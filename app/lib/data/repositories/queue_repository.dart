import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:aerodrive/data/db/database.dart';

class QueueRepository {
  final AeroDriveDatabase _db;
  final Uuid _uuid = const Uuid();

  QueueRepository(this._db);

  /// Enqueues a file for upload.
  Future<String> enqueueUpload(String filePath, {int priority = 0}) async {
    final id = _uuid.v4();
    await _db.into(_db.transferQueue).insert(
      TransferQueueCompanion.insert(
        id: id,
        type: const Value('UPLOAD'),
        status: const Value('PENDING'),
        priority: Value(priority),
        createdAt: Value(DateTime.now()),
      ),
    );
    return id;
  }

  /// Retrieves the next pending task, ordered by priority.
  Future<TransferQueueData?> getNextPendingTask() async {
    return (_db.select(_db.transferQueue)
          ..where((q) => q.status.equals('PENDING'))
          ..orderBy([
            (q) => OrderingTerm(expression: q.priority, mode: OrderingMode.desc),
            (q) => OrderingTerm(expression: q.createdAt, mode: OrderingMode.asc),
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Updates the status of a queue item.
  Future<void> updateStatus(String id, String status, {String? errorMessage}) async {
    await (_db.update(_db.transferQueue)..where((q) => q.id.equals(id))).write(
      TransferQueueCompanion(
        status: Value(status),
        errorMessage: Value(errorMessage),
      ),
    );
  }

  /// Removes a task from the queue.
  Future<void> removeTask(String id) async {
    await (_db.delete(_db.transferQueue)..where((q) => q.id.equals(id))).go();
  }
}
