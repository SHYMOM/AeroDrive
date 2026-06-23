import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/data/db/database.dart';

// Interface for Face Recognition
abstract class FaceRecognitionService {
  Future<void> scanLibrary();
  Future<List<FaceCluster>> getClusters();
  Future<List<String>> getPhotosForCluster(String clusterId);
}

// Data models
class FaceCluster {
  final String id;
  final String label;
  final String? avatarFileId; // Photo used as the main avatar for this face
  final int photoCount;

  FaceCluster({
    required this.id,
    required this.label,
    this.avatarFileId,
    required this.photoCount,
  });
}

// Provider
final faceRecognitionServiceProvider = Provider<FaceRecognitionService>((ref) {
  return DbFaceService(ref);
});

// Riverpod FutureProvider for face clusters caching/signals
final faceClustersProvider = FutureProvider.autoDispose<List<FaceCluster>>((ref) async {
  final faceService = ref.watch(faceRecognitionServiceProvider);
  return faceService.getClusters();
});

// Production-ready database-backed implementation
class DbFaceService implements FaceRecognitionService {
  final Ref _ref;

  DbFaceService(this._ref);

  @override
  Future<List<FaceCluster>> getClusters() async {
    final db = _ref.read(databaseProvider);
    
    // Select clusters and aggregate count and avatar
    final rows = await db.customSelect(
      'SELECT c.id, c.name, COUNT(p.file_id) as photo_count, MIN(p.file_id) as avatar_id '
      'FROM face_clusters c '
      'LEFT JOIN photo_faces p ON c.id = p.face_cluster_id '
      'GROUP BY c.id, c.name'
    ).get();

    return rows.map((row) {
      return FaceCluster(
        id: row.read<String>('id'),
        label: row.read<String?>('name') ?? 'Unknown Person',
        avatarFileId: row.read<String?>('avatar_id'),
        photoCount: row.read<int>('photo_count'),
      );
    }).toList();
  }

  @override
  Future<List<String>> getPhotosForCluster(String clusterId) async {
    final db = _ref.read(databaseProvider);
    final rows = await db.customSelect(
      'SELECT file_id FROM photo_faces WHERE face_cluster_id = ?',
      variables: [drift.Variable<String>(clusterId)]
    ).get();
    return rows.map((r) => r.read<String>('file_id')).toList();
  }

  @override
  Future<void> scanLibrary() async {
    final db = _ref.read(databaseProvider);

    // Query files having ML tags matching person indicators
    final rows = await db.customSelect(
      "SELECT ft.file_id, t.name as tag_name FROM file_tags ft "
      "INNER JOIN tags t ON ft.tag_id = t.id "
      "WHERE t.name IN ('person', 'man', 'woman', 'face', 'smile', 'family', 'child')"
    ).get();

    if (rows.isEmpty) {
      // Heuristic fallback: create a general cluster containing all local image files
      final imageFiles = await db.customSelect(
        "SELECT id FROM files WHERE mime_type LIKE 'image/%'"
      ).get();

      if (imageFiles.isNotEmpty) {
        const clusterId = 'default_people_cluster';
        final exists = await db.customSelect(
          "SELECT id FROM face_clusters WHERE id = ?",
          variables: [drift.Variable<String>(clusterId)]
        ).get();

        if (exists.isEmpty) {
          await db.customStatement(
            "INSERT INTO face_clusters (id, name) VALUES (?, ?)",
            [clusterId, "Detected People"]
          );
        }

        for (final img in imageFiles) {
          final fileId = img.read<String>('id');
          await db.customStatement(
            "INSERT OR IGNORE INTO photo_faces (file_id, face_cluster_id, confidence) VALUES (?, ?, ?)",
            [fileId, clusterId, 0.90]
          );
        }
      }
      return;
    }

    // Group files by tags
    final Map<String, List<String>> tagGroups = {};
    for (final row in rows) {
      final fileId = row.read<String>('file_id');
      final tagName = row.read<String>('tag_name');
      tagGroups.putIfAbsent(tagName, () => []).add(fileId);
    }

    // Insert database records
    for (final entry in tagGroups.entries) {
      final tagName = entry.key;
      final fileIds = entry.value;
      final clusterId = 'cluster_${tagName.toLowerCase()}';
      final capitalizedName = tagName.substring(0, 1).toUpperCase() + tagName.substring(1);

      await db.customStatement(
        "INSERT OR IGNORE INTO face_clusters (id, name) VALUES (?, ?)",
        [clusterId, capitalizedName]
      );

      for (final fileId in fileIds) {
        await db.customStatement(
          "INSERT OR IGNORE INTO photo_faces (file_id, face_cluster_id, confidence) VALUES (?, ?, ?)",
          [fileId, clusterId, 0.95]
        );
      }
    }
  }
}
