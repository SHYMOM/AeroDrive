import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants.dart';
import '../../core/logger.dart';
import '../../core/providers/repository_providers.dart';
import '../../data/repositories/settings_repository.dart';
import '../../features/telegram/telegram_service.dart';
import '../sync/config_sync_service.dart';
import 'channel_description_codec.dart';

typedef ProvisioningProgressCallback = void Function(String message, double progress);

/// Result of the infrastructure provisioning operation.
class InfrastructureResult {
  const InfrastructureResult({
    required this.success,
    required this.storageChannelIds,
    required this.configChannelId,
    required this.sharedChannelId,
    this.errorMessage,
  });

  final bool success;
  final List<int> storageChannelIds;
  final int? configChannelId;
  final int? sharedChannelId;
  final String? errorMessage;
}

/// Creates the initial AeroDrive channel infrastructure during first-time
/// registration:
///   - 2 Storage channels ("AeroDrive Storage 1", "AeroDrive Storage 2")
///   - 1 Config channel ("AeroDrive Config")
///   - 1 Shared channel ("AeroDrive Shared")
///
/// Each channel gets an encrypted description (via [ChannelDescriptionCodec])
/// so the infrastructure can be discovered on reinstall. All channels are
/// grouped into a Telegram folder named "AeroDrive", archived, and muted.
class InfrastructureProvisioningService {
  InfrastructureProvisioningService(this._ref);

  final Ref _ref;

  /// Checks whether infrastructure already exists (via settings), runs
  /// provisioning if not. Idempotent — safe to call multiple times.
  ///
  /// This method BLOCKS until provisioning is complete, ensuring channels
  /// are ready before the UI proceeds.
  Future<InfrastructureResult> ensureInfrastructure({
    required TelegramService telegramService,
    required SecretKey masterKey,
    required String masterKeySalt,
    required List<TelegramService> allAccounts,
    ProvisioningProgressCallback? onProgress,
  }) async {
    final settingsRepo = _ref.read(settingsRepositoryProvider);

    // Check if already provisioned
    final existingChannels = await settingsRepo.getSetting('storage_channels_list');
    final existingConfig = await settingsRepo.getSetting('config_channel_id');

    if ((existingChannels != null && existingChannels.isNotEmpty && existingChannels != '[]') ||
        existingConfig != null) {
      return const InfrastructureResult(
        success: true,
        storageChannelIds: [],
        configChannelId: null,
        sharedChannelId: null,
        errorMessage: 'Infrastructure already exists — skipping provisioning.',
      );
    }

    return await provisionInitialInfrastructure(
      telegramService: telegramService,
      masterKey: masterKey,
      masterKeySalt: masterKeySalt,
      allAccounts: allAccounts,
      onProgress: onProgress,
    );
  }

