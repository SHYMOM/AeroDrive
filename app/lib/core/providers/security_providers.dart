import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';

/// Holds the 256-bit Argon2id derived Master Key (KEK).
/// This is volatile and is NEVER saved to disk.
final masterKeyProvider = StateProvider<List<int>?>((ref) => null);

/// Derived boolean to easily check if the app is unlocked.
final isAppUnlockedProvider = Provider<bool>((ref) {
  final key = ref.watch(masterKeyProvider);
  return key != null;
});

/// A provider to check if a Master Password has been configured at all.
final isMasterPasswordSetupProvider = FutureProvider<bool>((ref) async {
  final settings = ref.watch(settingsRepositoryProvider);
  final salt = await settings.getSetting('master_password_salt');
  return salt != null;
});
