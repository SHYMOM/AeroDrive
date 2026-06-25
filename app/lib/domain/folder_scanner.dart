import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:drift/drift.dart' as drift;
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/core/providers/security_providers.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:aerodrive/domain/recovery/manifest_encoder.dart';
import 'package:aerodrive/features/telegram/telegram_service.dart';

class FolderScanner {
  final Ref _ref;
  final AeroDriveDatabase _db;
  final Uuid _uuid = const Uuid();

  FolderScanner(this._ref) : _db = _ref.read(databaseProvider);

  /// Helper to upload folder metadata manifest as a 1px transparent PNG to Telegram
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
        
        // 1px transparent PNG bytes representation
        final pngBytes = Uint8List.fromList([
          137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 108, 137, 0, 0, 0, 11, 73, 68, 65, 84, 120, 156, 99, 96, 0, 0, 0, 2, 0, 1, 226, 33, 188, 51, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130
        ]);
        await tempFile.writeAsBytes(pngBytes);

        await telegram.uploadDocument(chatId, tempFile.path, caption: manifestCaption);

        // Delete temp file after TDLib handoff
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    } catch (e) {
      debugPrint("FolderScanner: Failed to upload folder manifest: $e");
    }
  }

  /// Recursively scans a directory dropped from the OS or queues a single file,
  /// creates the folder structure in the database, and queues files for upload.
  Future<void> scanAndQueueDirectory(String rootDirPath, String? targetParentFolderId) async {
    final file = File(rootDirPath);
    if (await file.exists()) {
      final queueId = _uuid.v4();
      final fileSize = await file.length();
      await _db.into(_db.transferQueue).insert(
        TransferQueueCompanion.insert(
          id: queueId,
          type: const drift.Value('UPLOAD_FILE'),
          status: const drift.Value('PENDING'),
          priority: const drift.Value(1),
          totalBytes: drift.Value(fileSize),
          fileId: drift.Value('${file.path}|$targetParentFolderId'),
          createdAt: drift.Value(DateTime.now()),
        ),
      );
      return;
    }

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

    // Upload folder metadata to Telegram immediately
    await _uploadFolderManifest(rootFolderId, rootFolderName, targetParentFolderId);

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

          // Upload folder metadata to Telegram immediately
          await _uploadFolderManifest(newFolderId, folderName, parentId);
        } else if (entity is File) {
          // Find the parent's UUID
          final parentPath = entity.parent.path;
          final parentId = pathToUuidMap[parentPath] ?? rootFolderId;

          // Queue the file for upload
          final queueId = _uuid.v4();
          final fileSize = await entity.length();

          await _db.into(_db.transferQueue).insert(
            TransferQueueCompanion.insert(
              id: queueId,
              type: const drift.Value('UPLOAD_FILE'),
              status: const drift.Value('PENDING'),
              priority: const drift.Value(1),
              totalBytes: drift.Value(fileSize),
              fileId: drift.Value('${entity.path}|$parentId'), // format: LocalPath|ParentFolderId
              createdAt: drift.Value(DateTime.now()),
            ),
          );
        }
      } catch (e) {
        debugPrint("Error scanning ${entity.path}: $e");
      }
    }
  }
}

final folderScannerProvider = Provider<FolderScanner>((ref) {
  return FolderScanner(ref);
});