  /// Creates all AeroDrive channels from scratch.
  ///
  /// IMPORTANT: This is a BLOCKING operation that creates channels sequentially.
  /// Each channel is created, configured, and verified before moving to the next.
  Future<InfrastructureResult> provisionInitialInfrastructure({
    required TelegramService telegramService,
    required SecretKey masterKey,
    required String masterKeySalt,
    required List<TelegramService> allAccounts,
    ProvisioningProgressCallback? onProgress,
  }) async {
    final settingsRepo = _ref.read(settingsRepositoryProvider);
    final List<int> storageChannelIds = [];
    int? configChannelId;
    int? sharedChannelId;
    String? sharedInviteLink;

    try {
      // ── 1. Create ALL channels FIRST (without archiving) ──────────
      for (var i = 0; i < ChannelConstants.defaultStorageChannelCount; i++) {
        final title = '${ChannelConstants.storageChannelBaseName} ${i + 1}';
        final progressFrac = 0.1 + (i * 0.18);
        onProgress?.call('Creating $title...', progressFrac);
        AppLogger.info('Provisioning: Creating storage channel "$title"');

        final response = await telegramService.createNewChannel(
          title,
          'AeroDrive Storage Channel ${i + 1}',
        );

        if (response['@type'] == 'error') {
          AppLogger.error('Provisioning: Failed to create "$title": ${response['message']}');
          await _rollback(storageChannelIds, configChannelId, sharedChannelId, telegramService);
          return InfrastructureResult(
            success: false,
            storageChannelIds: [],
            configChannelId: null,
            sharedChannelId: null,
            errorMessage: 'Failed to create storage channel $i: ${response['message']}',
          );
        }

        final chatId = response['id'] as int;
        storageChannelIds.add(chatId);

        // Set channel photo
        onProgress?.call('Setting icon for $title...', progressFrac + 0.05);
        await _setChannelPhoto(telegramService, chatId);

        // Set encrypted description
        await _setChannelDescription(
          telegramService,
          chatId,
          purpose: ChannelConstants.descriptionPurposeStorage,
          masterKey: masterKey,
          keySalt: masterKeySalt,
          channelIndex: i,
          totalStorageChannels: ChannelConstants.defaultStorageChannelCount,
        );

        // Wait for TDLib to fully process
        await _waitForChannelReady(telegramService, chatId);
      }

      // ── 2. Create Config Channel ───────────────────────────────────
      onProgress?.call('Creating ${ChannelConstants.configChannelName}...', 0.5);
      AppLogger.info('Provisioning: Creating config channel "${ChannelConstants.configChannelName}"');
      {
        final response = await telegramService.createNewChannel(
          ChannelConstants.configChannelName,
          '${ChannelConstants.configChannelMarker} AeroDrive system configuration channel. Do not delete.',
        );

        if (response['@type'] == 'error') {
          AppLogger.error('Provisioning: Failed to create config channel: ${response['message']}');
          await _rollback(storageChannelIds, configChannelId, sharedChannelId, telegramService);
          return InfrastructureResult(
            success: false,
            storageChannelIds: [],
            configChannelId: null,
            sharedChannelId: null,
            errorMessage: 'Failed to create config channel: ${response['message']}',
          );
        }

        configChannelId = response['id'] as int;
        await _setChannelPhoto(telegramService, configChannelId);
        await _setChannelDescription(
          telegramService,
          configChannelId,
          purpose: ChannelConstants.descriptionPurposeConfig,
          masterKey: masterKey,
          keySalt: masterKeySalt,
          channelIndex: 0,
          totalStorageChannels: ChannelConstants.defaultStorageChannelCount,
        );
        await _waitForChannelReady(telegramService, configChannelId);
      }

      // ── 3. Create Shared Channel ──────────────────────────────────
      onProgress?.call('Creating ${ChannelConstants.sharedChannelName}...', 0.65);
      AppLogger.info('Provisioning: Creating shared channel "${ChannelConstants.sharedChannelName}"');
      {
        final response = await telegramService.createNewChannel(
          ChannelConstants.sharedChannelName,
          'AeroDrive public sharing channel. Shared files are stored here.',
        );

        if (response['@type'] == 'error') {
          AppLogger.error('Provisioning: Failed to create shared channel: ${response['message']}');
          await _rollback(storageChannelIds, configChannelId, sharedChannelId, telegramService);
          return InfrastructureResult(
            success: false,
            storageChannelIds: [],
            configChannelId: null,
            sharedChannelId: null,
            errorMessage: 'Failed to create shared channel: ${response['message']}',
          );
        }

        sharedChannelId = response['id'] as int;
        await _setChannelPhoto(telegramService, sharedChannelId);
        await _setChannelDescription(
          telegramService,
          sharedChannelId,
          purpose: ChannelConstants.descriptionPurposeShared,
          masterKey: masterKey,
          keySalt: masterKeySalt,
          channelIndex: 0,
          totalStorageChannels: ChannelConstants.defaultStorageChannelCount,
        );
        await _waitForChannelReady(telegramService, sharedChannelId);

        // Generate public share invite link
        onProgress?.call('Generating shared link invitation...', 0.72);
        try {
          final inviteRes = await telegramService.sendRequest({
            "@type": "createChatInviteLink",
            "chat_id": sharedChannelId,
            "name": "AeroDrive Public Share",
            "creates_join_request": false,
          });
          sharedInviteLink = inviteRes['invite_link'] as String?;
          if (sharedInviteLink != null && sharedInviteLink.isNotEmpty) {
            await settingsRepo.setSetting('public_share_channel_invite', sharedInviteLink);
            AppLogger.info('Provisioning: Generated public share invite link: $sharedInviteLink');
          }
        } catch (e) {
          AppLogger.warning('Provisioning: Failed to create invite link for shared channel: $e');
        }
      }

      // ── 4. Create Telegram folder FIRST (before archiving) ────────
      final allChannelIds = [
        ...storageChannelIds,
        if (configChannelId != null) configChannelId,
        if (sharedChannelId != null) sharedChannelId,
      ];

      onProgress?.call('Organizing channels into AeroDrive folder...', 0.80);
      AppLogger.info('Provisioning: Creating Telegram folder "AeroDrive"');
      await _createTelegramFolder(telegramService, allChannelIds);

      // ── 5. Promote all accounts as admins on all channels ────────
      onProgress?.call('Configuring multi-account bandwidth pooling...', 0.85);
      final primaryAccount = telegramService;
      await _promoteAccountsToChannels(
        primaryAccount,
        allAccounts,
        allChannelIds,
      );

      // ── 6. Archive and mute all channels LAST ────────────────────
      onProgress?.call('Securing and muting channels...', 0.90);
      for (final chatId in allChannelIds) {
        await _archiveAndMuteChannel(telegramService, chatId);
      }

      // ── 7. Save to settings ─────────────────────────────────────
      onProgress?.call('Saving configuration...', 0.95);
      await _saveToSettings(
        settingsRepo,
        storageChannelIds,
        configChannelId,
        sharedChannelId,
        sharedInviteLink: sharedInviteLink,
      );

      // ── 8. Sync initial config message to Config Channel ────────
      try {
        await _ref.read(configSyncServiceProvider).syncConfigToChannel();
      } catch (e) {
        AppLogger.warning('Provisioning: Failed to sync initial config to channel: $e');
      }

      onProgress?.call('Setup complete!', 1.0);
      AppLogger.info(
        'Provisioning complete. '
        'Storage: $storageChannelIds, '
        'Config: $configChannelId, '
        'Shared: $sharedChannelId',
      );

      return InfrastructureResult(
        success: true,
        storageChannelIds: storageChannelIds,
        configChannelId: configChannelId,
        sharedChannelId: sharedChannelId,
      );
    } catch (e, s) {
      AppLogger.error('Provisioning: Unexpected error during infrastructure creation', e, s);
      await _rollback(storageChannelIds, configChannelId, sharedChannelId, telegramService);
      return InfrastructureResult(
        success: false,
        storageChannelIds: [],
        configChannelId: null,
        sharedChannelId: null,
        errorMessage: 'Unexpected error: $e',
      );
    }
  }

