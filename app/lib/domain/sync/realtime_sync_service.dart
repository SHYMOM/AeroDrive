import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/logger.dart';
import '../../core/providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/providers/security_providers.dart';
import '../../data/db/database.dart';
import '../../features/drive/providers/drive_providers.dart';
import '../../features/telegram/telegram_manager.dart';
import '../../features/telegram/telegram_service.dart';
import '../../features/trash/trash_screen.dart';
import '../recovery/manifest_encoder.dart';
import '../smart_analyzer.dart';
import 'config_sync_service.dart';

final realtimeSyncServiceProvider = Provider<RealtimeSyncService>((ref) {
  final service = RealtimeSyncService(ref);
  ref.onDispose(service.dispose);
  return service;
});

class RealtimeSyncService {
  RealtimeSyncService(this._ref);
  final Ref _ref;
  bool _isListening = false;
  bool _isCatchingUp = false;
  StreamSubscription? _allEventsSub;
  Timer? _periodicCatchUpTimer;
  int? _configChatId;

  void startListening() {
    if (_isListening) return;
    _isListening = true;

    // Listen to all Telegram events across all accounts via TelegramManager
    _allEventsSub?.cancel();
    _allEventsSub = _ref.read(telegramManagerProvider.notifier).allEvents.listen((event) {
      final type = event['@type'];
      if (type == 'updateDeleteMessages') {
        _handleDeleteMessages(event);
      } else if (type == 'updateNewMessage') {
        _handleNewMessage(event);
      } else if (type == 'updateMessageContent') {
        _handleMessageContent(event);
      }
    });

    // Listen to primary authState changes to initialize chats and catch up when logged in
    _ref.listen<TelegramAuthState>(telegramServiceProvider, (previous, next) {
      if (next == TelegramAuthState.ready) {
        _initializeBackgroundSyncChats();
        catchUp();
      }
    });

    // Also run immediately if already ready
    final currentStatus = _ref.read(telegramServiceProvider);
    if (currentStatus == TelegramAuthState.ready) {
      _initializeBackgroundSyncChats();
      catchUp();
    }

    // Periodic background catch-up sweep every 25 seconds
    _periodicCatchUpTimer?.cancel();
    _periodicCatchUpTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_isListening) {
        catchUp();
      }
    });
  }

  void stopListening() {
    _isListening = false;
    _allEventsSub?.cancel();
    _allEventsSub = null;
    _periodicCatchUpTimer?.cancel();
    _periodicCatchUpTimer = null;
  }

  void dispose() {
    stopListening();
  }

  Future<Set<int>> _getStorageChannelIds() async {
    final settingsRepo = _ref.read(settingsRepositoryProvider);
    final rawChannels = await settingsRepo.getSetting('storage_channels_list');
    final activeChannelStr = await settingsRepo.getSetting('active_channel_id');
    final Set<int> channelIds = {};

    if (rawChannels != null && rawChannels.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(rawChannels);
        for (final item in decoded) {
          final id = int.tryParse(item['id'].toString());
          if (id != null) channelIds.add(id);
        }
      } catch (_) {}
    }
    if (activeChannelStr != null && activeChannelStr.isNotEmpty) {
      final id = int.tryParse(activeChannelStr);
      if (id != null) channelIds.add(id);
    }
    return channelIds;
  }

  /// Incremental catch-up sync sweep:
  /// Queries recent messages from all storage channels to discover any uploads,
  /// folder creations, or changes made from other devices while this device was offline.
  Future<void> catchUp({bool force = false}) async {
    if (_isCatchingUp) return;
    _isCatchingUp = true;

    try {
      final masterKeyBytes = _ref.read(masterKeyProvider);
      if (masterKeyBytes == null) return;
      final masterKey = SecretKey(masterKeyBytes);

      final telegramAccounts = _ref.read(telegramManagerProvider);
      if (telegramAccounts.isEmpty) return;
      final primary = telegramAccounts.first;
      if (primary.authState != TelegramAuthState.ready) return;

      final channelIds = await _getStorageChannelIds();
      final db = _ref.read(databaseProvider);
      var dbChanged = false;

      for (final channelId in channelIds) {
        try {
          // Pre-open chat to maintain live TDLib subscription
          await primary.sendRequest({
            "@type": "openChat",
            "chat_id": channelId,
          });

          // Fetch recent messages
          final history = await primary.sendRequest({
            "@type": "getChatHistory",
            "chat_id": channelId,
            "from_message_id": 0,
            "offset": 0,
            "limit": 50,
            "only_local": false,
          });

          final messages = history['messages'] as List<dynamic>?;
          if (messages == null || messages.isEmpty) continue;

          var consecutiveKnown = 0;
          for (final msg in messages) {
            final msgMap = msg as Map<String, dynamic>;
            final messageId = msgMap['id'] as int?;
            if (messageId == null) continue;

            // Check if we already have this chunk locally
            final existingChunk = await (db.select(db.chunks)
              ..where((c) => c.channelId.equals(channelId) & c.messageId.equals(messageId)))
              .getSingleOrNull();

            if (existingChunk != null) {
              consecutiveKnown++;
              if (consecutiveKnown >= 5 && !force) {
                // Messages are newest-first; finding 5 consecutive known messages means caught up
                break;
              }
              continue;
            }

            final processed = await processMessage(msgMap, channelId, masterKey);
            if (processed) {
              dbChanged = true;
            }
          }
        } catch (e) {
          AppLogger.warning('RealtimeSync: catchUp failed for channel $channelId: $e');
        }
      }

      // Check remote config channel for drive state (trash, deletions, config updates)
      final configService = _ref.read(configSyncServiceProvider);
      final restoredConfig = await configService.restoreConfigFromChannel();
      if (restoredConfig != null && restoredConfig.isNotEmpty) {
        try {
          final Map<String, dynamic> configMap = jsonDecode(restoredConfig);
          final applied = await configService.applyRemoteDriveState(configMap);
          if (applied) dbChanged = true;
        } catch (_) {}
      }

      if (dbChanged) {
        _ref.read(dbRebuildVersionProvider.notifier).update((state) => state + 1);
        _ref.invalidate(folderContentsProvider);
        _ref.invalidate(trashedItemsProvider);
        AppLogger.info('RealtimeSync: Catch-up completed with new items synced.');
      }
    } catch (e, s) {
      AppLogger.error('RealtimeSync: catchUp error', e, s);
    } finally {
      _isCatchingUp = false;
    }
  }

  /// Processes a single Telegram message from a storage channel.
  /// Decodes encrypted manifest and inserts/updates local DB.
  Future<bool> processMessage(Map<String, dynamic> msg, int chatId, SecretKey masterKey) async {
    try {
      String? caption;
      if (msg['content'] != null && msg['content']['caption'] != null) {
        caption = msg['content']['caption']['text'] as String?;
      }
      caption ??= msg['caption'] as String?;
      if (caption == null || caption.isEmpty) return false;

      final manifest = await ManifestEncoder.decodeManifest(caption, masterKey);
      if (manifest == null) return false;

      final db = _ref.read(databaseProvider);
      const uuid = Uuid();
      var changed = false;

      await db.transaction(() async {
        if (manifest['t'] == 'dir') {
          final folderId = manifest['id'] as String;
          final existingFolder = await (db.select(db.folders)..where((f) => f.id.equals(folderId))).getSingleOrNull();

          final int? tsSeconds = manifest['ts'] as int?;
          final int? msgDate = msg['date'] as int?;
          final DateTime remoteDate = tsSeconds != null
              ? DateTime.fromMillisecondsSinceEpoch(tsSeconds * 1000)
              : (msgDate != null
                  ? DateTime.fromMillisecondsSinceEpoch(msgDate * 1000)
                  : DateTime.now());

          DateTime folderCreatedAt;
          if (existingFolder?.createdAt != null) {
            if (remoteDate.isBefore(existingFolder!.createdAt!)) {
              folderCreatedAt = remoteDate;
            } else {
              folderCreatedAt = existingFolder.createdAt!;
            }
          } else {
            folderCreatedAt = remoteDate;
          }

          await db.into(db.folders).insertOnConflictUpdate(
            FoldersCompanion.insert(
              id: folderId,
              name: manifest['name'] as String,
              parentId: drift.Value(manifest['pid'] as String?),
              color: drift.Value(manifest['col'] as String?),
              createdAt: drift.Value(folderCreatedAt),
              updatedAt: drift.Value(DateTime.now()),
            ),
          );
          changed = true;
          AppLogger.info('RealtimeSync: Added/Updated folder $folderId');
        } else if (manifest['t'] == 'thumb') {
          // Thumbnail manifests are handled on-demand by thumbnail service
        } else {
          final fileId = manifest['id'] as String;
          final existingFile = await (db.select(db.files)..where((f) => f.id.equals(fileId))).getSingleOrNull();

          final dekBase64 = manifest['k'] as String?;
          final ctrIvBase64 = manifest['iv'] as String?;

          String? wrappedDekString;
          if (dekBase64 != null) {
            if (ctrIvBase64 != null) {
              wrappedDekString = '$dekBase64|$ctrIvBase64';
            } else {
              wrappedDekString = dekBase64;
            }
          }

          final document = msg['content']?['document'];
          final size = manifest['size'] as int? ?? document?['document']?['size'] as int? ?? 0;
          final isChunkedVal = manifest['chk'] == 1;
          final totalChunksVal = manifest['tc'] as int? ?? (isChunkedVal ? (size / (20 * 1024 * 1024)).ceil() : 1);

          final int? docSize = document?['document']?['size'] as int?;
          final int chunkActualSize = isChunkedVal && totalChunksVal > 1
              ? (docSize ?? (size ~/ totalChunksVal))
              : size;

          final durationVal = manifest['dur'] as int?;
          final int? ptSeconds = manifest['pt'] as int?;
          final DateTime? photoTakenAt = ptSeconds != null
              ? DateTime.fromMillisecondsSinceEpoch(ptSeconds * 1000)
              : null;

          final int? tsSeconds = manifest['ts'] as int?;
          final int? msgDate = msg['date'] as int?;
          final DateTime remoteDate = tsSeconds != null
              ? DateTime.fromMillisecondsSinceEpoch(tsSeconds * 1000)
              : (msgDate != null
                  ? DateTime.fromMillisecondsSinceEpoch(msgDate * 1000)
                  : DateTime.now());

          DateTime fileCreatedAt;
          if (existingFile?.createdAt != null) {
            if (remoteDate.isBefore(existingFile!.createdAt!)) {
              fileCreatedAt = remoteDate;
            } else {
              fileCreatedAt = existingFile.createdAt!;
            }
          } else {
            fileCreatedAt = remoteDate;
          }

          await db.into(db.files).insertOnConflictUpdate(
            FilesCompanion.insert(
              id: fileId,
              name: manifest['name'] as String,
              folderId: drift.Value(manifest['pid'] as String?),
              size: drift.Value(size),
              mimeType: drift.Value(manifest['mime'] as String?),
              isEncrypted: drift.Value(manifest['enc'] == 1),
              isChunked: drift.Value(isChunkedVal),
              totalChunks: drift.Value(totalChunksVal),
              sha256Hash: drift.Value(wrappedDekString),
              createdAt: drift.Value(fileCreatedAt),
              updatedAt: drift.Value(DateTime.now()),
              photoTakenAt: drift.Value(photoTakenAt),
              duration: drift.Value(durationVal),
            ),
          );

          final chunkIndexVal = manifest['c'] as int? ?? 0;

          // Delete any existing chunk record for this (fileId, chunkIndex) to prevent duplicates
          await (db.delete(db.chunks)
            ..where((c) => c.fileId.equals(fileId))
            ..where((c) => c.chunkIndex.equals(chunkIndexVal))
          ).go();

          await db.into(db.chunks).insert(
            ChunksCompanion.insert(
              id: uuid.v4(),
              fileId: drift.Value(fileId),
              chunkIndex: drift.Value(chunkIndexVal),
              channelId: drift.Value(chatId),
              messageId: drift.Value(msg['id'] as int?),
              size: drift.Value(chunkActualSize),
            ),
          );

          try {
            final analyzer = SmartAnalyzer(db);
            await analyzer.syncMetadataFromManifest(manifest, fileId);
          } catch (e) {
            AppLogger.error('RealtimeSync: Failed to sync metadata for $fileId', e);
          }

          changed = true;
          AppLogger.info('RealtimeSync: Added/Updated file $fileId from remote message');
        }
      });

      return changed;
    } catch (e) {
      AppLogger.error('RealtimeSync: Error in processMessage', e);
      return false;
    }
  }

  Future<void> _handleDeleteMessages(Map<String, dynamic> event) async {
    try {
      if (event['from_cache'] == true) {
        AppLogger.info('RealtimeSync: Ignoring delete messages event because it is only from cache');
        return;
      }

      final chatId = event['chat_id'] as int?;
      final messageIds = (event['message_ids'] as List<dynamic>?)?.cast<int>();

      if (chatId == null || messageIds == null || messageIds.isEmpty) return;

      final db = _ref.read(databaseProvider);
      var dbChanged = false;

      for (final messageId in messageIds) {
        // Find if this message ID belongs to any chunk
        final chunkMatches = await (db.select(db.chunks)
          ..where((c) => c.channelId.equals(chatId) & c.messageId.equals(messageId)))
          .get();

        for (final chunk in chunkMatches) {
          if (chunk.fileId != null) {
            final fileId = chunk.fileId!;
            // Mark file as deleted locally
            final updatedCount = await (db.update(db.files)
              ..where((f) => f.id.equals(fileId) & f.deletedAt.isNull()))
              .write(FilesCompanion(
                deletedAt: drift.Value(DateTime.now()),
                updatedAt: drift.Value(DateTime.now()),
              ));

            if (updatedCount > 0) {
              dbChanged = true;
              AppLogger.info('RealtimeSync: Marked file $fileId as deleted (Chunk $messageId deleted remotely)');
            }
          }
        }

        // Find if this message ID belongs to a manifest directly in files table
        final manifestMatches = await (db.select(db.files)
          ..where((f) => f.manifestMessageId.equals(messageId) & f.deletedAt.isNull()))
          .get();

        for (final file in manifestMatches) {
          final updatedCount = await (db.update(db.files)
            ..where((f) => f.id.equals(file.id)))
            .write(FilesCompanion(
              deletedAt: drift.Value(DateTime.now()),
              updatedAt: drift.Value(DateTime.now()),
            ));

          if (updatedCount > 0) {
            dbChanged = true;
            AppLogger.info('RealtimeSync: Marked file ${file.id} as deleted (Manifest $messageId deleted remotely)');
          }
        }
      }

      if (dbChanged) {
        _ref.read(dbRebuildVersionProvider.notifier).update((state) => state + 1);
        _ref.invalidate(folderContentsProvider);
        _ref.invalidate(trashedItemsProvider);
      }
    } catch (e, s) {
      AppLogger.error('RealtimeSyncService: Error handling deleted messages', e, s);
    }
  }

  Future<void> _handleNewMessage(Map<String, dynamic> event) async {
    try {
      final msg = event['message'];
      if (msg == null) return;

      final chatId = msg['chat_id'] as int?;
      if (chatId == null) return;

      final configChatId = await _getConfigChatId();
      if (chatId == configChatId) {
        await _syncConfigFromChannelText(msg);
        return;
      }

      // Check if it's one of our storage channels
      final channelIds = await _getStorageChannelIds();
      if (!channelIds.contains(chatId)) return;

      final masterKeyBytes = _ref.read(masterKeyProvider);
      if (masterKeyBytes == null) return;
      final masterKey = SecretKey(masterKeyBytes);

      final dbChanged = await processMessage(msg, chatId, masterKey);
      if (dbChanged) {
        _ref.read(dbRebuildVersionProvider.notifier).update((state) => state + 1);
        _ref.invalidate(folderContentsProvider);
      }
    } catch (e, s) {
      AppLogger.error('RealtimeSyncService: Error handling new message', e, s);
    }
  }

  Future<int?> _getConfigChatId() async {
    if (_configChatId != null) return _configChatId;

    final telegramAccounts = _ref.read(telegramManagerProvider);
    if (telegramAccounts.isNotEmpty && telegramAccounts.first.authState == TelegramAuthState.ready) {
      try {
        final configService = _ref.read(configSyncServiceProvider);
        _configChatId = await configService.findConfigChannel();
      } catch (_) {}
    }
    return _configChatId;
  }

  Future<void> _syncConfigFromChannelText(Map<String, dynamic> msg) async {
    try {
      if (msg['content']?['@type'] == 'messageText') {
        final text = msg['content']['text']['text'] as String?;
        if (text != null && text.contains('WARNING: DO NOT DELETE')) {
          final parts = text.split('\n\n');
          if (parts.length >= 3) {
            final encryptedBase64 = parts.last.trim();
            final encryptedBytes = base64Decode(encryptedBase64);

            final secretBox = SecretBox.fromConcatenation(
              encryptedBytes,
              nonceLength: 12,
              macLength: 16,
            );

            final masterKeyBytes = _ref.read(masterKeyProvider);
            if (masterKeyBytes == null) return;

            final masterKey = SecretKey(masterKeyBytes);
            final algorithm = AesGcm.with256bits();
            final decryptedBytes = await algorithm.decrypt(
              secretBox,
              secretKey: masterKey,
            );

            final decryptedConfig = utf8.decode(decryptedBytes);
            if (decryptedConfig.isNotEmpty) {
              final Map<String, dynamic> configMap = jsonDecode(decryptedConfig);
              final remoteLww = configMap['lww_timestamp'] as int? ?? 0;

              final settingsRepo = _ref.read(settingsRepositoryProvider);
              final localLwwStr = await settingsRepo.getSetting('config_lww_timestamp');
              final localLww = int.tryParse(localLwwStr ?? '') ?? 0;

              var configUpdated = false;
              if (remoteLww > localLww) {
                final rawChannels = configMap['storage_channels_list'] as String? ?? '[]';
                final activeChannel = configMap['active_channel_id'] as String? ?? '';
                final publicShareChannelId = configMap['public_share_channel_id'] as String? ?? '';
                final publicShareChannelUsername = configMap['public_share_channel_username'] as String? ?? '';
                final publicShareChannelInvite = configMap['public_share_channel_invite'] as String? ?? '';
                final tempJoined = configMap['temp_joined_sharing_channels'] as String? ?? '[]';

                await settingsRepo.setSetting('storage_channels_list', rawChannels);
                await settingsRepo.setSetting('active_channel_id', activeChannel);
                await settingsRepo.setSetting('public_share_channel_id', publicShareChannelId);
                await settingsRepo.setSetting('public_share_channel_username', publicShareChannelUsername);
                await settingsRepo.setSetting('public_share_channel_invite', publicShareChannelInvite);
                await settingsRepo.setSetting('temp_joined_sharing_channels', tempJoined);
                await settingsRepo.setSetting('config_lww_timestamp', remoteLww.toString());
                AppLogger.info('RealtimeSync: Configuration updated in real-time ($remoteLww > $localLww)');
                configUpdated = true;
              }

              // Apply remote drive state (trashed items, restored items, tombstones)
              final configService = _ref.read(configSyncServiceProvider);
              final driveStateApplied = await configService.applyRemoteDriveState(configMap);

              if (configUpdated || driveStateApplied) {
                _ref.read(dbRebuildVersionProvider.notifier).update((state) => state + 1);
                _ref.invalidate(folderContentsProvider);
                _ref.invalidate(trashedItemsProvider);
              }
            }
          }
        }
      }
    } catch (e, s) {
      AppLogger.error('RealtimeSync: Error parsing config update from chat text', e, s);
    }
  }

  Future<void> _handleMessageContent(Map<String, dynamic> event) async {
    try {
      final chatId = event['chat_id'] as int?;
      if (chatId == null) return;

      final configChatId = await _getConfigChatId();
      if (chatId == configChatId) {
        final mockMsg = {
          'chat_id': chatId,
          'id': event['message_id'],
          'content': event['new_content'],
        };
        await _syncConfigFromChannelText(mockMsg);
      }
    } catch (e, s) {
      AppLogger.error('RealtimeSyncService: Error handling message content update', e, s);
    }
  }

  Future<void> _initializeBackgroundSyncChats() async {
    try {
      final channelIds = await _getStorageChannelIds();
      final configChatId = await _getConfigChatId();
      final Set<int> allChatIds = {...channelIds};
      if (configChatId != null) {
        allChatIds.add(configChatId);
      }

      final telegramAccounts = _ref.read(telegramManagerProvider);
      if (telegramAccounts.isNotEmpty) {
        final primary = telegramAccounts.first;
        if (primary.authState == TelegramAuthState.ready) {
          for (final chatId in allChatIds) {
            try {
              await primary.sendRequest({
                "@type": "getChat",
                "chat_id": chatId,
              });
              await primary.sendRequest({
                "@type": "openChat",
                "chat_id": chatId,
              });
              AppLogger.info('RealtimeSync: Pre-opened channel $chatId for background updates');
            } catch (e) {
              AppLogger.warning('RealtimeSync: Failed to pre-open channel $chatId: $e');
            }
          }
        }
      }
    } catch (e) {
      AppLogger.error('RealtimeSync: Failed to initialize background chats', e);
    }
  }
}
