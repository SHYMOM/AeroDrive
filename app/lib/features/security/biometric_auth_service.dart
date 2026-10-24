import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/logger.dart';
import '../../core/providers/repository_providers.dart';

final biometricAuthServiceProvider = Provider<BiometricAuthService>((ref) {
  return BiometricAuthService(ref);
});

final appLockEnabledProvider = StateProvider<bool>((ref) => false);
final isVaultUnlockedProvider = StateProvider<bool>((ref) => false);

class BiometricAuthService {
  BiometricAuthService(this._ref);

  final Ref _ref;
  final LocalAuthentication _localAuth = LocalAuthentication();

  Future<bool> isBiometricsSupported() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck || isSupported;
    } on PlatformException catch (e) {
      AppLogger.error('Failed to check biometrics support', e);
      return false;
    }
  }

  Future<bool> authenticate({required String localizedReason}) async {
    try {
      final supported = await isBiometricsSupported();
      if (!supported) {
        AppLogger.info('Biometrics not supported on device; falling back to allowed.');
        return true;
      }

      return await _localAuth.authenticate(
        localizedReason: localizedReason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } on PlatformException catch (e) {
      AppLogger.error('Biometric authentication failed or cancelled', e);
      return false;
    }
  }

  Future<bool> isAppLockEnabled() async {
    final settings = _ref.read(settingsRepositoryProvider);
    final val = await settings.getSetting('app_lock_biometrics_enabled');
    return val == 'true';
  }

  Future<void> setAppLockEnabled(bool enabled) async {
    final settings = _ref.read(settingsRepositoryProvider);
    await settings.setSetting('app_lock_biometrics_enabled', enabled ? 'true' : 'false');
    _ref.read(appLockEnabledProvider.notifier).state = enabled;
  }
}
