import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/logger.dart';
import '../../core/providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/providers/security_providers.dart';
import '../../data/db/database.dart';
import '../../features/drive/providers/drive_providers.dart';
import '../../features/telegram/telegram_service.dart';
import '../../features/trash/trash_screen.dart';

enum ConfigStatus {
  synced,
  found_unrestored,
  missing,
  missing_message,
  error
}

class ConfigSyncService {

  ConfigSyncService(this._ref);
  final Ref _ref;
  static const String _configChannelName = 'AeroDrive Config';
  static const String _configWarningText = 
      '⚠️ WARNING: DO NOT DELETE THIS MESSAGE OR CHANNEL ⚠️\n\n'
      'This channel is automatically created by AeroDrive to store your storage configuration across devices. '
      'If you delete this, you may lose the ability to easily restore your files on a new device.\n\n';

  Future<void> syncConfigToChannel() async {
    final telegramService = _ref.read(telegramServiceProvider.notifier);
    final masterKeyBytes = _ref.read(masterKeyProvider);
    final settingsRepo = _ref.read(settingsRepositoryProvider);

    if (masterKeyBytes == null) {
      AppLogger.warning('ConfigSyncService: masterKey is null');
      return;
    }

    final rawChannels = await settingsRepo.getSetting('storage_channels_list');
    if (rawChannels == null || rawChannels.isEmpty || rawChannels == '[]') {
      AppLogger.warning('ConfigSyncService: Refusing to sync empty storage_channels_list to remote channel!');
      return;
    }
    final activeChannel = await settingsRepo.getSetting('active_channel_id');
    final publicShareChannelId = await settingsRepo.getSetting('public_share_channel_id');
    final publicShareChannelUsername = await settingsRepo.getSetting('public_share_channel_username');
    final publicShareChannelInvite = await settingsRepo.getSetting('public_share_channel_invite');
    final tempJoined = await settingsRepo.getSetting('temp_joined_sharing_channels');

    final nowLww = DateTime.now().millisecondsSinceEpoch;
    await settingsRepo.setSetting('config_lww_timestamp', nowLww.toString());

    // Collect currently trashed files and folders
    final db = _ref.read(databaseProvider);
    final trashedFiles = await (db.select(db.files)..where((f) => f.deletedAt.isNotNull())).get();
    final trashedFolders = await (db.select(db.folders)..where((f) => f.deletedAt.isNotNull())).get();

    final Map<String, int> trashedFilesMap = {};
    for (final f in trashedFiles) {
      if (f.deletedAt != null) {
        trashedFilesMap[f.id] = f.deletedAt!.millisecondsSinceEpoch ~/ 1000;
      }
    }

    final Map<String, int> trashedFoldersMap = {};
    for (final f in trashedFolders) {
      if (f.deletedAt != null) {
        trashedFoldersMap[f.id] = f.deletedAt!.millisecondsSinceEpoch ~/ 1000;
      }
    }

    // Read recently deleted IDs (tombstones for permanently purged items)
    final deletedFilesJson = await settingsRepo.getSetting('tombstone_deleted_files');
    final deletedFoldersJson = await settingsRepo.getSetting('tombstone_deleted_folders');
    final List<String> deletedFilesList = deletedFilesJson != null ? List<String>.from(jsonDecode(deletedFilesJson)) : [];
    final List<String> deletedFoldersList = deletedFoldersJson != null ? List<String>.from(jsonDecode(deletedFoldersJson)) : [];

    final configMap = {
      'storage_channels_list': rawChannels ?? '[]',
      'active_channel_id': activeChannel ?? '',
      'public_share_channel_id': publicShareChannelId ?? '',
      'public_share_channel_username': publicShareChannelUsername ?? '',
      'public_share_channel_invite': publicShareChannelInvite ?? '',
      'temp_joined_sharing_channels': tempJoined ?? '[]',
      'trashed_files': trashedFilesMap,
      'trashed_folders': trashedFoldersMap,
      'deleted_file_ids': deletedFilesList,
      'deleted_folder_ids': deletedFoldersList,
      'lww_timestamp': nowLww,
    };
    final String configToSync = jsonEncode(configMap);

    try {
      final masterKey = SecretKey(masterKeyBytes);
      final plaintext = utf8.encode(configToSync);
      
      final algorithm = AesGcm.with256bits();
      final secretBox = await algorithm.encrypt(
        plaintext,
        secretKey: masterKey,
      );

      final encryptedConfig = base64Encode(secretBox.concatenation());
      final fullText = '$_configWarningText$encryptedConfig';

      int? configChatId = await findConfigChannel();

      if (configChatId == null) {
        // Create the channel
        AppLogger.info('ConfigSyncService: Creating config channel');
        final response = await telegramService.createNewChannel(_configChannelName, 'AeroDrive System Channel [AERODRIVE_CONFIG_v1]');
        if (response['@type'] == 'error') {
          AppLogger.error('ConfigSyncService: Failed to create channel: ${response['message']}');
          return;
        }
        configChatId = response['id'];
        
        // Wait a bit for TDLib to process
        await Future.delayed(const Duration(seconds: 1));

        // Archive and mute
        await _archiveAndMute(telegramService, configChatId!);

        // Set channel icon
        await _setChannelIcon(telegramService, configChatId);
      }

      // Send or update the pinned message
      final history = await telegramService.sendRequest({
        "@type": "searchChatMessages",
        "chat_id": configChatId,
        "query": "WARNING: DO NOT DELETE",
        "limit": 10
      });

      int? existingMessageId;
      if (history['messages'] != null) {
        for (final msg in history['messages']) {
          if (msg['content']?['@type'] == 'messageText') {
            final text = msg['content']['text']['text'] as String?;
            if (text != null && text.contains('WARNING: DO NOT DELETE')) {
              existingMessageId = msg['id'];
              break;
            }
          }
        }
      }

      bool editedSuccessfully = false;

      if (existingMessageId != null) {
        // Edit existing message
        final editResult = await telegramService.sendRequest({
          "@type": "editMessageText",
          "chat_id": configChatId,
          "message_id": existingMessageId,
          "input_message_content": {
            "@type": "inputMessageText",
            "text": {
              "@type": "formattedText",
              "text": fullText,
              "entities": []
            },
            "disable_web_page_preview": true,
            "clear_draft": true
          }
        });
        
        if (editResult['@type'] != 'error') {
          editedSuccessfully = true;
        } else {
          AppLogger.warning('ConfigSyncService: editMessageText failed, falling back to new message. Error: ${editResult['message']}');
          // Try to delete the old message if editing failed
          await telegramService.sendRequest({
            "@type": "deleteMessages",
            "chat_id": configChatId,
            "message_ids": [existingMessageId],
            "revoke": true
          });
        }
      }

      if (!editedSuccessfully) {
        // Send new message
        final sentMessage = await telegramService.sendRequest({
          "@type": "sendMessage",
          "chat_id": configChatId,
          "input_message_content": {
            "@type": "inputMessageText",
            "text": {
              "@type": "formattedText",
              "text": fullText,
              "entities": []
            },
            "disable_web_page_preview": true,
            "clear_draft": true
          }
        });
        
        if (sentMessage['@type'] != 'error') {
          // Try to pin it — may fail if channel restricts pinning
          try {
            await telegramService.sendRequest({
              "@type": "pinChatMessage",
              "chat_id": configChatId,
              "message_id": sentMessage['id'],
              "disable_notification": true,
              "only_for_self": false
            });
          } catch (pinError) {
            AppLogger.warning('ConfigSyncService: Could not pin config message (non-fatal): $pinError');
          }
        }
      }

      AppLogger.info('ConfigSyncService: Config successfully synced to channel.');
      await syncTelegramFolder();
    } catch (e, s) {
      AppLogger.error('ConfigSyncService: Error syncing config', e, s);
    }
  }

