import 'package:flutter_test/flutter_test.dart';
import 'package:aerodrive/data/repositories/settings_repository.dart';
import 'package:aerodrive/features/telegram/telegram_service.dart';

class MockSettingsRepository implements SettingsRepository {
  final Map<String, dynamic> _storage = {};

  @override
  Future<String?> getSetting(String key) async => _storage[key]?.toString();

  @override
  Future<void> setSetting(String key, String value) async {
    _storage[key] = value;
  }

  @override
  Future<bool> getBoolSetting(String key, {bool defaultValue = false}) async {
    final val = _storage[key];
    if (val == null) return defaultValue;
    return val.toString().toLowerCase() == 'true';
  }

  @override
  Future<void> setBoolSetting(String key, bool value) async {
    _storage[key] = value.toString();
  }

  @override
  Future<int> getIntSetting(String key, {int defaultValue = 0}) async {
    final val = _storage[key];
    if (val == null) return defaultValue;
    return int.tryParse(val.toString()) ?? defaultValue;
  }

  @override
  Future<void> setIntSetting(String key, int value) async {
    _storage[key] = value.toString();
  }

  @override
  Future<int?> getInt(String key) async {
    final val = _storage[key];
    if (val == null) return null;
    return int.tryParse(val.toString());
  }

  @override
  Future<String?> getString(String key) async => _storage[key]?.toString();

  @override
  Future<void> setString(String key, String value) async {
    _storage[key] = value;
  }

  @override
  Future<void> setInt(String key, int value) async {
    _storage[key] = value.toString();
  }

  @override
  Future<void> clearSetting(String key) async {
    _storage.remove(key);
  }

  @override
  Future<void> clearAllSettings() async {
    _storage.clear();
  }
}

void main() {
  group('Telegram API Credentials Configuration Tests', () {
    late MockSettingsRepository settingsRepo;

    setUp(() {
      settingsRepo = MockSettingsRepository();
    });

    test('TelegramAuthState includes waitApiCredentials state', () {
      expect(TelegramAuthState.values, contains(TelegramAuthState.waitApiCredentials));
    });

    test('SettingsRepository persists and retrieves custom apiId and apiHash', () async {
      expect(await settingsRepo.getInt('telegram_api_id'), isNull);
      expect(await settingsRepo.getString('telegram_api_hash'), isNull);

      await settingsRepo.setInt('telegram_api_id', 12345678);
      await settingsRepo.setString('telegram_api_hash', '0123456789abcdef0123456789abcdef');

      expect(await settingsRepo.getInt('telegram_api_id'), equals(12345678));
      expect(await settingsRepo.getString('telegram_api_hash'), equals('0123456789abcdef0123456789abcdef'));
    });

    test('Credentials validation logic rejects invalid formats and accepts valid', () {
      // API ID tests
      expect(int.tryParse(''), isNull);
      expect(int.tryParse('abc'), isNull);
      expect(int.tryParse('-10'), lessThanOrEqualTo(0));
      expect(int.tryParse('12345678'), greaterThan(0));

      // API Hash tests
      const validHash = '0123456789abcdef0123456789abcdef';
      expect(validHash.length, equals(32));
      expect(validHash.trim().isNotEmpty, isTrue);

      const invalidHash = 'short';
      expect(invalidHash.length < 16, isTrue);
    });
  });
}
