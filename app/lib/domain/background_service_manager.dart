import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/logger.dart';

/// Service for managing the Android foreground backup service.
/// This keeps the auto-backup watcher alive even when the user
/// dismisses the app from the recents screen.
class BackgroundServiceManager {
  static const _channel = MethodChannel('com.aerodrive.aerodrive/backup_service');

  /// Start the Android foreground backup service.
  /// This should be called when auto-backup is enabled and the app
  /// is about to go to background.
  static Future<void> startService() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('startBackupService');
      AppLogger.info('BackgroundServiceManager: Foreground backup service started');
    } catch (e) {
      AppLogger.error('BackgroundServiceManager: Failed to start backup service', e);
    }
  }

  /// Stop the Android foreground backup service.
  /// This should be called when auto-backup is disabled.
  static Future<void> stopService() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('stopBackupService');
      AppLogger.info('BackgroundServiceManager: Foreground backup service stopped');
    } catch (e) {
      AppLogger.error('BackgroundServiceManager: Failed to stop backup service', e);
    }
  }
}
