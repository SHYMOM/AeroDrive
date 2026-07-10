import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/telegram/telegram_service.dart';

enum AuthState { initial, loading, unauthenticated, authenticated }

/// Internal provider that watches the Telegram auth state
final _telegramAuthStateProvider = Provider<TelegramAuthState>((ref) {
  return ref.watch(telegramServiceProvider);
});

/// Notifier that manages the app-level auth state
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._ref) : super(AuthState.initial) {
    _init();
  }

  final Ref _ref;
  bool _hasBeenAuthenticated = false;

  void _init() {
    // Listen to Telegram auth state changes
    _ref.listen(_telegramAuthStateProvider, (prev, next) {
      if (next == TelegramAuthState.ready) {
        // Once authenticated, lock it in
        _hasBeenAuthenticated = true;
        state = AuthState.authenticated;
      } else if (next == TelegramAuthState.waitPhoneNumber ||
                 next == TelegramAuthState.waitCode ||
                 next == TelegramAuthState.waitPassword) {
        if (!_hasBeenAuthenticated) {
          state = AuthState.unauthenticated;
        }
      } else if (next == TelegramAuthState.error || next == TelegramAuthState.closed) {
        if (!_hasBeenAuthenticated) {
          state = AuthState.unauthenticated;
        }
      }
    });

    // Check initial state
    final initialState = _ref.read(_telegramAuthStateProvider);
    if (initialState == TelegramAuthState.ready) {
      _hasBeenAuthenticated = true;
      state = AuthState.authenticated;
    } else if (initialState == TelegramAuthState.initial) {
      state = AuthState.loading;
    } else if (!_hasBeenAuthenticated) {
      state = AuthState.unauthenticated;
    }
  }

  void forceUnauthenticated() {
    _hasBeenAuthenticated = false;
    state = AuthState.unauthenticated;
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref);
});