import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cryptography/cryptography.dart';
import 'package:aerodrive/domain/recovery/manifest_encoder.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:drift/drift.dart' as drift;
import 'package:aerodrive/features/telegram/telegram_service.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:uuid/uuid.dart';

class ZeroDBRecoveryService {
  final Ref _ref;
  final AeroDriveDatabase _db;
  final TelegramService _telegramService;

  ZeroDBRecoveryService(this._ref, this._db, this._telegramService);

  /// Scans Telegram storage channels and reconstructs the local SQLite database.
  Future<void> runDisasterRecovery({
    required SecretKey masterKey,
    // Optional fallback channelId if storage_channels_list is empty
    int? channelId,
    Function(int messagesScanned, int itemsRecovered)? onProgress,
  }) async {
    int messagesScanned = 0;
    int itemsRecovered = 0;

    // 1. Resolve channel IDs to scan
    final settingsRepo = _ref.read(settingsRepositoryProvider);
    final savedChannelsJson = await settingsRepo.getSetting('storage_channels_list');
    List<int> channelsToScan = [];

    if (savedChannelsJson != null && savedChannelsJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(savedChannelsJson);
        for (final ch in decoded) {
          final id = ch['id'];
          if (id != null) {
            channelsToScan.add(id is String ? int.parse(id) : id as int);
          }
        }
      } catch (_) {}
    }

    if (channelsToScan.isEmpty && channelId != null) {
      channelsToScan.add(channelId);
    }

    if (channelsToScan.isEmpty) {
      debugPrint("ZeroDBRecovery: No channels configured to scan.");
      return;
    }

    final List<FoldersCompanion> recoveredFolders = [];
    final List<FilesCompanion> recoveredFiles = [];
    final List<ChunksCompanion> recoveredChunks = [];
    final Set<String> recoveredFolderIds = {};
    final Set<String> recoveredFileIds = {};
    final Uuid uuid = const Uuid();

    // 2. Scan each channel
    for (final scanChannelId in channelsToScan) {
      int lastMessageId = 0;
      while (true) {
        final response = await _telegramService.sendRequest({
          "@type": "getChatHistory",
          "chat_id": scanChannelId,
          "from_message_id": lastMessageId,
          "offset": 0,
          "limit": 100,
          "only_local": false,
        });

        final List<dynamic>? messages = response['messages'];
        if (messages == null || messages.isEmpty) {
          break;
        }

        for (final msg in messages) {
          messagesScanned++;
          if (messagesScanned % 10 == 0) {
            onProgress?.call(messagesScanned, itemsRecovered);
          }

          String? caption;
          if (msg['content'] != null && msg['content']['caption'] != null) {
            caption = msg['content']['caption']['text'] as String?;
          }
          caption ??= msg['caption'] as String?; // Fallback

          if (caption == null || caption.isEmpty) continue;

          // Decode caption
          final manifest = await ManifestEncoder.decodeManifest(caption, masterKey);
          if (manifest == null) continue;

          itemsRecovered++;

          if (manifest['t'] == 'dir') {
            final folderId = manifest['id'] as String;
            recoveredFolderIds.add(folderId);
            recoveredFolders.add(
              FoldersCompanion.insert(
                id: folderId,
                name: manifest['name'] as String,
                parentId: drift.Value(manifest['pid'] as String?), // Can be null
                color: drift.Value(manifest['col'] as String?),
                createdAt: drift.Value(DateTime.now()), 
                updatedAt: drift.Value(DateTime.now()),
              ),
            );
          } else {
            final fileId = manifest['id'] as String;
            recoveredFileIds.add(fileId);
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

            final existingFile = recoveredFiles.any((f) => f.id.value == fileId);
            if (!existingFile) {
              final document = msg['content']?['document'];
              final size = document?['document']?['size'] as int? ?? manifest['size'] as int? ?? 0;
              recoveredFiles.add(
                FilesCompanion.insert(
                  id: fileId,
                  name: manifest['name'] as String,
                  folderId: drift.Value(manifest['pid'] as String?),
                  size: drift.Value(size),
                  mimeType: drift.Value(manifest['mime'] as String?),
                  isEncrypted: drift.Value(manifest['enc'] == 1),
                  isChunked: drift.Value(manifest['chk'] == 1),
                  sha256Hash: drift.Value(wrappedDekString),
                  createdAt: drift.Value(DateTime.now()),
                ),
              );
            }

            recoveredChunks.add(
              ChunksCompanion.insert(
                id: uuid.v4(),
                fileId: drift.Value(fileId),
                chunkIndex: drift.Value(manifest['c'] as int? ?? 0),
                channelId: drift.Value(scanChannelId),
                messageId: drift.Value(msg['id'] as int?),
                size: drift.Value(msg['content']?['document']?['document']?['size'] as int?),
              ),
            );
          }
        }

        final nextLastMessageId = messages.last['id'] as int;
        if (nextLastMessageId == lastMessageId) {
          break; // Prevent infinite loop
        }
        lastMessageId = nextLastMessageId;
      }
    }

    // 3. Update database in transaction
    await _db.transaction(() async {
      // Upsert Folders
      if (recoveredFolders.isNotEmpty) {
        await _db.batch((batch) {
          batch.insertAllOnConflictUpdate(_db.folders, recoveredFolders);
        });
      }
      
      // Upsert Files
      if (recoveredFiles.isNotEmpty) {
        await _db.batch((batch) {
          batch.insertAllOnConflictUpdate(_db.files, recoveredFiles);
        });
      }

      // Re-insert Chunks
      if (recoveredChunks.isNotEmpty) {
        final List<String> fileIdsToClear = recoveredChunks.map((c) => c.fileId.value!).toSet().toList();
        for (final fid in fileIdsToClear) {
          await (_db.delete(_db.chunks)..where((c) => c.fileId.equals(fid))).go();
        }
        await _db.batch((batch) {
          batch.insertAllOnConflictUpdate(_db.chunks, recoveredChunks);
        });
      }

      // 4. Prune database records not found in Telegram (handling deletions)
      final allFiles = await _db.select(_db.files).get();
      for (final f in allFiles) {
        if (!recoveredFileIds.contains(f.id)) {
          // Delete chunks and file
          await (_db.delete(_db.chunks)..where((c) => c.fileId.equals(f.id))).go();
          await (_db.delete(_db.files)..where((file) => file.id.equals(f.id))).go();
        }
      }

      final allFolders = await _db.select(_db.folders).get();
      for (final f in allFolders) {
        if (!recoveredFolderIds.contains(f.id)) {
          await (_db.delete(_db.folders)..where((folder) => folder.id.equals(f.id))).go();
        }
      }
    });

    onProgress?.call(messagesScanned, itemsRecovered);
    debugPrint("ZeroDB disaster recovery scan complete! Recovered $itemsRecovered items.");
  }
}

// Retain alias for UI/GoRouter compatibility
typedef RecoveryScanner = ZeroDBRecoveryService;

final recoveryServiceProvider = Provider<ZeroDBRecoveryService>((ref) {
  final db = ref.read(databaseProvider);
  final telegram = ref.read(telegramServiceProvider.notifier);
  return ZeroDBRecoveryService(ref, db, telegram);
});