  /// Configures four existing Telegram channels chosen by the user into the
  /// AeroDrive infrastructure:
  /// - 2 storage channels (renamed to "AeroDrive Storage 1" and "AeroDrive Storage 2")
  /// - 1 config channel (renamed to "AeroDrive Config")
  /// - 1 shared channel (renamed to "AeroDrive Shared")
  /// Sets descriptions, application icons, invite links, folder, and settings.
  Future<InfrastructureResult> configureExistingChannelsAsInfrastructure({
    required TelegramService telegramService,
    required int storageChannel1Id,
    required int storageChannel2Id,
    required int configChannelId,
    required int sharedChannelId,
    required SecretKey masterKey,
    required String masterKeySalt,
    required List<TelegramService> allAccounts,
    ProvisioningProgressCallback? onProgress,
  }) async {
    final settingsRepo = _ref.read(settingsRepositoryProvider);
    final storageChannelIds = [storageChannel1Id, storageChannel2Id];

    try {
      // 1. Rename and configure Storage Channel 1
      onProgress?.call('Configuring AeroDrive Storage 1...', 0.15);
      final title1 = '${ChannelConstants.storageChannelBaseName} 1';
      try {
        await telegramService.setChatTitle(storageChannel1Id, title1);
      } catch (e) {
        AppLogger.warning('Failed to rename storage channel 1: $e');
      }
      await _setChannelPhoto(telegramService, storageChannel1Id);
      await _setChannelDescription(
        telegramService,
        storageChannel1Id,
        purpose: ChannelConstants.descriptionPurposeStorage,
        masterKey: masterKey,
        keySalt: masterKeySalt,
        channelIndex: 0,
        totalStorageChannels: storageChannelIds.length,
      );

      // 2. Rename and configure Storage Channel 2
      onProgress?.call('Configuring AeroDrive Storage 2...', 0.35);
      final title2 = '${ChannelConstants.storageChannelBaseName} 2';
      try {
        await telegramService.setChatTitle(storageChannel2Id, title2);
      } catch (e) {
        AppLogger.warning('Failed to rename storage channel 2: $e');
      }
      await _setChannelPhoto(telegramService, storageChannel2Id);
      await _setChannelDescription(
        telegramService,
        storageChannel2Id,
        purpose: ChannelConstants.descriptionPurposeStorage,
        masterKey: masterKey,
        keySalt: masterKeySalt,
        channelIndex: 1,
        totalStorageChannels: storageChannelIds.length,
      );

      // 3. Rename and configure Config Channel
      onProgress?.call('Configuring AeroDrive Config...', 0.55);
      try {
        await telegramService.setChatTitle(configChannelId, ChannelConstants.configChannelName);
      } catch (e) {
        AppLogger.warning('Failed to rename config channel: $e');
      }
      await _setChannelPhoto(telegramService, configChannelId);
      await _setChannelDescription(
        telegramService,
        configChannelId,
        purpose: ChannelConstants.descriptionPurposeConfig,
        masterKey: masterKey,
        keySalt: masterKeySalt,
        channelIndex: 0,
        totalStorageChannels: storageChannelIds.length,
      );

      // 4. Rename and configure Shared Channel
      onProgress?.call('Configuring AeroDrive Shared...', 0.70);
      try {
        await telegramService.setChatTitle(sharedChannelId, ChannelConstants.sharedChannelName);
      } catch (e) {
        AppLogger.warning('Failed to rename shared channel: $e');
      }
      await _setChannelPhoto(telegramService, sharedChannelId);
      await _setChannelDescription(
        telegramService,
        sharedChannelId,
        purpose: ChannelConstants.descriptionPurposeShared,
        masterKey: masterKey,
        keySalt: masterKeySalt,
        channelIndex: 0,
        totalStorageChannels: storageChannelIds.length,
      );

      // Generate public share invite link
      String? sharedInviteLink;
      try {
        final inviteRes = await telegramService.sendRequest({
          "@type": "createChatInviteLink",
          "chat_id": sharedChannelId,
          "name": "AeroDrive Public Share",
          "creates_join_request": false,
        });
        sharedInviteLink = inviteRes['invite_link'] as String?;
        if (sharedInviteLink != null && sharedInviteLink.isNotEmpty) {
          await settingsRepo.setSetting('public_share_channel_invite', sharedInviteLink);
        }
      } catch (e) {
        AppLogger.warning('Failed to create invite link for shared channel: $e');
      }

      final allChannelIds = [
        ...storageChannelIds,
        configChannelId,
        sharedChannelId,
      ];

      // 5. Group into Telegram Folder
      onProgress?.call('Grouping channels into AeroDrive folder...', 0.80);
      await _createTelegramFolder(telegramService, allChannelIds);

      // 6. Multi-account promotion
      onProgress?.call('Configuring multi-account pooling...', 0.85);
      await _promoteAccountsToChannels(telegramService, allAccounts, allChannelIds);

      // 7. Archive and mute
      onProgress?.call('Archiving and muting channels...', 0.90);
      for (final chatId in allChannelIds) {
        await _archiveAndMuteChannel(telegramService, chatId);
      }

      // 8. Save settings
      onProgress?.call('Saving configuration...', 0.95);
      await _saveToSettings(
        settingsRepo,
        storageChannelIds,
        configChannelId,
        sharedChannelId,
        sharedInviteLink: sharedInviteLink,
      );

      // 9. Sync initial config
      try {
        await _ref.read(configSyncServiceProvider).syncConfigToChannel();
      } catch (e) {
        AppLogger.warning('Failed to sync config to channel: $e');
      }

      onProgress?.call('Setup complete!', 1.0);

      return InfrastructureResult(
        success: true,
        storageChannelIds: storageChannelIds,
        configChannelId: configChannelId,
        sharedChannelId: sharedChannelId,
      );
    } catch (e, s) {
      AppLogger.error('Failed to configure existing channels: $e', e, s);
      return InfrastructureResult(
        success: false,
        storageChannelIds: [],
        configChannelId: null,
        sharedChannelId: null,
        errorMessage: 'Error configuring channels: $e',
      );
    }
  }

