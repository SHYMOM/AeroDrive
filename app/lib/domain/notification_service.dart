import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/logger.dart';

class NotificationService {

  factory NotificationService() => instance;

  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  
  final _actionStreamController = StreamController<String>.broadcast();
  Stream<String> get actionStream => _actionStreamController.stream;

  bool _initialized = false;

  bool get _isSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> initialize() async {
    if (!_isSupported) return;
    if (_initialized) return;

    const initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettings = InitializationSettings(android: initializationSettingsAndroid);

    await _plugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        if (details.actionId != null) {
          instance._actionStreamController.add(details.actionId!);
        } else {
          AppLogger.info('Notification clicked: ${details.payload}');
        }
      },
    );

    // Create channels for Android 8.0+
    if (Platform.isAndroid) {
      final flutterLocalNotificationsPluginAndroid =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      await flutterLocalNotificationsPluginAndroid?.createNotificationChannel(const AndroidNotificationChannel(
        'aerodrive_uploads',
        'Uploads',
        description: 'Notifications for file uploads to AeroDrive',
        importance: Importance.low,
      ));

      await flutterLocalNotificationsPluginAndroid?.createNotificationChannel(const AndroidNotificationChannel(
        'aerodrive_downloads',
        'Downloads',
        description: 'Notifications for file downloads from AeroDrive',
        importance: Importance.low,
      ));

      await flutterLocalNotificationsPluginAndroid?.createNotificationChannel(const AndroidNotificationChannel(
        'aerodrive_sync',
        'Sync Status',
        description: 'Background sync and data merge status',
        importance: Importance.low,
      ));

      await flutterLocalNotificationsPluginAndroid?.createNotificationChannel(const AndroidNotificationChannel(
        'aerodrive_backup',
        'Backups',
        description: 'Automated and manual backup status',
        importance: Importance.high,
      ));
    }

    _initialized = true;
  }

  Future<void> requestPermissions() async {
    if (!_isSupported) return;
    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      if (status.isDenied) {
        await Permission.notification.request();
      }
    }
  }

  Future<void> showUploadProgress(int id, String fileName, int progress, int total) async {
    if (!_isSupported) return;
    final int percent = total > 0 ? ((progress / total) * 100).toInt() : 0;
    final androidDetails = AndroidNotificationDetails(
      'aerodrive_uploads',
      'Uploads',
      channelDescription: 'Upload progress',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: 100,
      progress: percent,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'cancel_upload_$id',
          'Cancel Upload',
          showsUserInterface: true,
        ),
      ],
    );
    final details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      id,
      'Uploading $fileName',
      '$percent% - ${_formatBytes(progress)} / ${_formatBytes(total)}',
      details,
    );
  }

  Future<void> showUploadComplete(int id, String fileName) async {
    if (!_isSupported) return;
    const androidDetails = AndroidNotificationDetails(
      'aerodrive_uploads',
      'Uploads',
      channelDescription: 'Upload complete',
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      id,
      'Upload Complete',
      fileName,
      details,
    );
  }

  Future<void> showUploadFailed(int id, String fileName, String reason) async {
    if (!_isSupported) return;
    const androidDetails = AndroidNotificationDetails(
      'aerodrive_uploads',
      'Uploads',
      channelDescription: 'Upload failures',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      id,
      'Upload Failed: $fileName',
      reason,
      details,
    );
  }

  Future<void> showDownloadProgress(int id, String fileName, int progress, int total) async {
    if (!_isSupported) return;
    final int percent = total > 0 ? ((progress / total) * 100).toInt() : 0;
    final androidDetails = AndroidNotificationDetails(
      'aerodrive_downloads',
      'Downloads',
      channelDescription: 'Download progress',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: 100,
      progress: percent,
    );
    final details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      id,
      'Downloading $fileName',
      '$percent% - ${_formatBytes(progress)} / ${_formatBytes(total)}',
      details,
    );
  }

  Future<void> showDownloadComplete(int id, String fileName, String filePath) async {
    if (!_isSupported) return;
    const androidDetails = AndroidNotificationDetails(
      'aerodrive_downloads',
      'Downloads',
      channelDescription: 'Download complete',
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      id,
      'Download Complete',
      fileName,
      details,
      payload: filePath,
    );
  }

  Future<void> showDownloadFailed(int id, String fileName, String reason) async {
    if (!_isSupported) return;
    const androidDetails = AndroidNotificationDetails(
      'aerodrive_downloads',
      'Downloads',
      channelDescription: 'Download failures',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      id,
      'Download Failed: $fileName',
      reason,
      details,
    );
  }

  Future<void> showBackupComplete(String filePath) async {
    if (!_isSupported) return;
    const androidDetails = AndroidNotificationDetails(
      'aerodrive_backup',
      'Backups',
      channelDescription: 'Automated and manual backup status',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      9001,
      'Backup Successful',
      filePath,
      details,
      payload: filePath,
    );
  }

  Future<void> showSyncStatus(String message) async {
    if (!_isSupported) return;
    const androidDetails = AndroidNotificationDetails(
      'aerodrive_sync',
      'Sync Status',
      channelDescription: 'Background sync and data merge status',
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      9002,
      'AeroDrive Sync',
      message,
      details,
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
