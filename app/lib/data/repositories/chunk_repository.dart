import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../db/database.dart';

class ChunkRepository {

  ChunkRepository(this._db);
  final AeroDriveDatabase _db;
  final Uuid _uuid = const Uuid();

  /// Inserts a chunk record for a file.
  Future<String> insertChunk({
    required String fileId,
    required int chunkIndex,
    required int channelId,
    required int messageId,
    required int sizeBytes,
    required String hash,
  }) async {
    final id = _uuid.v4();
    await _db.into(_db.chunks).insert(
      ChunksCompanion.insert(
        id: id,
        fileId: Value(fileId),
        chunkIndex: Value(chunkIndex),
        channelId: Value(channelId),
        messageId: Value(messageId),
        size: Value(sizeBytes),
        hash: Value(hash),
      ),
    );
    return id;
  }

  /// Retrieves all chunks for a given file
  Future<List<ChunkData>> getChunksForFile(String fileId) => (_db.select(_db.chunks)
          ..where((c) => c.fileId.equals(fileId))
          ..orderBy([(c) => OrderingTerm(expression: c.chunkIndex)]))
        .get();

  /// Updates a specific chunk's message ID if it was re-uploaded or modified.
  Future<void> updateChunkMessageId(String chunkId, int newMessageId) async {
    await (_db.update(_db.chunks)..where((c) => c.id.equals(chunkId))).write(
      ChunksCompanion(
        messageId: Value(newMessageId),
      ),
    );
  }
}
