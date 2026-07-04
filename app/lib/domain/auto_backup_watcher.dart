import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../core/logger.dart';
import '../core/providers.dart';
import '../core/providers/repository_providers.dart';
import '../data/db/database.dart';

class AutoBackupWatcherService {

  AutoBackupWatcherService(this._ref);
  final Ref _ref;
  final Uuid _uuid = const Uuid();
  final List<StreamSubscription> _subscriptions = [];
  Timer? _pollTimer;
  bool _isRunning = false;

  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;
    AppLogger.info('AutoBackupWatcher: Starting watcher service');
    await _refreshWatchers();
  }

  Future<void> stop() async {
    _isRunning = false;
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _pollTimer?.cancel();
    _pollTimer = null;
    AppLogger.info('AutoBackupWatcher: Stopped watcher service');
  }

  Future<void> _refreshWatchers() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _pollTimer?.cancel();

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final status = await Permission.manageExternalStorage.request();
      if (status.isDenied || status.isPermanentlyDenied) {
        AppLogger.warning('AutoBackupWatcher: MANAGE_EXTERNAL_STORAGE permission denied');
        if (status.isPermanentlyDenied) {
          openAppSettings();
        }
        return;
      }
    }

    final settingsRepo = _ref.read(settingsRepositoryProvider);
    final enabled = await settingsRepo.getSetting('master_autobackup_enabled');
    if (enabled != 'true') {
      AppLogger.info('AutoBackupWatcher: Master switch disabled, skipping');
      return;
    }

    final raw = await settingsRepo.getSetting('tracked_backup_folders');
    if (raw == null || raw.isEmpty) {
      AppLogger.info('AutoBackupWatcher: No tracked folders configured');
      return;
    }

    final List<dynamic> decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      AppLogger.error('AutoBackup: failed to parse profiles JSON', e);
      return;
    }

    for (final profile in decoded) {
      final path = profile['path'] as String?;
      if (path == null || path.isEmpty) continue;
      final dir = Directory(path);
      if (!await dir.exists()) {
        AppLogger.warning('AutoBackupWatcher: Folder not found: $path');
        continue;
      }
      _watchDirectory(dir, Map<String, dynamic>.from(profile));
    }

    AppLogger.info('AutoBackupWatcher: Watching ${_subscriptions.length} directories');
  }

  void _watchDirectory(Directory dir, Map<String, dynamic> profile) {
    try {
      final sub = dir.watch(recursive: true, events: FileSystemEvent.create | FileSystemEvent.modify).listen((event) {
        final entity = File(event.path);
        if (entity.existsSync() && _matchesFilter(event.path, profile)) {
          unawaited(_queueFile(event.path, profile));
        }
      });
      _subscriptions.add(sub);
    } catch (e) {
      AppLogger.error('AutoBackupWatcher: Failed to watch ${dir.path}', e);
    }
  }

  bool _matchesFilter(String filePath, Map<String, dynamic> profile) {
    final ext = filePath.split('.').last.toLowerCase();

    if (profile['include_all'] == true) return true;

    if (profile['include_images'] == true) {
      if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg', 'heic', 'heif'].contains(ext)) return true;
    }
    if (profile['include_videos'] == true) {
      if (['mp4', 'mkv', 'mov', 'avi', 'wmv', 'flv', 'webm', 'm4v', '3gp'].contains(ext)) return true;
    }
    if (profile['include_documents'] == true) {
      if (['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv', 'json', 'xml', 'md'].contains(ext)) return true;
    }
    return false;
  }

  Future<void> _queueFile(String filePath, Map<String, dynamic> profile) async {
    try {
      final db = _ref.read(databaseProvider);
      final file = File(filePath);
      if (!await file.exists()) return;

      final fileSize = await file.length();
      final queueId = _uuid.v4();
      await db.into(db.transferQueue).insert(
        TransferQueueCompanion.insert(
          id: queueId,
          type: const drift.Value('UPLOAD_FILE'),
          status: const drift.Value('PENDING'),
          priority: const drift.Value(1),
          totalBytes: drift.Value(fileSize),
          fileId: drift.Value('$filePath|null'),
          createdAt: drift.Value(DateTime.now()),
        ),
      );
      AppLogger.info('AutoBackupWatcher: Queued file for upload: $filePath');
    } catch (e) {
      AppLogger.error('AutoBackupWatcher: Failed to queue $filePath', e);
    }
  }

  Future<int> scanAllTrackedNow() async {
    var count = 0;
    final settingsRepo = _ref.read(settingsRepositoryProvider);
    final raw = await settingsRepo.getSetting('tracked_backup_folders');
    if (raw == null || raw.isEmpty) return 0;

    final List<dynamic> decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      AppLogger.error('AutoBackup: failed to parse profiles count JSON', e);
      return 0;
    }

    for (final profile in decoded) {
      final path = profile['path'] as String?;
      if (path == null || path.isEmpty) continue;
      final dir = Directory(path);
      if (!await dir.exists()) continue;

      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File && _matchesFilter(entity.path, Map<String, dynamic>.from(profile))) {
          unawaited(_queueFile(entity.path, Map<String, dynamic>.from(profile)));
          count++;
        }
      }
    }
    AppLogger.info('AutoBackupWatcher: Scanned and queued $count files from all tracked folders');
    return count;
  }

  void dispose() {
    stop();
  }
}

final autoBackupWatcherProvider = Provider<AutoBackupWatcherService>((ref) {
  final service = AutoBackupWatcherService(ref);
  ref.onDispose(service.dispose);
  return service;
});
