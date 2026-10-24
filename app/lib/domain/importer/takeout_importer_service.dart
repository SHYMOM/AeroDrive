import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/logger.dart';
import '../../core/providers.dart';
import '../../data/db/database.dart';
import '../folder_scanner.dart';

class TakeoutImportSummary {
  const TakeoutImportSummary({
    required this.totalMediaFiles,
    required this.sidecarsMatched,
    required this.foldersCreated,
    required this.totalBytes,
  });

  final int totalMediaFiles;
  final int sidecarsMatched;
  final int foldersCreated;
  final int totalBytes;
}

class TakeoutImporterService {
  TakeoutImporterService(this._ref);

  final Ref _ref;
  final Uuid _uuid = const Uuid();

  static const Set<String> _mediaExtensions = {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif', 'dng',
    'cr2', 'nef', 'arw', 'mp4', 'mov', 'm4v', '3gp', 'avi', 'mkv', 'webm',
  };

  /// Analyzes a Google Takeout directory without enqueuing.
  Future<TakeoutImportSummary> analyzeDirectory(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      return const TakeoutImportSummary(
        totalMediaFiles: 0,
        sidecarsMatched: 0,
        foldersCreated: 0,
        totalBytes: 0,
      );
    }

    var mediaCount = 0;
    var sidecarCount = 0;
    var totalBytes = 0;
    final folderPaths = <String>{};

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is Directory) {
        folderPaths.add(entity.path);
      } else if (entity is File) {
        final ext = entity.path.split('.').last.toLowerCase();
        if (_mediaExtensions.contains(ext)) {
          mediaCount++;
          totalBytes += await entity.length();
          final directSidecar = File('${entity.path}.json');
          if (await directSidecar.exists()) {
            sidecarCount++;
          } else {
            final dot = entity.path.lastIndexOf('.');
            if (dot > 0 && await File('${entity.path.substring(0, dot)}.json').exists()) {
              sidecarCount++;
            }
          }
        }
      }
    }

    return TakeoutImportSummary(
      totalMediaFiles: mediaCount,
      sidecarsMatched: sidecarCount,
      foldersCreated: folderPaths.length,
      totalBytes: totalBytes,
    );
  }

  /// Imports all media from a Google Takeout folder into AeroDrive.
  Stream<double> importTakeoutDirectory(
    String path, {
    String? targetParentFolderId,
    void Function(String)? onStatus,
  }) async* {
    final dir = Directory(path);
    if (!await dir.exists()) return;

    final db = _ref.read(databaseProvider);
    final folderScanner = _ref.read(folderScannerProvider);

    onStatus?.call('Discovering media files and sidecars...');
    final mediaFiles = <File>[];

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final ext = entity.path.split('.').last.toLowerCase();
        if (_mediaExtensions.contains(ext)) {
          mediaFiles.add(entity);
        }
      }
    }

    final total = mediaFiles.length;
    if (total == 0) {
      yield 1.0;
      return;
    }

    // Map local directory path to created folder ID in SQLite
    final createdFolderMap = <String, String>{};

    for (var i = 0; i < total; i++) {
      final file = mediaFiles[i];
      final parentDirPath = file.parent.path;

      // Ensure directory structure in database
      String? parentFolderId = targetParentFolderId;
      if (parentDirPath != dir.path) {
        if (createdFolderMap.containsKey(parentDirPath)) {
          parentFolderId = createdFolderMap[parentDirPath];
        } else {
          // Create hierarchy
          parentFolderId = await _ensureFolderHierarchy(
            rootDir: dir,
            currentDir: file.parent,
            targetParentFolderId: targetParentFolderId,
            cache: createdFolderMap,
            db: db,
            scanner: folderScanner,
          );
        }
      }

      final fileName = file.path.contains('/') ? file.path.split('/').last : file.path.split('\\').last;
      onStatus?.call('Queuing ($i/$total): $fileName');

      // Check if sidecar exists for metadata logging
      final fileSize = await file.length();
      final queueId = _uuid.v4();

      await db.into(db.transferQueue).insert(
        TransferQueueCompanion.insert(
          id: queueId,
          type: const drift.Value('UPLOAD_FILE'),
          status: const drift.Value('PENDING'),
          priority: const drift.Value(1),
          totalBytes: drift.Value(fileSize),
          fileId: drift.Value('${file.path}|${parentFolderId ?? ''}'),
          createdAt: drift.Value(DateTime.now()),
        ),
      );

      yield (i + 1) / total;
    }

    onStatus?.call('Import complete! $total items queued.');
    yield 1.0;
  }

  Future<String> _ensureFolderHierarchy({
    required Directory rootDir,
    required Directory currentDir,
    required String? targetParentFolderId,
    required Map<String, String> cache,
    required AeroDriveDatabase db,
    required FolderScanner scanner,
  }) async {
    if (cache.containsKey(currentDir.path)) {
      return cache[currentDir.path]!;
    }

    String? parentId = targetParentFolderId;
    if (currentDir.parent.path != rootDir.path && currentDir.parent.path.startsWith(rootDir.path)) {
      parentId = await _ensureFolderHierarchy(
        rootDir: rootDir,
        currentDir: currentDir.parent,
        targetParentFolderId: targetParentFolderId,
        cache: cache,
        db: db,
        scanner: scanner,
      );
    }

    final folderName = currentDir.path.contains('/') ? currentDir.path.split('/').last : currentDir.path.split('\\').last;
    final folderId = _uuid.v4();
    final now = DateTime.now();

    await db.into(db.folders).insert(
      FoldersCompanion.insert(
        id: folderId,
        name: folderName,
        parentId: drift.Value(parentId),
        createdAt: drift.Value(now),
      ),
    );

    // Non-blocking manifest sync
    scanner.uploadFolderManifest(folderId, folderName, parentId, createdAt: now).catchError((_) {});

    cache[currentDir.path] = folderId;
    return folderId;
  }
}

final takeoutImporterServiceProvider = Provider<TakeoutImporterService>((ref) {
  return TakeoutImporterService(ref);
});
