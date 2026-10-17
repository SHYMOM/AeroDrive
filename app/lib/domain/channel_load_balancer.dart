import 'dart:convert';
import 'dart:math';

import '../core/logger.dart';
import '../data/repositories/settings_repository.dart';

/// Centralized channel load balancer for distributing file, chunk, and folder
/// uploads across multiple Telegram storage channels.
class ChannelLoadBalancer {
  /// Fetches all active storage channels.
  /// Checks `storage_channels_list`, then `active_channel_ids`, then `active_channel_id`.
  static Future<List<Map<String, dynamic>>> getStorageChannels(SettingsRepository settings) async {
    final savedChannelsJson = await settings.getSetting('storage_channels_list');
    if (savedChannelsJson != null && savedChannelsJson.isNotEmpty && savedChannelsJson != '[]') {
      try {
        final List<dynamic> decoded = jsonDecode(savedChannelsJson);
        final list = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
        if (list.isNotEmpty) return list;
      } catch (e) {
        AppLogger.error('ChannelLoadBalancer: failed to parse storage_channels_list', e);
      }
    }

    final activeIdsJson = await settings.getSetting('active_channel_ids');
    if (activeIdsJson != null && activeIdsJson.isNotEmpty && activeIdsJson != '[]') {
      try {
        final List<dynamic> decoded = jsonDecode(activeIdsJson);
        final list = decoded.map((id) => {
          'id': id is String ? int.parse(id) : id as int,
          'title': 'Storage Channel $id',
          'accountId': 'primary',
        }).toList();
        if (list.isNotEmpty) return list;
      } catch (e) {
        AppLogger.error('ChannelLoadBalancer: failed to parse active_channel_ids', e);
      }
    }

    final activeChannelStr = await settings.getSetting('active_channel_id');
    if (activeChannelStr != null && activeChannelStr.isNotEmpty) {
      final id = int.tryParse(activeChannelStr);
      if (id != null) {
        return [
          {
            'id': id,
            'title': 'Storage Channel $id',
            'accountId': 'primary',
          }
        ];
      }
    }

    return [];
  }

  /// Selects the starting/base channel index for a file or folder upload based on
  /// the user-configured load balancing strategy ('round_robin', 'random', 'size_based', 'fill_first').
  static Future<int> selectFileBaseIndex({
    required SettingsRepository settings,
    required int channelCount,
    int? fileSize,
  }) async {
    if (channelCount <= 1) return 0;

    final strategy = await settings.getSetting('load_balancing_strategy') ?? 'round_robin';

    if (strategy == 'random') {
      return Random().nextInt(channelCount);
    } else if (strategy == 'size_based') {
      final size = fileSize ?? 0;
      if (size < 10 * 1024 * 1024) {
        return 0; // Small files to first channel
      } else {
        // Larger files distributed across remaining channels
        return 1 + Random().nextInt(channelCount - 1);
      }
    } else {
      // Default: round_robin
      final indexStr = await settings.getSetting('load_balancing_round_robin_index') ?? '0';
      final curIndex = int.tryParse(indexStr) ?? 0;
      final selectedIndex = curIndex % channelCount;
      await settings.setSetting('load_balancing_round_robin_index', ((curIndex + 1) % channelCount).toString());
      return selectedIndex;
    }
  }

  /// Convenience method: selects a single storage channel map for folder manifests or single files.
  static Future<Map<String, dynamic>?> selectStorageChannel({
    required SettingsRepository settings,
    int? fileSize,
  }) async {
    final channels = await getStorageChannels(settings);
    if (channels.isEmpty) return null;
    if (channels.length == 1) return channels.first;

    final index = await selectFileBaseIndex(
      settings: settings,
      channelCount: channels.length,
      fileSize: fileSize,
    );
    return channels[index];
  }
}
