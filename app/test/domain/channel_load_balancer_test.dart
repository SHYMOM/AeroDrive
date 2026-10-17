import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/data/repositories/settings_repository.dart';
import 'package:aerodrive/domain/channel_load_balancer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AeroDriveDatabase db;
  late SettingsRepository settings;

  setUp(() {
    db = AeroDriveDatabase(NativeDatabase.memory());
    settings = SettingsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('ChannelLoadBalancer Tests', () {
    test('getStorageChannels retrieves channels from storage_channels_list', () async {
      final channels = [
        {'id': 1001, 'title': 'Storage 1', 'accountId': 'acc1'},
        {'id': 1002, 'title': 'Storage 2', 'accountId': 'acc2'},
      ];
      await settings.setSetting('storage_channels_list', jsonEncode(channels));

      final result = await ChannelLoadBalancer.getStorageChannels(settings);
      expect(result.length, equals(2));
      expect(result[0]['id'], equals(1001));
      expect(result[1]['id'], equals(1002));
    });

    test('getStorageChannels falls back to active_channel_ids if storage_channels_list is missing', () async {
      await settings.setSetting('active_channel_ids', jsonEncode([2001, 2002, 2003]));

      final result = await ChannelLoadBalancer.getStorageChannels(settings);
      expect(result.length, equals(3));
      expect(result[0]['id'], equals(2001));
      expect(result[1]['id'], equals(2002));
      expect(result[2]['id'], equals(2003));
    });

    test('getStorageChannels falls back to active_channel_id if lists are missing', () async {
      await settings.setSetting('active_channel_id', '3001');

      final result = await ChannelLoadBalancer.getStorageChannels(settings);
      expect(result.length, equals(1));
      expect(result[0]['id'], equals(3001));
    });

    test('round_robin strategy evenly rotates across channels', () async {
      await settings.setSetting('load_balancing_strategy', 'round_robin');
      await settings.setSetting('load_balancing_round_robin_index', '0');

      final idx0 = await ChannelLoadBalancer.selectFileBaseIndex(settings: settings, channelCount: 3);
      final idx1 = await ChannelLoadBalancer.selectFileBaseIndex(settings: settings, channelCount: 3);
      final idx2 = await ChannelLoadBalancer.selectFileBaseIndex(settings: settings, channelCount: 3);
      final idx3 = await ChannelLoadBalancer.selectFileBaseIndex(settings: settings, channelCount: 3);

      expect(idx0, equals(0));
      expect(idx1, equals(1));
      expect(idx2, equals(2));
      expect(idx3, equals(0)); // Wraps around
    });

    test('random strategy returns valid channel indices', () async {
      await settings.setSetting('load_balancing_strategy', 'random');

      for (var i = 0; i < 20; i++) {
        final idx = await ChannelLoadBalancer.selectFileBaseIndex(settings: settings, channelCount: 3);
        expect(idx >= 0 && idx < 3, isTrue);
      }
    });

    test('selectStorageChannel returns channel from storage channels pool', () async {
      final channels = [
        {'id': 101, 'title': 'AeroDrive Storage 1', 'accountId': 'acc1'},
        {'id': 102, 'title': 'AeroDrive Storage 2', 'accountId': 'acc2'},
      ];
      await settings.setSetting('storage_channels_list', jsonEncode(channels));
      await settings.setSetting('load_balancing_strategy', 'round_robin');
      await settings.setSetting('load_balancing_round_robin_index', '0');

      final first = await ChannelLoadBalancer.selectStorageChannel(settings: settings);
      final second = await ChannelLoadBalancer.selectStorageChannel(settings: settings);

      expect(first?['id'], equals(101));
      expect(second?['id'], equals(102));
    });
  });
}
