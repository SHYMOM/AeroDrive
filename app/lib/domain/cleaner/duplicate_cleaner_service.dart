import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/db/database.dart';

class DuplicateGroup {
  DuplicateGroup({
    required this.hashOrKey,
    required this.files,
    required this.totalWastedBytes,
  });

  final String hashOrKey;
  final List<FileData> files;
  final int totalWastedBytes;
}

final duplicateCleanerServiceProvider = Provider<DuplicateCleanerService>((ref) {
  final db = ref.watch(databaseProvider);
  return DuplicateCleanerService(db);
});

class DuplicateCleanerService {
  DuplicateCleanerService(this._db);

  final AeroDriveDatabase _db;

  /// Finds groups of files that share the exact same sha256Hash or identical size & name
  Future<List<DuplicateGroup>> getDuplicateGroups() async {
    final allFiles = await (_db.select(_db.files)..where((f) => f.deletedAt.isNull())).get();
    
    final Map<String, List<FileData>> byHash = {};
    for (final f in allFiles) {
      final key = f.sha256Hash ?? (f.size != null ? '${f.size}_${f.name}' : null);
      if (key == null) continue;
      byHash.putIfAbsent(key, () => []).add(f);
    }

    final List<DuplicateGroup> duplicateGroups = [];
    for (final entry in byHash.entries) {
      if (entry.value.length > 1) {
        // Sort with newest first
        final sorted = List<FileData>.from(entry.value)
          ..sort((a, b) {
            final da = a.createdAt ?? DateTime(0);
            final db = b.createdAt ?? DateTime(0);
            return db.compareTo(da);
          });

        final fileSize = sorted.first.size ?? 0;
        final wastedBytes = fileSize * (sorted.length - 1);

        duplicateGroups.add(DuplicateGroup(
          hashOrKey: entry.key,
          files: sorted,
          totalWastedBytes: wastedBytes,
        ));
      }
    }

    // Sort groups by most wasted space first
    duplicateGroups.sort((a, b) => b.totalWastedBytes.compareTo(a.totalWastedBytes));
    return duplicateGroups;
  }

  /// Finds files exceeding 50 MB
  Future<List<FileData>> getLargeFiles({int thresholdBytes = 50 * 1024 * 1024}) async {
    final query = _db.select(_db.files)
      ..where((f) => f.deletedAt.isNull() & f.size.isBiggerOrEqualValue(thresholdBytes))
      ..orderBy([(f) => drift.OrderingTerm.desc(f.size)]);
    return query.get();
  }

  /// Finds screenshots
  Future<List<FileData>> getScreenshots() async {
    final allFiles = await (_db.select(_db.files)..where((f) => f.deletedAt.isNull())).get();
    return allFiles.where((f) {
      final name = f.name.toLowerCase();
      final mime = (f.mimeType ?? '').toLowerCase();
      return (name.contains('screenshot') || name.contains('screen_shot') || name.startsWith('scr_')) &&
          mime.startsWith('image/');
    }).toList();
  }

  /// Moves selected file IDs to trash
  Future<void> moveToTrash(List<String> fileIds) async {
    if (fileIds.isEmpty) return;
    final now = DateTime.now();
    await (_db.update(_db.files)..where((f) => f.id.isIn(fileIds))).write(
      FilesCompanion(deletedAt: drift.Value(now)),
    );
  }
}