  /// Records permanent deletion tombstones and syncs config to Telegram.
  Future<void> recordPermanentDeletion({List<String>? fileIds, List<String>? folderIds}) async {
    final settingsRepo = _ref.read(settingsRepositoryProvider);
    if (fileIds != null && fileIds.isNotEmpty) {
      final existingJson = await settingsRepo.getSetting('tombstone_deleted_files');
      final List<String> list = existingJson != null ? List<String>.from(jsonDecode(existingJson)) : [];
      list.addAll(fileIds);
      final capped = list.toSet().toList();
      if (capped.length > 500) capped.removeRange(0, capped.length - 500);
      await settingsRepo.setSetting('tombstone_deleted_files', jsonEncode(capped));
    }
    if (folderIds != null && folderIds.isNotEmpty) {
      final existingJson = await settingsRepo.getSetting('tombstone_deleted_folders');
      final List<String> list = existingJson != null ? List<String>.from(jsonDecode(existingJson)) : [];
      list.addAll(folderIds);
      final capped = list.toSet().toList();
      if (capped.length > 500) capped.removeRange(0, capped.length - 500);
      await settingsRepo.setSetting('tombstone_deleted_folders', jsonEncode(capped));
    }
    await syncConfigToChannel();
  }

  /// Applies remote drive state (trashed items, restored items, tombstones) to local SQLite.
  Future<bool> applyRemoteDriveState(Map<String, dynamic> configMap) async {
    try {
      final db = _ref.read(databaseProvider);
      var dbChanged = false;

      // 1. Permanently deleted items (tombstones)
      final deletedFileIds = (configMap['deleted_file_ids'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
      final deletedFolderIds = (configMap['deleted_folder_ids'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

      if (deletedFileIds.isNotEmpty) {
        final deletedChunksCount = await (db.delete(db.chunks)..where((c) => c.fileId.isIn(deletedFileIds))).go();
        final deletedThumbCount = await (db.delete(db.thumbnails)..where((t) => t.fileId.isIn(deletedFileIds))).go();
        final deletedFilesCount = await (db.delete(db.files)..where((f) => f.id.isIn(deletedFileIds))).go();
        if (deletedFilesCount > 0 || deletedChunksCount > 0 || deletedThumbCount > 0) {
          dbChanged = true;
          AppLogger.info('ConfigSyncService: Purged $deletedFilesCount files and $deletedChunksCount chunks from tombstones');
        }
      }

      if (deletedFolderIds.isNotEmpty) {
        final count = await (db.delete(db.folders)..where((f) => f.id.isIn(deletedFolderIds))).go();
        if (count > 0) {
          dbChanged = true;
          AppLogger.info('ConfigSyncService: Purged $count folders from tombstones');
        }
      }

      // 2. Trashed files
      final remoteTrashedFiles = (configMap['trashed_files'] as Map<String, dynamic>?) ?? {};
      for (final entry in remoteTrashedFiles.entries) {
        final fileId = entry.key;
        final int? sec = entry.value as int?;
        final dt = sec != null ? DateTime.fromMillisecondsSinceEpoch(sec * 1000) : DateTime.now();

        final updated = await (db.update(db.files)
          ..where((f) => f.id.equals(fileId) & f.deletedAt.isNull()))
          .write(FilesCompanion(
            deletedAt: drift.Value(dt),
            updatedAt: drift.Value(DateTime.now()),
          ));
        if (updated > 0) {
          dbChanged = true;
          AppLogger.info('ConfigSyncService: File $fileId marked as trashed remotely');
        }
      }

      // 3. Trashed folders
      final remoteTrashedFolders = (configMap['trashed_folders'] as Map<String, dynamic>?) ?? {};
      for (final entry in remoteTrashedFolders.entries) {
        final folderId = entry.key;
        final int? sec = entry.value as int?;
        final dt = sec != null ? DateTime.fromMillisecondsSinceEpoch(sec * 1000) : DateTime.now();

        final updated = await (db.update(db.folders)
          ..where((f) => f.id.equals(folderId) & f.deletedAt.isNull()))
          .write(FoldersCompanion(
            deletedAt: drift.Value(dt),
            updatedAt: drift.Value(DateTime.now()),
          ));
        if (updated > 0) {
          dbChanged = true;
          AppLogger.info('ConfigSyncService: Folder $folderId marked as trashed remotely');
        }
      }

      // 4. Restored files/folders (items that are currently trashed locally, but NOT in remote trashed map and NOT in deleted list)
      final localTrashedFiles = await (db.select(db.files)..where((f) => f.deletedAt.isNotNull())).get();
      for (final file in localTrashedFiles) {
        if (!remoteTrashedFiles.containsKey(file.id) && !deletedFileIds.contains(file.id)) {
          // File was restored remotely
          await (db.update(db.files)..where((f) => f.id.equals(file.id)))
              .write(const FilesCompanion(deletedAt: drift.Value(null)));
          dbChanged = true;
          AppLogger.info('ConfigSyncService: File ${file.id} restored remotely');
        }
      }

      final localTrashedFolders = await (db.select(db.folders)..where((f) => f.deletedAt.isNotNull())).get();
      for (final folder in localTrashedFolders) {
        if (!remoteTrashedFolders.containsKey(folder.id) && !deletedFolderIds.contains(folder.id)) {
          // Folder was restored remotely
          await (db.update(db.folders)..where((f) => f.id.equals(folder.id)))
              .write(const FoldersCompanion(deletedAt: drift.Value(null)));
          dbChanged = true;
          AppLogger.info('ConfigSyncService: Folder ${folder.id} restored remotely');
        }
      }

      if (dbChanged) {
        _ref.read(dbRebuildVersionProvider.notifier).update((v) => v + 1);
        _ref.invalidate(folderContentsProvider);
        _ref.invalidate(trashedItemsProvider);
      }
      return dbChanged;
    } catch (e, s) {
      AppLogger.error('ConfigSyncService: Error applying remote drive state', e, s);
      return false;
    }
  }

  Future<ConfigStatus> checkConfigStatus() async {
    final telegramService = _ref.read(telegramServiceProvider.notifier);
    final masterKeyBytes = _ref.read(masterKeyProvider);
    final settingsRepo = _ref.read(settingsRepositoryProvider);

    if (masterKeyBytes == null) return ConfigStatus.error;

    try {
      final int? configChatId = await findConfigChannel();
      if (configChatId == null) return ConfigStatus.missing;

      final restoredConfig = await restoreConfigFromChannel();
      final localConfig = await settingsRepo.getSetting('storage_channels_list');
      
      bool hasRestored = false;
      if (restoredConfig != null && restoredConfig.isNotEmpty) {
        if (restoredConfig.startsWith('{')) {
          final Map<String, dynamic> configMap = jsonDecode(restoredConfig);
          final rawChannels = configMap['storage_channels_list'] as String? ?? '[]';
          hasRestored = rawChannels != '[]';
        } else {
          hasRestored = restoredConfig != '[]';
        }
      }

      if (hasRestored) {
        if (localConfig == null || localConfig.isEmpty || localConfig == '[]') {
          return ConfigStatus.found_unrestored;
        } else {
          return ConfigStatus.synced;
        }
      } else {
        if (localConfig != null && localConfig.isNotEmpty && localConfig != '[]') {
          return ConfigStatus.missing_message;
        } else {
          return ConfigStatus.missing;
        }
      }
    } catch (e) {
      return ConfigStatus.error;
    }
  }

  Future<String?> restoreConfigFromChannel() async {
    final telegramService = _ref.read(telegramServiceProvider.notifier);
    final masterKeyBytes = _ref.read(masterKeyProvider);

    if (masterKeyBytes == null) return null;

    try {
      final int? configChatId = await findConfigChannel();
      if (configChatId == null) return null;

      final history = await telegramService.sendRequest({
        "@type": "getChatHistory",
        "chat_id": configChatId,
        "from_message_id": 0,
        "offset": 0,
        "limit": 20,
        "only_local": false,
      });

      final List<dynamic> allMessages = [];
      if (history['messages'] != null) {
        allMessages.addAll(history['messages']);
      }

      if (allMessages.isEmpty || !allMessages.any((m) => m['content']?['text']?['text']?.toString().contains('WARNING: DO NOT DELETE') ?? false)) {
        try {
          final searchRes = await telegramService.sendRequest({
            "@type": "searchChatMessages",
            "chat_id": configChatId,
            "query": "WARNING: DO NOT DELETE",
            "limit": 10,
          });
          if (searchRes['messages'] != null) {
            allMessages.addAll(searchRes['messages']);
          }
        } catch (_) {}
      }

      for (final msg in allMessages) {
        if (msg['content']?['@type'] == 'messageText') {
          final text = msg['content']['text']['text'] as String?;
          if (text != null && text.contains('WARNING: DO NOT DELETE')) {
            // Extract base64 encrypted string
            final parts = text.split('\n\n');
            if (parts.isNotEmpty) {
              final encryptedBase64 = parts.last.trim();
              final encryptedBytes = base64Decode(encryptedBase64);
              
              final secretBox = SecretBox.fromConcatenation(
                encryptedBytes,
                nonceLength: 12,
                macLength: 16,
              );
              
              final masterKey = SecretKey(masterKeyBytes);
              final algorithm = AesGcm.with256bits();
              final decryptedBytes = await algorithm.decrypt(
                secretBox,
                secretKey: masterKey,
              );
              
              return utf8.decode(decryptedBytes);
            }
          }
        }
      }
    } catch (e, s) {
      AppLogger.error('ConfigSyncService: Error restoring config', e, s);
    }
    return null;
  }

  Future<int?> findConfigChannel() async {
    final telegramService = _ref.read(telegramServiceProvider.notifier);
    
    // Attempt 1: Search on server (very reliable for finding un-cached channels)
    try {
      final searchResponse = await telegramService.sendRequest({
        "@type": "searchChats",
        "query": "AeroDrive Config",
        "limit": 10
      });
      if (searchResponse['chat_ids'] != null) {
        int? fallbackId;
        for (final id in searchResponse['chat_ids']) {
           final chat = await telegramService.sendRequest({"@type": "getChat", "chat_id": id});
           if (chat['title'] == _configChannelName || chat['title'] == 'AeroDrive Config (Do Not Delete)') {
             final adminCheck = await telegramService.checkAdminStatus(id);
             if (adminCheck['is_admin'] == true) {
                final description = await telegramService.getChannelDescription(id);
                if (description != null && (description.contains('[AERODRIVE_CONFIG_v1]') || description.contains('AERODRIVE_INFRA_v1:'))) {
                   return id; // Exact match found
                }
                fallbackId ??= id; // Save first valid channel as fallback
             }
           }
        }
        if (fallbackId != null) return fallbackId;
      }
    } catch (e) {
      AppLogger.warning('searchChatsOnServer failed: $e');
    }

    // Attempt 2: Fallback to local admin channels (loads both main and archive)
    final channels = await telegramService.getAdminChannels();
    for (final channel in channels) {
      final title = channel['title'] as String?;
      final chatId = channel['id'] as int?;
      if (chatId == null) continue;

      if (title == _configChannelName || title == 'AeroDrive Config (Do Not Delete)') {
        return chatId;
      }

      // Check description marker
      try {
        final description = await telegramService.getChannelDescription(chatId);
        if (description != null && (description.contains('[AERODRIVE_CONFIG_v1]') || description.contains('"p":"config"'))) {
          return chatId;
        }
      } catch (_) {}
    }

    // Attempt 3: Search specifically in archived chats
    final archivedId = await findInArchivedChats();
    if (archivedId != null) return archivedId;

    return null;
  }

  Future<int?> findInArchivedChats() async {
    final telegramService = _ref.read(telegramServiceProvider.notifier);
    try {
      await telegramService.loadChatList({"@type": "chatListArchive"}, maxBatches: 3);
      final response = await telegramService.sendRequest({
        "@type": "getChats",
        "chat_list": {"@type": "chatListArchive"},
        "limit": 200
      });
      if (response['chat_ids'] != null) {
        for (final chatId in response['chat_ids']) {
          final chat = await telegramService.sendRequest({"@type": "getChat", "chat_id": chatId});
          final title = chat['title'] as String?;
          if (title == _configChannelName || title == 'AeroDrive Config (Do Not Delete)') {
            return chatId;
          }
          final description = await telegramService.getChannelDescription(chatId);
          if (description != null && (description.contains('[AERODRIVE_CONFIG_v1]') || description.contains('"p":"config"'))) {
            return chatId;
          }
        }
      }
    } catch (e) {
      AppLogger.warning('findInArchivedChats failed: $e');
    }
    return null;
  }

  Future<void> _archiveAndMute(TelegramService telegramService, int chatId) async {
    // Archive
    await telegramService.sendRequest({
      "@type": "addChatToList",
      "chat_id": chatId,
      "chat_list": {"@type": "chatListArchive"}
    });

    // Mute forever
    await telegramService.sendRequest({
      "@type": "setChatNotificationSettings",
      "chat_id": chatId,
      "notification_settings": {
        "@type": "chatNotificationSettings",
        "use_default_mute_for": false,
        "mute_for": 2147483647,
        "use_default_sound": false,
        "sound_id": 0,
        "use_default_show_preview": false,
        "show_preview": false,
        "use_default_disable_pinned_message_notifications": false,
        "disable_pinned_message_notifications": true,
        "use_default_disable_mention_notifications": false,
        "disable_mention_notifications": true
      }
    });
  }

  Future<void> _setChannelIcon(TelegramService telegramService, int chatId) async {
    try {
      // 1. Load icon from assets
      final byteData = await rootBundle.load('assets/icon.png');
      final buffer = byteData.buffer;

      // 2. Save it to a temporary file
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/aerodrive_icon.png');
      await tempFile.writeAsBytes(buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));

      // 3. Upload and set as chat photo
      await telegramService.sendRequest({
        "@type": "setChatPhoto",
        "chat_id": chatId,
        "photo": {
          "@type": "inputChatPhotoStatic",
          "photo": {
            "@type": "inputFileLocal",
            "path": tempFile.path
          }
        }
      });
      AppLogger.info('ConfigSyncService: Set channel icon successfully.');
    } catch (e, s) {
      AppLogger.error('ConfigSyncService: Error setting channel icon', e, s);
    }
  }

  /// Synchronizes Telegram Chat Filter Folder grouping all app-related channels.
  Future<void> syncTelegramFolder() async {
    final telegramService = _ref.read(telegramServiceProvider.notifier);
    final settingsRepo = _ref.read(settingsRepositoryProvider);

    final Set<int> chatIds = {};

    // 1. Add storage channels
    final savedChannelsJson = await settingsRepo.getSetting('storage_channels_list');
    if (savedChannelsJson != null && savedChannelsJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(savedChannelsJson);
        for (final ch in decoded) {
          final id = ch['id'];
          if (id != null) {
            chatIds.add(id is String ? int.parse(id) : id as int);
          }
        }
      } catch (e) {
        AppLogger.error('syncTelegramFolder: failed to parse storage_channels_list', e);
      }
    }

    // 2. Add public share channel
    final publicShareChannelId = await settingsRepo.getSetting('public_share_channel_id');
    if (publicShareChannelId != null && publicShareChannelId.isNotEmpty) {
      final id = int.tryParse(publicShareChannelId);
      if (id != null) chatIds.add(id);
    }

    // 3. Add config channel
    final configChannelId = await findConfigChannel();
    if (configChannelId != null) {
      chatIds.add(configChannelId);
    }

    if (chatIds.isNotEmpty) {
      await telegramService.updateTelegramFolder(chatIds.toList());
    }
  }
}

final configSyncServiceProvider = Provider<ConfigSyncService>(ConfigSyncService.new);
