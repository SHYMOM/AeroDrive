import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/telegram/telegram_service.dart';
import '../security/master_key_provider.dart';

/// Holds the 256-bit Master Key dynamically derived from Telegram Auth.
final masterKeyProvider = Provider<List<int>?>((ref) {
  final telegramService = ref.watch(telegramServiceProvider);
  // Watch the notifier to get the latest userId
  final userId = ref.read(telegramServiceProvider.notifier).userId;
  
  if (userId != null) {
    const salt = "AeroDrive_Secret_Salt";
    final bytes = utf8.encode("$userId$salt");
    final hash = sha256.convert(bytes);
    
    // Sync with singleton instance used by viewers
    MasterKeyProvider.instance.setKey(hash.bytes);
    
    return hash.bytes;
  }
  return null;
});

/// Derived boolean to easily check if the app is unlocked.
final isAppUnlockedProvider = Provider<bool>((ref) {
  final key = ref.watch(masterKeyProvider);
  return key != null;
});
