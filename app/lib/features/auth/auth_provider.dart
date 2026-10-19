import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logger.dart';
import '../../core/providers/infrastructure_providers.dart';
import '../../core/providers/security_providers.dart';
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
        _hasBeenAuthenticated = true;
        state = AuthState.authenticated;

        // Discover/sync channels in background without blocking UI
        _ensureInfrastructure().catchError((e) {
          AppLogger.error('AuthNotifier: Infrastructure setup failed', e);
        });
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

      _ensureInfrastructure().catchError((e) {
        AppLogger.error('AuthNotifier: Initial infrastructure setup failed', e);
      });
    } else if (initialState == TelegramAuthState.initial) {
      state = AuthState.loading;
    } else if (!_hasBeenAuthenticated) {
      state = AuthState.unauthenticated;
    }
  }

  /// Ensures AeroDrive channel infrastructure exists.
  /// Tries discovery first, falls back to provisioning.
  Future<void> _ensureInfrastructure() async {
    try {
      final masterKeyBytes = _ref.read(masterKeyProvider);
      if (masterKeyBytes == null) {
        AppLogger.warning('Auth: master key not available yet, skipping infra check');
        return;
      }

      final masterKey = SecretKey(masterKeyBytes);
      await _ref.read(ensureInfrastructureProvider(masterKey).future);
    } catch (e, s) {
      AppLogger.error('Auth: Infrastructure provisioning/discovery failed', e, s);
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