  /// Waits for a channel to be fully processed by TDLib.
  Future<void> _waitForChannelReady(TelegramService client, int chatId) async {
    for (var i = 0; i < 10; i++) {
      try {
        final chat = await client.sendRequest({'@type': 'getChat', 'chat_id': chatId});
        if (chat['title'] != null && chat['title'] != 'Unknown chat') {
          return; // Channel is ready with proper title
        }
      } catch (_) {
        // Ignore errors during polling
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    AppLogger.warning('Provisioning: Channel $chatId may not be fully ready after waiting');
  }

  /// Writes an encrypted infrastructure description to the channel.
  Future<void> _setChannelDescription(
    TelegramService telegramService,
    int chatId, {
    required String purpose,
    required SecretKey masterKey,
    required String keySalt,
    required int channelIndex,
    required int totalStorageChannels,
  }) async {
    final description = await ChannelDescriptionCodec.encode(
      purpose: purpose,
      appVersion: AppConstants.appVersion,
      keySalt: keySalt,
      channelIndex: channelIndex,
      totalStorageChannels: totalStorageChannels,
      masterKey: masterKey,
    );

    await telegramService.setChatDescription(chatId, description);
    AppLogger.info('Set description for channel $chatId (purpose: $purpose)');
  }

  /// Sets the AeroDrive logo as the channel photo.
  Future<void> _setChannelPhoto(
    TelegramService telegramService,
    int chatId,
  ) async {
    try {
      final byteData = await rootBundle.load('assets/icon.png');
      final buffer = byteData.buffer;
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/aerodrive_channel_${chatId}_icon.png',
      );
      await tempFile.writeAsBytes(
        buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
      );

      await telegramService.sendRequest({
        '@type': 'setChatPhoto',
        'chat_id': chatId,
        'photo': {
          '@type': 'inputChatPhotoStatic',
          'photo': {
            '@type': 'inputFileLocal',
            'path': tempFile.path,
          },
        },
      });
      AppLogger.info('Set channel photo for chat $chatId');
    } catch (e, s) {
      AppLogger.warning('Failed to set channel photo for $chatId (non-fatal): $e');
    }
  }

  /// Creates a Telegram Chat Filter Folder named "AeroDrive" and adds all
  /// channels to it. This must be done BEFORE archiving.
  Future<void> _createTelegramFolder(
    TelegramService telegramService,
    List<int> channelIds,
  ) async {
    try {
      await telegramService.updateTelegramFolder(channelIds);
      AppLogger.info('Created Telegram folder "AeroDrive" with ${channelIds.length} channels');
    } catch (e, s) {
      AppLogger.warning('Failed to create Telegram folder: $e');
    }
  }

  /// Promotes all secondary accounts as administrators on all channels.
  /// Promotes all secondary accounts as administrators on all channels.
  Future<void> _promoteAccountsToChannels(
    TelegramService primaryAccount,
    List<TelegramService> allAccounts,
    List<int> channelIds,
  ) async {
    for (final chatId in channelIds) {
      for (final account in allAccounts) {
        if (account.accountId == primaryAccount.accountId) continue;
        if (account.authState != TelegramAuthState.ready) continue;

        try {
          final me = await account.getMe();
          final targetUserId = me['id'] as int?;
          if (targetUserId != null) {
            await primaryAccount.addAdminToChat(chatId, targetUserId);
            AppLogger.info('Promoted secondary account ${account.accountId} (user $targetUserId) on channel $chatId');
          }
        } catch (e) {
          AppLogger.warning('Failed to promote ${account.accountId} on $chatId (non-fatal): $e');
        }
      }
    }
  }

  /// Ensures all secondary accounts are administrators on all storage, config,
  /// and shared channels, and verifies that all channels belong to the 'AeroDrive' folder.
  Future<void> ensureAccountPromotionsAndFolder({
    required List<TelegramService> accounts,
  }) async {
    if (accounts.isEmpty) return;

    final primaryAccount = accounts.firstWhere(
      (a) => a.authState == TelegramAuthState.ready,
      orElse: () => accounts.first,
    );
    if (primaryAccount.authState != TelegramAuthState.ready) return;

    final settingsRepo = _ref.read(settingsRepositoryProvider);
    final savedChannelsJson = await settingsRepo.getSetting('storage_channels_list');
    final configChannelStr = await settingsRepo.getSetting('config_channel_id');
    final sharedChannelStr = await settingsRepo.getSetting('public_share_channel_id');

    final Set<int> channelIds = {};
    if (savedChannelsJson != null && savedChannelsJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(savedChannelsJson);
        for (final item in decoded) {
          final id = item['id'];
          final cId = id is String ? int.tryParse(id) : id as int?;
          if (cId != null) channelIds.add(cId);
        }
      } catch (_) {}
    }

    if (configChannelStr != null && configChannelStr.isNotEmpty) {
      final cId = int.tryParse(configChannelStr);
      if (cId != null) channelIds.add(cId);
    }
    if (sharedChannelStr != null && sharedChannelStr.isNotEmpty) {
      final sId = int.tryParse(sharedChannelStr);
      if (sId != null) channelIds.add(sId);
    }

    if (channelIds.isEmpty) return;

    await _promoteAccountsToChannels(primaryAccount, accounts, channelIds.toList());

    try {
      await primaryAccount.updateTelegramFolder(channelIds.toList());
    } catch (e) {
      AppLogger.warning('ensureAccountPromotionsAndFolder: Failed to update Telegram folder: $e');
    }
  }

