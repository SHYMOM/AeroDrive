import 'package:drift/drift.dart';
import '../db/database.dart';

class SettingsRepository {

  SettingsRepository(this._db);
  final AeroDriveDatabase _db;

  /// Get a setting value by key. Returns null if not found.
  Future<String?> getSetting(String key) async {
    final setting = await (_db.select(_db.settings)..where((s) => s.key.equals(key))).getSingleOrNull();
    return setting?.value;
  }

  /// Get a boolean setting. Returns defaultValue if not found.
  Future<bool> getBoolSetting(String key, {bool defaultValue = false}) async {
    final value = await getSetting(key);
    if (value == null) return defaultValue;
    return value.toLowerCase() == 'true';
  }

  /// Get an integer setting. Returns defaultValue if not found.
  Future<int> getIntSetting(String key, {int defaultValue = 0}) async {
    final value = await getSetting(key);
    if (value == null) return defaultValue;
    return int.tryParse(value) ?? defaultValue;
  }

  /// Get nullable int or null if not set.
  Future<int?> getInt(String key) async {
    final value = await getSetting(key);
    if (value == null) return null;
    return int.tryParse(value);
  }

  /// Get nullable string or null if not set.
  Future<String?> getString(String key) => getSetting(key);

  /// Set a string setting.
  Future<void> setString(String key, String value) => setSetting(key, value);

  /// Set an integer setting.
  Future<void> setInt(String key, int value) => setIntSetting(key, value);

  /// Set a string setting.
  Future<void> setSetting(String key, String value) async {
    await _db.into(_db.settings).insertOnConflictUpdate(
      SettingsCompanion.insert(
        key: key,
        value: Value(value),
      ),
    );
  }

  /// Set a boolean setting.
  Future<void> setBoolSetting(String key, bool value) async {
    await setSetting(key, value.toString());
  }

  /// Set an integer setting.
  Future<void> setIntSetting(String key, int value) async {
    await setSetting(key, value.toString());
  }

  /// Clear a setting.
  Future<void> clearSetting(String key) async {
    await (_db.delete(_db.settings)..where((s) => s.key.equals(key))).go();
  }

  /// Clear all settings.
  Future<void> clearAllSettings() async {
    await _db.delete(_db.settings).go();
  }
}
