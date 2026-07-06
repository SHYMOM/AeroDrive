import 'dart:io';

import 'package:archive/archive_io.dart' hide File;
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/logger.dart';
import '../core/providers.dart';
import '../core/providers/repository_providers.dart';
import '../core/providers/security_providers.dart';
import '../data/db/database.dart';
import '../features/telegram/telegram_service.dart';
import 'recovery/manifest_encoder.dart';

/// Callback for ZIP progress: (filesProcessed, totalFiles, currentFilePath)
typedef ZipProgressCallback = void Function(int processed, int total, String currentFile);

class FolderScanner {

  FolderScanner(this._ref) {
    _db = _ref.read(databaseProvider);
  }
  final Ref _ref;
  late final AeroDriveDatabase _db;
  final Uuid _uuid = const Uuid();

  /// Uploads folder metadata manifest as a 1px transparent PNG to Telegram.
  Future<void> _uploadFolderManifest(String folderId, String folderName, String? parentId) async {
    try {
      final telegram = _ref.read(telegramServiceProvider.notifier);
      final activeChannelStr = await _ref.read(settingsRepositoryProvider).getSetting('active_channel_id');
      final masterKeyBytes = _ref.read(masterKeyProvider);

      if (activeChannelStr != null && masterKeyBytes != null) {
        final chatId = int.parse(activeChannelStr);
        final cipher = AesGcm.with256bits();
        final secretKey = await cipher.newSecretKeyFromBytes(masterKeyBytes);

        final manifestCaption = await ManifestEncoder.encodeFolderManifest(
          folderId: folderId,
          folderName: folderName,
          parentFolderId: parentId,
          masterKey: secretKey,
        );

        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/folder_$folderId.png');

        final pngBytes = Uint8List.fromList([
          137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 108, 137, 0, 0, 0, 11, 73, 68, 65, 84, 120, 156, 99, 96, 0, 0, 0, 2, 0, 1, 226, 33, 188, 51, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130
        ]);
        await tempFile.writeAsBytes(pngBytes);
        await telegram.uploadDocument(chatId, tempFile.path, caption: manifestCaption);
        if (await tempFile.exists()) await tempFile.delete();
      }
    } catch (e) {
      debugPrint("FolderScanner: Failed to upload folder manifest: $e");
    }
  }

  /// Scans a path and queues it for upload.
  ///
  /// * Single file → queues directly.
  /// * Directory with [zipFolder]=false (default) → walks recursively, creates
  ///   DB folder entries mirroring the directory tree, queues each file individually.
  ///   Files over 1.5 GB are automatically chunked by the upload pipeline.
  /// * Directory with [zipFolder]=true → creates a ZIP archive and queues that.
  ///
  /// [onProgress] optional callback for ZIP creation progress (only used when zipping).
  Future<void> scanAndQueueDirectory(
    String rootDirPath,
    String? targetParentFolderId, {
    ZipProgressCallback? onProgress,
    bool zipFolder = false,
  }) async {
    final file = File(rootDirPath);
    if (await file.exists() && !await FileSystemEntity.isDirectory(rootDirPath)) {
      await _queueSingleFile(rootDirPath, targetParentFolderId);
      return;
    }

    final rootDir = Directory(rootDirPath);
    if (!await rootDir.exists()) return;

    if (zipFolder) {
      await _zipAndQueueDirectory(rootDir, targetParentFolderId, onProgress: onProgress);
    } else {
      await _walkAndQueueDirectory(rootDir, targetParentFolderId);
    }
  }

  /// Queues a single file for upload.
  Future<void> _queueSingleFile(String path, String? targetFolderId) async {
    final f = File(path);
    final fileSize = await f.length();
    final queueId = _uuid.v4();
    await _db.into(_db.transferQueue).insert(
      TransferQueueCompanion.insert(
        id: queueId,
        type: const drift.Value('UPLOAD_FILE'),
        status: const drift.Value('PENDING'),
        priority: const drift.Value(1),
        totalBytes: drift.Value(fileSize),
        fileId: drift.Value('${f.path}|${targetFolderId ?? ''}'),
        createdAt: drift.Value(DateTime.now()),
      ),
    );
  }

