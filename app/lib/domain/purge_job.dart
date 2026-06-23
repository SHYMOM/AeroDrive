import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Payload for messages to delete from TDLib
class ExpiredMessagesPayload {
  final List<ChunkData> chunksToDelete;
  final List<String> fileIdsToPurge;
  final List<String> folderIdsToPurge;

  ExpiredMessagesPayload(this.chunksToDelete, this.fileIdsToPurge, this.folderIdsToPurge);
}

class PurgeJob {
  static const String purgeTaskName = "aero_drive_daily_purge";

  /// Registers the daily OS background task using workmanager
  static void registerDailyBackgroundPurge() {
    Workmanager().registerPeriodicTask(
      "purge-task-id",
      purgeTaskName,
      frequency: const Duration(hours: 24),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }

  /// Finds items older than 30 days in an Isolate, returns the chunks to delete,
  /// and then the caller must pass those chunks to TDLib before hard-deleting the rows.
  static Future<ExpiredMessagesPayload> findExpiredItems(AeroDriveDatabase db) async {
    // Isolate.run to prevent UI lag on massive DBs
    return await Isolate.run(() async {
      final now = DateTime.now();
      final threshold = now.subtract(const Duration(days: 30));

      // 1. Find expired files
      final expiredFiles = await (db.select(db.files)
        ..where((f) => f.deletedAt.isNotNull() & f.deletedAt.isSmallerThanValue(threshold)))
        .get();

      final fileIds = expiredFiles.map((f) => f.id).toList();

      List<ChunkData> expiredChunks = [];
      if (fileIds.isNotEmpty) {
        // 2. Find their chunks
        expiredChunks = await (db.select(db.chunks)..where((c) => c.fileId.isIn(fileIds))).get();
      }

      // 3. Find expired folders
      final expiredFolders = await (db.select(db.folders)
        ..where((f) => f.deletedAt.isNotNull() & f.deletedAt.isSmallerThanValue(threshold)))
        .get();
        
      final folderIds = expiredFolders.map((f) => f.id).toList();

      return ExpiredMessagesPayload(expiredChunks, fileIds, folderIds);
    });
  }

  /// Completes the purge by removing the rows from SQLite ONLY AFTER TDLib has successfully deleted the messages.
  static Future<void> completeHardDelete(AeroDriveDatabase db, ExpiredMessagesPayload payload) async {
    await db.transaction(() async {
      // Delete chunks
      if (payload.fileIdsToPurge.isNotEmpty) {
        await (db.delete(db.chunks)..where((c) => c.fileId.isIn(payload.fileIdsToPurge))).go();
        // Delete files
        await (db.delete(db.files)..where((f) => f.id.isIn(payload.fileIdsToPurge))).go();
      }
      
      // Delete folders
      if (payload.folderIdsToPurge.isNotEmpty) {
        await (db.delete(db.folders)..where((f) => f.id.isIn(payload.folderIdsToPurge))).go();
      }
    });
  }
}