  /// Archives and mutes a channel so it stays out of the user's main chat list.
  Future<void> _archiveAndMuteChannel(
    TelegramService telegramService,
    int chatId,
  ) async {
    try {
      // Archive
      await telegramService.sendRequest({
        '@type': 'addChatToList',
        'chat_id': chatId,
        'chat_list': {'@type': 'chatListArchive'},
      });

      // Mute forever
      await telegramService.sendRequest({
        '@type': 'setChatNotificationSettings',
        'chat_id': chatId,
        'notification_settings': {
          '@type': 'chatNotificationSettings',
          'use_default_mute_for': false,
          'mute_for': 2147483647,
          'use_default_sound': false,
          'sound_id': 0,
          'use_default_show_preview': false,
          'show_preview': false,
          'use_default_disable_pinned_message_notifications': false,
          'disable_pinned_message_notifications': true,
          'use_default_disable_mention_notifications': false,
          'disable_mention_notifications': true,
        },
      });
    } catch (e) {
      AppLogger.warning('Failed to archive/mute channel $chatId (non-fatal): $e');
    }
  }

  /// Saves provisioned channel IDs to local settings.
  Future<void> _saveToSettings(
    SettingsRepository settingsRepo,
    List<int> storageChannelIds,
    int? configChannelId,
    int? sharedChannelId, {
    String? sharedInviteLink,
  }) async {
    // Build storage_channels_list JSON
    final storageChannels = storageChannelIds
        .asMap()
        .entries
        .map((entry) => {
              'id': entry.value,
              'title': '${ChannelConstants.storageChannelBaseName} ${entry.key + 1}',
              'name': '${ChannelConstants.storageChannelBaseName} ${entry.key + 1}',
              'purpose': ChannelConstants.descriptionPurposeStorage,
              'accountId': 'primary', // Default to primary account
            })
        .toList();

    await settingsRepo.setSetting('storage_channels_list', jsonEncode(storageChannels));

    if (storageChannelIds.isNotEmpty) {
      // All storage channels are active - store them all
      await settingsRepo.setSetting('active_channel_ids', jsonEncode(storageChannelIds));
      // Keep first channel as default active for legacy compatibility
      await settingsRepo.setSetting('active_channel_id', storageChannelIds.first.toString());
    }

    if (configChannelId != null) {
      await settingsRepo.setSetting('config_channel_id', configChannelId.toString());
    }

    if (sharedChannelId != null) {
      await settingsRepo.setSetting('public_share_channel_id', sharedChannelId.toString());
    }

    if (sharedInviteLink != null && sharedInviteLink.isNotEmpty) {
      await settingsRepo.setSetting('public_share_channel_invite', sharedInviteLink);
    }
  }

  /// Rollback: delete all channels created so far if provisioning fails midway.
  Future<void> _rollback(
    List<int> storageChannelIds,
    int? configChannelId,
    int? sharedChannelId,
    TelegramService telegramService,
  ) async {
    final allIds = [
      ...storageChannelIds,
      if (configChannelId != null) configChannelId,
      if (sharedChannelId != null) sharedChannelId,
    ];

    for (final chatId in allIds) {
      try {
        await telegramService.sendRequest({
          '@type': 'deleteChatHistory',
          'chat_id': chatId,
          'remove_from_chat_list': true,
          'revoke': true,
        });
      } catch (e) {
        AppLogger.warning('Rollback: Failed to delete chat $chatId: $e');
      }
    }

    AppLogger.info('Rollback complete — deleted ${allIds.length} channels');
  }
}