  /// Recursively walks a directory tree, creates DB folder entries, and queues
  /// each file individually. The upload pipeline handles chunking for large files.
  /// Bug #4 fix: Added error handling per-entity so a single failure won't stall
  /// the entire folder upload. Added logging for debugging stalls.
  Future<void> _walkAndQueueDirectory(Directory dir, String? parentFolderId) async {
    final folderName = dir.path.contains('/') ? dir.path.split('/').last : dir.path.split('\\').last;

    // Create DB folder entry
    final folderId = _uuid.v4();
    await _db.into(_db.folders).insert(
      FoldersCompanion.insert(
        id: folderId,
        name: folderName,
        parentId: drift.Value(parentFolderId),
        createdAt: drift.Value(DateTime.now()),
      ),
    );

    // Upload folder manifest (non-blocking — don't let manifest failure stall file queuing)
    // Bug #4 fix: Removed `await` so this actually runs asynchronously.
    _uploadFolderManifest(folderId, folderName, parentFolderId)
        .timeout(const Duration(seconds: 30), onTimeout: () {
      AppLogger.warning('FolderScanner: Manifest upload timed out for "$folderName" — continuing with file queuing');
    }).catchError((e) {
      AppLogger.error('FolderScanner: Manifest upload failed for "$folderName" — continuing', e);
    });

    // Walk contents — each entity is handled independently
    var filesQueued = 0;
    var foldersQueued = 0;
    var errors = 0;

    try {
      await for (final entity in dir.list(followLinks: false)) {
        try {
          if (entity is File) {
            await _queueSingleFile(entity.path, folderId);
            filesQueued++;
          } else if (entity is Directory) {
            await _walkAndQueueDirectory(entity, folderId);
            foldersQueued++;
          }
        } catch (e) {
          errors++;
          AppLogger.error('FolderScanner: Failed to process ${entity.path}', e);
          // Continue with next entity — don't stall the whole folder
        }
      }
    } catch (e) {
      errors++;
      AppLogger.error('FolderScanner: Failed to list directory ${dir.path} - possible permission issue', e);
    }

    AppLogger.info('FolderScanner: "$folderName" complete — $filesQueued files, $foldersQueued subfolders, $errors errors');
  }

  /// Creates a ZIP archive of the folder and queues it as a single file.
  Future<void> _zipAndQueueDirectory(
    Directory rootDir,
    String? targetParentFolderId, {
    ZipProgressCallback? onProgress,
  }) async {
    final rootDirPath = rootDir.path;
    final folderName = rootDirPath.contains('/') ? rootDirPath.split('/').last : rootDirPath.split('\\').last;

    // Create a folder entry in DB
    final folderId = _uuid.v4();
    await _db.into(_db.folders).insert(
      FoldersCompanion.insert(
        id: folderId,
        name: folderName,
        parentId: drift.Value(targetParentFolderId),
        createdAt: drift.Value(DateTime.now()),
      ),
    );

    await _uploadFolderManifest(folderId, folderName, targetParentFolderId);

    // Create ZIP
    final tempDir = await getTemporaryDirectory();
    final safeFolderName = folderName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final zipPath = '${tempDir.path}/$safeFolderName.zip';

    AppLogger.info('FolderScanner: creating ZIP archive of $rootDirPath -> $zipPath');
    await _createZipArchive(rootDirPath, zipPath, onProgress: onProgress);

    final zipFile = File(zipPath);
    if (!await zipFile.exists()) {
      AppLogger.error('FolderScanner: ZIP creation failed — file not found at $zipPath');
      return;
    }

    final zipSize = await zipFile.length();
    AppLogger.info('FolderScanner: ZIP created ($zipSize bytes), queuing for upload');

    final queueId = _uuid.v4();
    await _db.into(_db.transferQueue).insert(
      TransferQueueCompanion.insert(
        id: queueId,
        type: const drift.Value('UPLOAD_FILE'),
        status: const drift.Value('PENDING'),
        priority: const drift.Value(1),
        totalBytes: drift.Value(zipSize),
        fileId: drift.Value('$zipPath|${targetParentFolderId ?? ''}'),
        createdAt: drift.Value(DateTime.now()),
      ),
    );
  }

  /// Creates a ZIP archive of [sourceDir] at [zipPath] using the `archive` package.
  /// Bug #3 fix: Uses ZipFileEncoder to stream the zip directly to disk, preventing OOM.
  Future<void> _createZipArchive(
    String sourceDir,
    String zipPath, {
    ZipProgressCallback? onProgress,
  }) async {
    final dir = Directory(sourceDir);
    final allFiles = <FileSystemEntity>[];

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) allFiles.add(entity);
    }

    final total = allFiles.length;
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    
    var processed = 0;

    for (final entity in allFiles) {
      final file = entity as File;
      final endsWithSeparator = sourceDir.endsWith('/') || sourceDir.endsWith('\\');
      final relativePath = file.path.substring(sourceDir.length + (endsWithSeparator ? 0 : 1));
      final fileSize = await file.length();

      // Bug #3 fix: Skip files larger than 200 MB in ZIP — they should be
      // uploaded individually as chunked files, not bundled into a ZIP.
      if (fileSize > 200 * 1024 * 1024) {
        AppLogger.warning('FolderScanner: Skipping ${file.path} (${fileSize ~/ (1024 * 1024)} MB) — too large for ZIP archive');
        processed++;
        onProgress?.call(processed, total, relativePath);
        continue;
      }

      // Stream directly to the output zip file to prevent OOM
      encoder.addFile(file, relativePath);
      processed++;
      onProgress?.call(processed, total, relativePath);
    }

    encoder.close();
  }
}

final folderScannerProvider = Provider<FolderScanner>(FolderScanner.new);
