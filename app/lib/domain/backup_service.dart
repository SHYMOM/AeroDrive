import 'dart:convert';
import 'dart:io' show Directory, File, Platform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cryptography/cryptography.dart';

import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/core/providers/security_providers.dart';
import 'package:aerodrive/core/logger.dart';
import 'package:aerodrive/features/settings/dropbox_service.dart';

class BackupService {
  final Ref _ref;

  BackupService(this._ref);

  Future<Directory> getOrCreateBackupDir() async {
    // Prefer public Downloads/AeroDrive/Backup when available
    final publicDir = Directory('/storage/emulated/0/Download/AeroDrive/Backup');
    if (await publicDir.exists()) {
      return publicDir;
    }

    // Fallback to app-internal documents directory
    final baseDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory(p.join(baseDir.path, 'AeroDrive', 'Backup'));
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

  /// Ensures the public AeroDrive folder tree exists. Requests storage
  /// permission and returns an error message if creation fails.
  static Future<String?> ensurePublicFolders() async {
    try {
      if (Platform.isAndroid) {
        final status = await Permission.manageExternalStorage.request();
        if (!status.isGranted) {
          return 'Storage permission denied. Grant "Manage all files" access in App Settings.';
        }
      }

      final downloadsDir = Directory('/storage/emulated/0/Download/AeroDrive');
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      for (final sub in ['Backup', 'Photos', 'Videos', 'Documents', 'Music']) {
        final subDir = Directory('${downloadsDir.path}/$sub');
        if (!await subDir.exists()) {
          await subDir.create(recursive: true);
        }
      }

      return null; // success
    } catch (e) {
      return 'Failed to create app folders: $e';
    }
  }

  Future<Map<String, dynamic>> _collectBackupData({
    required bool exportDatabase,
    required bool exportSettings,
  }) async {
    final db = _ref.read(databaseProvider);
    final Map<String, dynamic> backupData = {
      'version': 1,
      'createdAt': DateTime.now().toIso8601String(),
    };

    if (exportDatabase) {
      backupData['database'] = {
        'folders': (await db.select(db.folders).get()).map((e) => e.toJson()).toList(),
        'files': (await db.select(db.files).get()).map((e) => e.toJson()).toList(),
        'chunks': (await db.select(db.chunks).get()).map((e) => e.toJson()).toList(),
        'channels': (await db.select(db.channels).get()).map((e) => e.toJson()).toList(),
        'accounts': (await db.select(db.accounts).get()).map((e) => e.toJson()).toList(),
        'tags': (await db.select(db.tags).get()).map((e) => e.toJson()).toList(),
        'file_tags': (await db.select(db.fileTags).get()).map((e) => e.toJson()).toList(),
        'share_links': (await db.select(db.shareLinks).get()).map((e) => e.toJson()).toList(),
        'transfer_queue': (await db.select(db.transferQueue).get()).map((e) => e.toJson()).toList(),
        'face_clusters': (await db.select(db.faceClusters).get()).map((e) => e.toJson()).toList(),
        'photo_faces': (await db.select(db.photoFaces).get()).map((e) => e.toJson()).toList(),
        'backup_history': (await db.select(db.backupHistory).get()).map((e) => e.toJson()).toList(),
      };
    }

    if (exportSettings) {
      backupData['settings'] = (await db.select(db.settings).get()).map((e) => e.toJson()).toList();
    }

    return backupData;
  }

  Future<String> exportBackup({
    required bool exportDatabase,
    required bool exportSettings,
    String? customPath,
  }) async {
    // Bug 9 fix: Always ensure folders exist and permissions are granted
    // before attempting to export. If permission fails, throw error.
    final permError = await ensurePublicFolders();
    if (permError != null) {
      throw Exception(permError);
    }

    final data = await _collectBackupData(
      exportDatabase: exportDatabase,
      exportSettings: exportSettings,
    );
    final jsonString = jsonEncode(data);

    String finalPath;
    if (customPath != null) {
      finalPath = customPath;
    } else {
      final dir = await getOrCreateBackupDir();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      finalPath = p.join(dir.path, 'aerodrive_backup_$timestamp.aerobackup');
    }

    final file = File(finalPath);
    await file.writeAsString(jsonString);

    // Bug 9 fix: Verify the file was actually written and is not empty.
    if (!await file.exists()) {
      throw Exception('Failed to write backup file: file does not exist at $finalPath after write.');
    }
    
    final writtenSize = await file.length();
    if (writtenSize == 0) {
      await file.delete().catchError((_) => null);
      throw Exception('Failed to write backup file: file is empty.');
    }

    final db = _ref.read(databaseProvider);
    await db.into(db.backupHistory).insert(
      BackupHistoryCompanion.insert(
        id: const Uuid().v4(),
        type: Value('export'),
        filePath: Value(finalPath),
        fileSize: Value(writtenSize),
        fileCount: Value(
          ((data['database'] as Map<String, dynamic>?)?.values
              .fold<int>(0, (sum, list) => sum + ((list as List?)?.length ?? 0)) ?? 0)
        ),
        createdAt: Value(DateTime.now()),
        isEncrypted: const Value(false),
      ),
    );

    return finalPath;
  }

  Future<bool> dropboxBackup(String backupFilePath) async {
    try {
      final dropboxService = _ref.read(dropboxServiceProvider.notifier);
      if (!dropboxService.connected) {
        AppLogger.warning('BackupService: Dropbox not connected');
        return false;
      }

      final token = await _getDropboxToken();
      if (token == null) return false;

      final file = File(backupFilePath);
      if (!await file.exists()) {
        AppLogger.error('BackupService: Backup file not found at $backupFilePath');
        return false;
      }

      final bytes = await file.readAsBytes();
      final fileName = p.basename(backupFilePath);

      final response = await http.post(
        Uri.parse('https://content.dropboxapi.com/2/files/upload'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/octet-stream',
          'Dropbox-API-Arg': jsonEncode({
            'path': '/AeroDrive/$fileName',
            'mode': 'overwrite',
            'autorename': true,
          }),
        },
        body: bytes,
      );

      if (response.statusCode == 200) {
        final db = _ref.read(databaseProvider);
        await db.into(db.backupHistory).insert(
          BackupHistoryCompanion.insert(
            id: const Uuid().v4(),
            type: Value('dropbox'),
            filePath: Value('/AeroDrive/$fileName'),
            fileSize: Value(bytes.length),
            createdAt: Value(DateTime.now()),
            isEncrypted: const Value(false),
          ),
        );
        return true;
      } else {
        AppLogger.error('BackupService: Dropbox upload failed: ${response.statusCode} ${response.body}');
        return false;
      }
    } catch (e) {
      AppLogger.error('BackupService: Dropbox backup failed', e);
      return false;
    }
  }

  Future<String?> _getDropboxToken() async {
    try {
      return await _secureStorage.read(key: 'dropbox_access_token');
    } catch (_) {
      return null;
    }
  }

  Future<void> runScheduledBackup() async {
    try {
      AppLogger.info('BackupService: Running scheduled backup...');

      final path = await exportBackup(
        exportDatabase: true,
        exportSettings: true,
      );
      AppLogger.info('BackupService: Local backup saved to $path');

      final masterKeyList = _ref.read(masterKeyProvider);
      if (masterKeyList != null) {
        AppLogger.info('BackupService: Ready to sync with external backups if configured');
      } else {
        AppLogger.warning('BackupService: Skipping external secure backups — vault locked');
      }

      await dropboxBackup(path);
      AppLogger.info('BackupService: Dropbox backup completed');

      AppLogger.info('BackupService: Scheduled backup completed successfully');
    } catch (e, s) {
      AppLogger.error('BackupService: Scheduled backup failed', e, s);
    }
  }
}

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(ref);
});

final _secureStorage = const FlutterSecureStorage();
