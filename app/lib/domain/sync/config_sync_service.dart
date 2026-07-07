import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/logger.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/providers/security_providers.dart';
import '../../features/telegram/telegram_service.dart';

enum ConfigStatus {
  synced,
  found_unrestored,
  missing,
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
    final activeChannel = await settingsRepo.getSetting('active_channel_id');
    final publicShareChannelId = await settingsRepo.getSetting('public_share_channel_id');
    final publicShareChannelUsername = await settingsRepo.getSetting('public_share_channel_username');
    final publicShareChannelInvite = await settingsRepo.getSetting('public_share_channel_invite');
    final tempJoined = await settingsRepo.getSetting('temp_joined_sharing_channels');

    final configMap = {
      'storage_channels_list': rawChannels ?? '[]',
      'active_channel_id': activeChannel ?? '',
      'public_share_channel_id': publicShareChannelId ?? '',
      'public_share_channel_username': publicShareChannelUsername ?? '',
      'public_share_channel_invite': publicShareChannelInvite ?? '',
      'temp_joined_sharing_channels': tempJoined ?? '[]',
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
    } catch (e, s) {
      AppLogger.error('ConfigSyncService: Error syncing config', e, s);
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
          return ConfigStatus.synced; // assuming we trust local if both exist for now, or we can merge
        }
      }
      return ConfigStatus.synced;
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
        "limit": 10,
        "only_local": false,
      });

      if (history['messages'] != null) {
        for (final msg in history['messages']) {
          if (msg['content']?['@type'] == 'messageText') {
            final text = msg['content']['text']['text'] as String?;
            if (text != null && text.contains('WARNING: DO NOT DELETE')) {
              // Extract base64 encrypted string
              final parts = text.split('\n\n');
              if (parts.length >= 3) {
                final encryptedBase64 = parts.last;
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
                if (description != null && description.contains('[AERODRIVE_CONFIG_v1]')) {
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

    // Attempt 2: Fallback to existing logic (local admin channels)
    final channels = await telegramService.getAdminChannels();
    for (final channel in channels) {
      if (channel['title'] == _configChannelName || channel['title'] == 'AeroDrive Config (Do Not Delete)') {
        return channel['id'];
      }
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
}

final configSyncServiceProvider = Provider<ConfigSyncService>(ConfigSyncService.new);
