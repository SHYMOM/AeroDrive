import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../telegram/telegram_service.dart';

enum AuthState { initial, loading, unauthenticated, authenticated }

/// Maps the lower-level Telegram authentication state to a top-level AuthState
/// used by the router to protect screens.
final authProvider = Provider<AuthState>((ref) {
  final tdState = ref.watch(telegramServiceProvider);
  
  if (tdState == TelegramAuthState.ready) {
    return AuthState.authenticated;
  } else if (tdState == TelegramAuthState.initial) {
    return AuthState.loading;
  } else {
    return AuthState.unauthenticated;
  }
});
