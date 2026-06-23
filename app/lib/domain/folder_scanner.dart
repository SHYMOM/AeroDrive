import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:drift/drift.dart' as drift;

class FolderScanner {
  final AeroDriveDatabase _db;
  final Uuid _uuid = const Uuid();

  FolderScanner(this._db);

  /// Recursively scans a directory dropped from the OS, creates the folder
  /// structure in the database, and queues files for upload.
  Future<void> scanAndQueueDirectory(String rootDirPath, String? targetParentFolderId) async {
    final rootDir = Directory(rootDirPath);
    if (!await rootDir.exists()) return;

    // We maintain a map of LocalPath -> FolderUUID
    final Map<String, String> pathToUuidMap = {};

    // Create the root folder in DB first
    final rootFolderName = rootDir.path.split(Platform.pathSeparator).last;
    final rootFolderId = _uuid.v4();
    
    await _db.into(_db.folders).insert(
      FoldersCompanion.insert(
        id: rootFolderId,
        name: rootFolderName,
        parentId: drift.Value(targetParentFolderId),
        createdAt: drift.Value(DateTime.now()),
      ),
    );
    
    pathToUuidMap[rootDir.path] = rootFolderId;

    // Start async recursive scan
    final stream = rootDir.list(recursive: true, followLinks: false);

    await for (final FileSystemEntity entity in stream) {
      try {
        if (entity is Link) {
          continue; // Ignore symlinks to prevent infinite recursion
        }

        if (entity is Directory) {
          // Find the parent's UUID from the map
          final parentPath = entity.parent.path;
          final parentId = pathToUuidMap[parentPath] ?? rootFolderId;

          final newFolderId = _uuid.v4();
          final folderName = entity.path.split(Platform.pathSeparator).last;

          await _db.into(_db.folders).insert(
            FoldersCompanion.insert(
              id: newFolderId,
              name: folderName,
              parentId: drift.Value(parentId),
              createdAt: drift.Value(DateTime.now()),
            ),
          );

          pathToUuidMap[entity.path] = newFolderId;
        } else if (entity is File) {
          // Find the parent's UUID
          final parentPath = entity.parent.path;
          final parentId = pathToUuidMap[parentPath] ?? rootFolderId;

          // Queue the file for upload
          final queueId = _uuid.v4();
          final fileSize = await entity.length();

          // We insert into TransferQueue. The UploadOrchestrator will pick it up,
          // hash it, check for deduplication, chunk it, encrypt it, and upload it.
          await _db.into(_db.transferQueue).insert(
            TransferQueueCompanion.insert(
              id: queueId,
              type: const drift.Value('UPLOAD_FILE'),
              status: const drift.Value('PENDING'),
              priority: const drift.Value(1),
              totalBytes: drift.Value(fileSize),
              // We temporarily store the local OS file path in the errorMessage field 
              // or create a dedicated column. Since we can't change schema now without another rebuild,
              // we will use a custom JSON format or just the fileId field to hold the OS path temporarily 
              // until the file row is created by the orchestrator!
              fileId: drift.Value('${entity.path}|$parentId'), // format: LocalPath|ParentFolderId
              createdAt: drift.Value(DateTime.now()),
            ),
          );
        }
      } catch (e) {
        // Handle read permission errors gracefully
        debugPrint("Error scanning ${entity.path}: $e");
      }
    }
  }
}
