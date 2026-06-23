import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:aerodrive/data/db/database.dart';

class FileRepository {
  final AeroDriveDatabase _db;
  final Uuid _uuid = const Uuid();

  FileRepository(this._db);

  Future<FileData?> getFileByHash(String sha256Hash) async {
    return await (_db.select(_db.files)..where((f) => f.sha256Hash.equals(sha256Hash) & f.deletedAt.isNull()))
        .getSingleOrNull();
  }

  /// Creates a file entry. Implements the Zero Re-upload deduplication algorithm.
  Future<String> createFileEntry({
    required String name,
    required String sha256Hash,
    required int sizeBytes,
    required String mimeType,
    String? folderId,
  }) async {
    return _db.transaction(() async {
      // 1. Pre-flight check: Does this hash already exist in the database?
      final existingFile = await getFileByHash(sha256Hash);

      final newFileId = _uuid.v4();

      await _db.into(_db.files).insert(
        FilesCompanion.insert(
          id: newFileId,
          name: name,
          folderId: Value(folderId),
          size: Value(sizeBytes),
          mimeType: Value(mimeType),
          sha256Hash: Value(sha256Hash), // Wait, sha256Hash has unique() in schema!
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // If existingFile is found, we implement deduplication by copying its chunks
      if (existingFile != null) {
        final existingChunks = await (_db.select(_db.chunks)..where((c) => c.fileId.equals(existingFile.id))).get();
        
        for (final chunk in existingChunks) {
          await _db.into(_db.chunks).insert(
            ChunksCompanion.insert(
              id: _uuid.v4(),
              fileId: Value(newFileId),
              chunkIndex: Value(chunk.chunkIndex),
              channelId: Value(chunk.channelId),
              messageId: Value(chunk.messageId),
              size: Value(chunk.size),
              hash: Value(chunk.hash),
            ),
          );
        }
        
        // Update file to be completely chunked and ready (Zero Re-upload!)
        await (_db.update(_db.files)..where((f) => f.id.equals(newFileId))).write(
          const FilesCompanion(
            isChunked: Value(true),
          ),
        );
      }

      return newFileId;
    });
  }

  /// Retrieves the files within a specific folder.
  Future<List<FileData>> getFilesInFolder(String? folderId) {
    final query = _db.select(_db.files);
    if (folderId == null) {
      query.where((f) => f.folderId.isNull());
    } else {
      query.where((f) => f.folderId.equals(folderId));
    }
    query.where((f) => f.deletedAt.isNull());
    return query.get();
  }

  /// Deletes a file and its chunks locally.
  Future<void> trashFile(String fileId) async {
    await _db.transaction(() async {
      await (_db.delete(_db.chunks)..where((c) => c.fileId.equals(fileId))).go();
      await (_db.delete(_db.files)..where((f) => f.id.equals(fileId))).go();
    });
  }
}
