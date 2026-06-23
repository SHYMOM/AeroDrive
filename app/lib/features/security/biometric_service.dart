import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:aerodrive/core/logger.dart';

class BiometricService {
  final _localAuth = LocalAuthentication();
  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kekKey = 'aerodrive_master_kek';

  Future<bool> isBiometricAvailable() async {
    try {
      final canAuthenticateWithBiometrics = await _localAuth.canCheckBiometrics;
      final canAuthenticate = canAuthenticateWithBiometrics || await _localAuth.isDeviceSupported();
      return canAuthenticate;
    } catch (e) {
      AppLogger.error('Failed to check biometrics', e);
      return false;
    }
  }

  Future<bool> authenticate(String reason) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      AppLogger.error('Biometric auth failed', e);
      return false;
    }
  }

  Future<void> saveKek(List<int> kekBytes) async {
    final base64Kek = base64Encode(kekBytes);
    await _secureStorage.write(key: _kekKey, value: base64Kek);
  }

  Future<List<int>?> retrieveKek() async {
    final base64Kek = await _secureStorage.read(key: _kekKey);
    if (base64Kek != null) {
      return base64Decode(base64Kek);
    }
    return null;
  }

  Future<void> clearKek() async {
    await _secureStorage.delete(key: _kekKey);
  }
}

final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService();
});
