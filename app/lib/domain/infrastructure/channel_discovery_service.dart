import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/logger.dart';
import '../../core/providers/repository_providers.dart';
import '../../features/telegram/telegram_service.dart';
import 'channel_description_codec.dart';

/// Result of the channel discovery operation.
class DiscoveryResult {
  const DiscoveryResult({
    required this.storageChannelIds,
    required this.configChannelId,
    required this.sharedChannelId,
    this.totalFound = 0,
    this.errorMessage,
  });

  final List<int> storageChannelIds;
  final int? configChannelId;
  final int? sharedChannelId;
  final int totalFound;
  final String? errorMessage;

  bool get isComplete =>
      storageChannelIds.length >= ChannelConstants.defaultStorageChannelCount &&
      configChannelId != null &&
      sharedChannelId != null;
}

/// Discovers existing AeroDrive channel infrastructure by scanning all
/// Telegram channels the user administrates, reading their descriptions,
/// and decrypting the AeroDrive infrastructure metadata embedded in them.
///
/// This enables full recovery on reinstall: the user logs into Telegram,
/// this service finds all channels from their descriptions, restores the
/// local configuration, and the app picks up where it left off.
class ChannelDiscoveryService {
  ChannelDiscoveryService(this._ref);

  final Ref _ref;

  /// Scans all accessible admin channels and identifies AeroDrive channels
  /// by attempting to decrypt their descriptions with [masterKey].
  Future<DiscoveryResult> discoverInfrastructure({
    required TelegramService telegramService,
    required SecretKey masterKey,
  }) async {
    final List<int> storageChannelIds = [];
    int? configChannelId;
    int? sharedChannelId;
    int totalFound = 0;

    try {
      AppLogger.info('Discovery: Fetching admin channels...');
      final adminChannels = await telegramService.getAdminChannels();
      AppLogger.info('Discovery: Found ${adminChannels.length} admin channels');

      for (final channel in adminChannels) {
        final chatId = channel['id'] as int?;
        if (chatId == null) continue;

        // Read channel description
        String? description;
        try {
          description = await telegramService.getChannelDescription(chatId);
        } catch (e) {
          AppLogger.warning('Discovery: Failed to get description for chat $chatId: $e');
          continue;
        }

        if (description == null || description.isEmpty) continue;

        // Try to decrypt the description
        final decoded = await ChannelDescriptionCodec.decode(
          description: description,
          masterKey: masterKey,
        );

        if (decoded == null) {
          // Not an AeroDrive infra channel — skip
          continue;
        }

        totalFound++;
        final purpose = decoded['p'] as String?;

        switch (purpose) {
          case ChannelConstants.descriptionPurposeStorage:
            storageChannelIds.add(chatId);
            AppLogger.info('Discovery: Found storage channel $chatId');
            break;
          case ChannelConstants.descriptionPurposeConfig:
            configChannelId = chatId;
            AppLogger.info('Discovery: Found config channel $chatId');
            break;
          case ChannelConstants.descriptionPurposeShared:
            sharedChannelId = chatId;
            AppLogger.info('Discovery: Found shared channel $chatId');
            break;
          default:
            AppLogger.warning(
              'Discovery: Unknown channel purpose "$purpose" for chat $chatId',
            );
        }
      }

      AppLogger.info(
        'Discovery complete: found $totalFound AeroDrive channels '
        '(${storageChannelIds.length} storage, '
        '${configChannelId != null ? 1 : 0} config, '
        '${sharedChannelId != null ? 1 : 0} shared)',
      );

      return DiscoveryResult(
        storageChannelIds: storageChannelIds,
        configChannelId: configChannelId,
        sharedChannelId: sharedChannelId,
        totalFound: totalFound,
      );
    } catch (e, s) {
      AppLogger.error('Discovery: Unexpected error', e, s);
      return DiscoveryResult(
        storageChannelIds: [],
        configChannelId: null,
        sharedChannelId: null,
        errorMessage: 'Unexpected error: $e',
      );
    }
  }

  /// Restores local settings from discovered channels. Call after
  /// [discoverInfrastructure] returns a result with channels found.
  Future<void> restoreFromDiscovery(DiscoveryResult result) async {
    if (result.totalFound == 0) return;

    final settingsRepo = _ref.read(settingsRepositoryProvider);

    // Build storage_channels_list JSON
    final storageChannels = result.storageChannelIds
        .asMap()
        .entries
        .map((entry) => {
              'id': entry.value,
              'title':
                  '${ChannelConstants.storageChannelBaseName} ${entry.key + 1}',
              'name':
                  '${ChannelConstants.storageChannelBaseName} ${entry.key + 1}',
              'purpose': ChannelConstants.descriptionPurposeStorage,
              'accountId': 'primary',
            })
        .toList();

    if (storageChannels.isNotEmpty) {
      await settingsRepo.setSetting(
        'storage_channels_list',
        jsonEncode(storageChannels),
      );
      await settingsRepo.setSetting(
        'active_channel_ids',
        jsonEncode(result.storageChannelIds),
      );
      await settingsRepo.setSetting(
        'active_channel_id',
        result.storageChannelIds.first.toString(),
      );
    }

    if (result.configChannelId != null) {
      await settingsRepo.setSetting(
        'config_channel_id',
        result.configChannelId.toString(),
      );
    }

    if (result.sharedChannelId != null) {
      await settingsRepo.setSetting(
        'public_share_channel_id',
        result.sharedChannelId.toString(),
      );
    }

    AppLogger.info(
      'Discovery: Restored ${result.storageChannelIds.length} storage, '
      '${result.configChannelId != null ? 1 : 0} config, '
      '${result.sharedChannelId != null ? 1 : 0} shared channels to settings',
    );
  }
}
