import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:aerodrive/data/db/database.dart';
import 'package:drift/drift.dart' as drift;

class ThumbnailCacheService {
  final AeroDriveDatabase _db;
  static const int maxCacheSizeBytes = 1024 * 1024 * 1024; // 1 GB

  ThumbnailCacheService(this._db);

  /// Retrieves the correct cache directory based on the platform.
  Future<Directory> _getCacheDirectory() async {
    Directory baseDir;
    if (Platform.isAndroid) {
      baseDir = await getApplicationDocumentsDirectory();
    } else if (Platform.isIOS) {
      baseDir = await getLibraryDirectory(); // iOS Caches might be purged unexpectedly, Library is safer for explicit LRU
    } else {
      baseDir = await getApplicationSupportDirectory();
    }

    final thumbnailDir = Directory(p.join(baseDir.path, 'thumbnails_cache'));
    if (!await thumbnailDir.exists()) {
      await thumbnailDir.create(recursive: true);
    }
    return thumbnailDir;
  }

  /// Saves an encrypted thumbnail to disk and updates the DB reference.
  Future<void> saveThumbnail(String fileId, Uint8List encryptedBytes) async {
    final dir = await _getCacheDirectory();
    final file = File(p.join(dir.path, '$fileId.enc'));
    
    await file.writeAsBytes(encryptedBytes);

    final size = await file.length();
    
    // Update the database record with the file path, size, and access time
    await (_db.update(_db.files)..where((f) => f.id.equals(fileId))).write(
      FilesCompanion(
        thumbnailPath: drift.Value(file.path),
        thumbnailSize: drift.Value(size),
        thumbnailLastAccess: drift.Value(DateTime.now()),
      ),
    );

    // After saving, check if we need to purge
    await _enforceLruCacheLimit();
  }

  /// Retrieves a thumbnail from disk and updates its last access time.
  Future<Uint8List?> getThumbnail(String fileId) async {
    final fileData = await (_db.select(_db.files)..where((f) => f.id.equals(fileId))).getSingleOrNull();
    
    if (fileData == null || fileData.thumbnailPath == null) {
      return null;
    }

    final file = File(fileData.thumbnailPath!);
    if (!await file.exists()) {
      // Cache miss: file deleted by OS or corrupted
      // Nullify the reference in DB to trigger a re-download later
      await (_db.update(_db.files)..where((f) => f.id.equals(fileId))).write(
        const FilesCompanion(
          thumbnailPath: drift.Value(null),
          thumbnailSize: drift.Value(null),
        ),
      );
      return null;
    }

    // Read bytes
    final bytes = await file.readAsBytes();

    // Update LRU timestamp
    await (_db.update(_db.files)..where((f) => f.id.equals(fileId))).write(
      FilesCompanion(
        thumbnailLastAccess: drift.Value(DateTime.now()),
      ),
    );

    return bytes;
  }

  /// Enforces the 1GB LRU limit by deleting the oldest thumbnails.
  Future<void> _enforceLruCacheLimit() async {
    // 1. Calculate total size of thumbnails
    final sizeResult = await _db.customSelect(
      'SELECT SUM(thumbnail_size) as total FROM files WHERE thumbnail_path IS NOT NULL'
    ).getSingle();
    
    final totalSize = sizeResult.read<int?>('total') ?? 0;
    
    if (totalSize <= maxCacheSizeBytes) return;

    // 2. Find files to delete (order by oldest lastAccessTime)
    final itemsToPurge = await (_db.select(_db.files)
      ..where((f) => f.thumbnailPath.isNotNull())
      ..orderBy([(t) => drift.OrderingTerm(expression: t.thumbnailLastAccess, mode: drift.OrderingMode.asc)])
    ).get();

    int currentSize = totalSize;
    
    for (final item in itemsToPurge) {
      if (currentSize <= maxCacheSizeBytes) break;

      if (item.thumbnailPath != null) {
        final file = File(item.thumbnailPath!);
        if (await file.exists()) {
          await file.delete();
        }

        // Remove DB reference
        await (_db.update(_db.files)..where((f) => f.id.equals(item.id))).write(
          const FilesCompanion(
            thumbnailPath: drift.Value(null),
            thumbnailSize: drift.Value(null),
          ),
        );

        currentSize -= (item.thumbnailSize ?? 0);
      }
    }
    
    debugPrint("LRU Cache enforced. New size: ${currentSize ~/ (1024 * 1024)} MB");
  }
}
