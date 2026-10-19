import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../core/logger.dart';
import '../core/providers.dart';
import '../core/providers/repository_providers.dart';
import '../data/db/database.dart';
import '../features/drive/providers/drive_providers.dart';
import 'folder_scanner.dart';

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

    // Start periodic background scanner/sync while app is open (every 5 minutes)
    _pollTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      await runAllSyncProfiles();
    });

    // Run initial sync right away
    Future.delayed(const Duration(seconds: 5), () async {
      await runAllSyncProfiles();
    });
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

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        AppLogger.warning(
          'AutoBackupWatcher: MANAGE_EXTERNAL_STORAGE permission not granted. '
          'Please grant "Manage All Files" access in App Settings > Permissions for auto-backup to work.'
        );
        // Don't return here — try to continue anyway. Some paths (like app-internal)
        // may still be accessible. The watcher will log per-folder errors if access fails.
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
      final sub = dir.watch(recursive: true).listen((event) {
        final path = event.path;
        final mode = profile['backupMode'] as String? ?? 'local_to_drive';
        final deleteBehavior = profile['deleteBehavior'] as String? ?? 'dont_delete';

        if (event is FileSystemModifyEvent || event is FileSystemCreateEvent) {
          final entity = File(path);
          if (entity.existsSync() && _matchesFilter(path, profile)) {
            if (mode == 'local_to_drive' || mode == 'both') {
              unawaited(_queueFile(path, profile));
            }
          }
        } else if (event is FileSystemDeleteEvent) {
          if (deleteBehavior == 'sync_deletions') {
            if (mode == 'local_to_drive' || mode == 'both') {
              unawaited(_handleLocalDelete(path, profile));
            }
          }
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

  Future<String?> _resolveBackupFolderId(String filePath, String trackedFolderPath, String? destinationFolderId) async {
    final db = _ref.read(databaseProvider);
    
    // Normalize paths to ensure substring matching is correct
    final normalizedFilePath = filePath.replaceAll('\\', '/');
    final normalizedTrackedPath = trackedFolderPath.replaceAll('\\', '/');
    final normTracked = normalizedTrackedPath.endsWith('/')
        ? normalizedTrackedPath.substring(0, normalizedTrackedPath.length - 1)
        : normalizedTrackedPath;

    if (!normalizedFilePath.toLowerCase().startsWith(normTracked.toLowerCase())) {
      return destinationFolderId;
    }
    
    final relativePath = normalizedFilePath.substring(normTracked.length);
    final parts = relativePath.split('/').where((p) => p.isNotEmpty).toList();

    if (destinationFolderId != null) {
      String? currentFolderId = destinationFolderId;
      if (parts.length > 1) {
        for (final folderName in parts.sublist(0, parts.length - 1)) {
          var folder = await (db.select(db.folders)
            ..where((f) => f.name.equals(folderName) & 
                (currentFolderId == null ? f.parentId.isNull() : f.parentId.equals(currentFolderId)) & 
                f.deletedAt.isNull())
          ).get().then((list) => list.firstOrNull);

          if (folder == null) {
            final newId = _uuid.v4();
            await db.into(db.folders).insert(
              FoldersCompanion.insert(
                id: newId,
                name: folderName,
                parentId: drift.Value(currentFolderId),
                createdAt: drift.Value(DateTime.now()),
              )
            );
            try {
              unawaited(_ref.read(folderScannerProvider).uploadFolderManifest(newId, folderName, currentFolderId));
            } catch (e) {
              AppLogger.error('AutoBackupWatcher: Failed to upload folder manifest: $e');
            }
            currentFolderId = newId;
          } else {
            currentFolderId = folder.id;
          }
        }
      }
      return currentFolderId;
    }

    final String deviceName = Platform.isAndroid 
        ? "Android Device" 
        : Platform.isIOS 
            ? "iOS Device" 
            : Platform.isWindows 
                ? "Windows PC" 
                : Platform.isMacOS 
                    ? "Mac" 
                    : "Linux Device";

    final trackedFolderName = trackedFolderPath.contains('/') ? trackedFolderPath.split('/').lastWhere((s) => s.isNotEmpty, orElse: () => "Backup") : trackedFolderPath.split('\\').lastWhere((s) => s.isNotEmpty, orElse: () => "Backup");

    final List<String> folderHierarchy = ["Backups", deviceName, trackedFolderName];
    if (parts.length > 1) {
      folderHierarchy.addAll(parts.sublist(0, parts.length - 1));
    }

    String? currentFolderId;
    for (final folderName in folderHierarchy) {
      var folder = await (db.select(db.folders)
        ..where((f) => f.name.equals(folderName) & 
            (currentFolderId == null ? f.parentId.isNull() : f.parentId.equals(currentFolderId)) & 
            f.deletedAt.isNull())
      ).get().then((list) => list.firstOrNull);

      if (folder == null) {
        final newId = _uuid.v4();
        await db.into(db.folders).insert(
          FoldersCompanion.insert(
            id: newId,
            name: folderName,
            parentId: drift.Value(currentFolderId),
            createdAt: drift.Value(DateTime.now()),
          )
        );
        try {
          unawaited(_ref.read(folderScannerProvider).uploadFolderManifest(newId, folderName, currentFolderId));
        } catch (e) {
          AppLogger.error('AutoBackupWatcher: Failed to upload folder manifest: $e');
        }
        currentFolderId = newId;
      } else {
        currentFolderId = folder.id;
      }
    }

    return currentFolderId;
  }

  Future<void> _queueFile(String filePath, Map<String, dynamic> profile) async {
    try {
      final db = _ref.read(databaseProvider);
      final file = File(filePath);
      if (!await file.exists()) return;

      final fileSize = await file.length();
      final normalizedFilePath = filePath.replaceAll('\\', '/');

      // 1. Comprehensive queue deduplication:
      // Check if this local file is already in transferQueue (PENDING, PROCESSING, ENCRYPTING, or COMPLETED)
      final existingTransfers = await (db.select(db.transferQueue)
        ..where((q) => q.type.equals('UPLOAD_FILE'))
      ).get();

      final alreadyInQueue = existingTransfers.any((task) {
        if (task.status == 'FAILED') return false;
        final queuedRaw = task.fileId?.split('|').firstOrNull ?? '';
        final queuedNormalized = queuedRaw.replaceAll('\\', '/');
        return queuedNormalized.toLowerCase() == normalizedFilePath.toLowerCase();
      });

      if (alreadyInQueue) {
        AppLogger.info('AutoBackupWatcher: File is already in queue or completed: $filePath');
        return;
      }

      final targetFolderId = (profile['destinationFolderId'] == null || profile['destinationFolderId'] == 'null' || profile['destinationFolderId'] == '__root__')
          ? null
          : profile['destinationFolderId'] as String?;

      final folderId = await _resolveBackupFolderId(filePath, profile['path'] as String, targetFolderId);

      // 2. Check if file already exists in Drive with same name and size
      final fileName = filePath.contains('/') ? filePath.split('/').last : filePath.split('\\').last;
      final existing = await (db.select(db.files)
        ..where((f) =>
            f.name.equals(fileName) &
            f.size.equals(fileSize) &
            (folderId == null || folderId == 'null'
                ? (f.folderId.isNull() | f.folderId.equals('null') | f.folderId.equals(''))
                : (f.folderId.equals(folderId) | f.folderId.isNull() | f.folderId.equals('null'))) &
            f.deletedAt.isNull())
      ).get();

      if (existing.isNotEmpty) {
        AppLogger.info('AutoBackupWatcher: File already exists in Drive ($fileName, $fileSize bytes), skipping upload');
        return;
      }

      final targetFileId = '$filePath|${folderId ?? ''}';
      final queueId = _uuid.v4();
      await db.into(db.transferQueue).insert(
        TransferQueueCompanion.insert(
          id: queueId,
          type: const drift.Value('UPLOAD_FILE'),
          status: const drift.Value('PENDING'),
          priority: const drift.Value(1),
          totalBytes: drift.Value(fileSize),
          fileId: drift.Value(targetFileId),
          createdAt: drift.Value(DateTime.now()),
        ),
      );
      AppLogger.info('AutoBackupWatcher: Queued file for upload: $filePath');
    } catch (e) {
      AppLogger.error('AutoBackupWatcher: Failed to queue $filePath', e);
    }
  }

  Future<void> _handleLocalDelete(String filePath, Map<String, dynamic> profile) async {
    try {
      final db = _ref.read(databaseProvider);
      final trackedFolderPath = profile['path'] as String;
      final targetFolderId = (profile['destinationFolderId'] == null || profile['destinationFolderId'] == 'null' || profile['destinationFolderId'] == '__root__')
          ? null
          : profile['destinationFolderId'] as String?;

      final folderId = await _resolveBackupFolderId(filePath, trackedFolderPath, targetFolderId);
      final fileName = filePath.contains('/') ? filePath.split('/').last : filePath.split('\\').last;

      final existing = await (db.select(db.files)
        ..where((f) => f.name.equals(fileName) & (folderId == null ? f.folderId.isNull() : f.folderId.equals(folderId)) & f.deletedAt.isNull())
      ).getSingleOrNull();

      if (existing != null) {
        await _ref.read(fileRepositoryProvider).softDelete(existing.id);
        _ref.read(dbRebuildVersionProvider.notifier).state++;
        AppLogger.info('AutoBackupWatcher: Soft-deleted file in Drive because it was deleted locally: $fileName');
      }
    } catch (e) {
      AppLogger.error('AutoBackupWatcher: Failed to handle local deletion for $filePath', e);
    }
  }

  Future<bool> _isWifiOrWifiNotRequired(Map<String, dynamic> profile) async {
    if (profile['wifiOnly'] != true) return true;
    if (kIsWeb) return true;

    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final interfaces = await NetworkInterface.list();
        var cellularActive = false;
        var wifiActive = false;

        for (final interface in interfaces) {
          final name = interface.name.toLowerCase();
          if (name.contains('wlan') || name.contains('en') || name.contains('eth') || name.contains('wifi')) {
            wifiActive = true;
          }
          if (name.contains('rmnet') || name.contains('pdp') || name.contains('ccmni') || name.contains('cellular')) {
            cellularActive = true;
          }
        }

        if (cellularActive && !wifiActive) {
          AppLogger.warning('AutoBackupWatcher: Wi-Fi only constraint active, but device is on cellular. Skipping sync.');
          return false;
        }
      }
    } catch (_) {}
    return true;
  }

  Future<void> runAllSyncProfiles() async {
    final settingsRepo = _ref.read(settingsRepositoryProvider);
    final enabled = await settingsRepo.getSetting('master_autobackup_enabled');
    if (enabled != 'true') return;

    final raw = await settingsRepo.getSetting('tracked_backup_folders');
    if (raw == null || raw.isEmpty) return;

    final List<dynamic> decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      return;
    }

    for (final profile in decoded) {
      final mapProfile = Map<String, dynamic>.from(profile);
      if (await _isWifiOrWifiNotRequired(mapProfile)) {
        await runProfileSync(mapProfile);
      }
    }
  }

  Future<void> runProfileSync(Map<String, dynamic> profile) async {
    try {
      final path = profile['path'] as String?;
      if (path == null || path.isEmpty) return;

      final localDir = Directory(path);
      if (!await localDir.exists()) return;

      final db = _ref.read(databaseProvider);
      final targetFolderId = (profile['destinationFolderId'] == null || profile['destinationFolderId'] == 'null' || profile['destinationFolderId'] == '__root__')
          ? null
          : profile['destinationFolderId'] as String?;

      final mode = profile['backupMode'] as String? ?? 'local_to_drive';
      final deleteBehavior = profile['deleteBehavior'] as String? ?? 'dont_delete';

      // 1. Local to Drive Sync (Uploads)
      if (mode == 'local_to_drive' || mode == 'both') {
        await for (final entity in localDir.list(recursive: true, followLinks: false)) {
          if (entity is File && _matchesFilter(entity.path, profile)) {
            final normalizedFilePath = entity.path.replaceAll('\\', '/');
            final existingTransfers = await (db.select(db.transferQueue)
              ..where((q) => q.type.equals('UPLOAD_FILE'))
            ).get();

            final alreadyInQueue = existingTransfers.any((task) {
              if (task.status == 'FAILED') return false;
              final queuedRaw = task.fileId?.split('|').firstOrNull ?? '';
              final queuedNormalized = queuedRaw.replaceAll('\\', '/');
              return queuedNormalized.toLowerCase() == normalizedFilePath.toLowerCase();
            });

            if (alreadyInQueue) {
              continue;
            }

            final fileName = entity.path.contains('/') ? entity.path.split('/').last : entity.path.split('\\').last;
            final resolvedFolderId = await _resolveBackupFolderId(entity.path, path, targetFolderId);

            final existing = await (db.select(db.files)
              ..where((f) =>
                  f.name.equals(fileName) &
                  f.size.equals(entity.lengthSync()) &
                  (resolvedFolderId == null || resolvedFolderId == 'null'
                      ? (f.folderId.isNull() | f.folderId.equals('null') | f.folderId.equals(''))
                      : (f.folderId.equals(resolvedFolderId) | f.folderId.isNull() | f.folderId.equals('null'))) &
                  f.deletedAt.isNull())
            ).get();

            if (existing.isEmpty) {
              await _queueFile(entity.path, profile);
            }
          }
        }
      }

      // 2. Drive to Local Sync (Downloads)
      if (mode == 'drive_to_local' || mode == 'both') {
        final targetId = targetFolderId;
        // Fetch all files on Drive under targetId
        final dbFiles = await (db.select(db.files)
          ..where((f) => targetId == null ? f.folderId.isNull() : f.folderId.equals(targetId))
          ..where((f) => f.deletedAt.isNull())
        ).get();

        for (final dbFile in dbFiles) {
          final localFilePath = p.join(path, dbFile.name);
          final localFile = File(localFilePath);
          if (!await localFile.exists()) {
            final targetDownloadId = '${dbFile.id}|$localFilePath';
            final existingDownload = await (db.select(db.transferQueue)
              ..where((q) => q.fileId.equals(targetDownloadId) & 
                  (q.status.equals('PENDING') | q.status.equals('PROCESSING')))
            ).get();

            if (existingDownload.isEmpty) {
              // Queue download with output path encoded
              await db.into(db.transferQueue).insert(
                TransferQueueCompanion.insert(
                  id: _uuid.v4(),
                  fileId: drift.Value(targetDownloadId),
                  type: const drift.Value('DOWNLOAD_FILE'),
                  status: const drift.Value('PENDING'),
                  priority: const drift.Value(1),
                  createdAt: drift.Value(DateTime.now()),
                )
              );
              AppLogger.info('AutoBackupWatcher: Queued file for download: ${dbFile.name}');
            }
          }
        }
      }

      // 3. Deletions Policy Sync
      if (deleteBehavior == 'sync_deletions') {
        // Local deleted -> Delete on Drive
        if (mode == 'local_to_drive' || mode == 'both') {
          final targetId = targetFolderId;
          final dbFiles = await (db.select(db.files)
            ..where((f) => targetId == null ? f.folderId.isNull() : f.folderId.equals(targetId))
            ..where((f) => f.deletedAt.isNull())
          ).get();

          for (final dbFile in dbFiles) {
            final localFilePath = p.join(path, dbFile.name);
            final localFile = File(localFilePath);
            if (!await localFile.exists()) {
              await _ref.read(fileRepositoryProvider).softDelete(dbFile.id);
              _ref.read(dbRebuildVersionProvider.notifier).state++;
              AppLogger.info('AutoBackupWatcher: Deleted file on Drive because it was deleted locally: ${dbFile.name}');
            }
          }
        }

        // Drive deleted -> Delete locally
        if (mode == 'drive_to_local' || mode == 'both') {
          await for (final entity in localDir.list(recursive: true, followLinks: false)) {
            if (entity is File && _matchesFilter(entity.path, profile)) {
              final fileName = entity.path.contains('/') ? entity.path.split('/').last : entity.path.split('\\').last;
              final targetId = targetFolderId;
              final dbFile = await (db.select(db.files)
                ..where((f) => f.name.equals(fileName) & (targetId == null ? f.folderId.isNull() : f.folderId.equals(targetId)) & f.deletedAt.isNull())
              ).getSingleOrNull();

              if (dbFile == null) {
                await entity.delete();
                AppLogger.info('AutoBackupWatcher: Deleted local file because it was deleted on Drive: ${entity.path}');
              }
            }
          }
        }
      }
    } catch (e) {
      AppLogger.error('AutoBackupWatcher: runProfileSync failed', e);
    }
  }

  Future<int> scanAllTrackedNow() async {
    await runAllSyncProfiles();
    return 0;
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
