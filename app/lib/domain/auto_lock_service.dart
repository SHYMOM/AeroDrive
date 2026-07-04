import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logger.dart';
import '../core/providers/repository_providers.dart';
import '../core/providers/security_providers.dart';
import '../core/security/master_key_provider.dart';

class AutoLockService extends WidgetsBindingObserver {

  AutoLockService(this._ref);
  Timer? _lockTimer;
  final WidgetRef _ref;
  DateTime? _backgroundedAt;

  void start() {
    WidgetsBinding.instance.addObserver(this);
  }

  void stop() {
    WidgetsBinding.instance.removeObserver(this);
    _lockTimer?.cancel();
  }

  void _resetTimer() {
    _lockTimer?.cancel();
    final settingsRepo = _ref.read(settingsRepositoryProvider);
    settingsRepo.getSetting('auto_lock_timeout').then((timeoutStr) {
      if (timeoutStr == null || timeoutStr == 'never') return;

      Duration? duration;
      switch (timeoutStr) {
        case '1m':
          duration = const Duration(minutes: 1);
        case '5m':
          duration = const Duration(minutes: 5);
        case '15m':
          duration = const Duration(minutes: 15);
        case '1h':
          duration = const Duration(hours: 1);
      }

      if (duration != null) {
        _lockTimer?.cancel();
        _lockTimer = Timer(duration, () {
          if (MasterKeyProvider.instance.isUnlocked) {
            AppLogger.info('Auto-lock: locking vault after $timeoutStr of inactivity');
            MasterKeyProvider.instance.clearKey();
            _ref.read(masterKeyProvider.notifier).state = null;
          }
        });
      }
    }).catchError((e) {
      AppLogger.error('Auto-lock: failed to read timeout setting', e);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
      _checkMaxEncryptionMode();
    } else if (state == AppLifecycleState.resumed) {

      // If the app was backgrounded long enough that the timeout expired,
      // lock immediately instead of starting a fresh timer.
      if (_backgroundedAt != null) {
        final elapsed = DateTime.now().difference(_backgroundedAt!);
        final settingsRepo = _ref.read(settingsRepositoryProvider);
        settingsRepo.getSetting('auto_lock_timeout').then((timeoutStr) {
          if (timeoutStr == null || timeoutStr == 'never') return;
          Duration? timeout;
          switch (timeoutStr) {
            case '1m': timeout = const Duration(minutes: 1);
            case '5m': timeout = const Duration(minutes: 5);
            case '15m': timeout = const Duration(minutes: 15);
            case '1h': timeout = const Duration(hours: 1);
          }
          if (timeout != null && elapsed >= timeout) {
            if (MasterKeyProvider.instance.isUnlocked) {
              AppLogger.info('Auto-lock: vault locked after $elapsed in background');
              MasterKeyProvider.instance.clearKey();
              _ref.read(masterKeyProvider.notifier).state = null;
            }
          } else {
            _resetTimer();
          }
        }).catchError((e) {
          AppLogger.error('Auto-lock: failed to read timeout setting', e);
        });
      } else {
        _resetTimer();
      }
      _backgroundedAt = null;
    }
  }

  Future<void> _checkMaxEncryptionMode() async {
    final settings = _ref.read(settingsRepositoryProvider);
    final mode = await settings.getSetting('encryption_mode');
    if (mode == 'max' && MasterKeyProvider.instance.isUnlocked) {
      AppLogger.info('Auto-lock: encryption_mode=max, clearing key on background');
      MasterKeyProvider.instance.clearKey();
      _ref.read(masterKeyProvider.notifier).state = null;
    }
  }
}
