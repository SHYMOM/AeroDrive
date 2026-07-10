import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:workmanager/workmanager.dart';

import '../core/logger.dart';
import '../data/db/database.dart';

// Payload for messages to delete from TDLib
class ExpiredMessagesPayload {

  ExpiredMessagesPayload(this.chunksToDelete, this.fileIdsToPurge, this.folderIdsToPurge);
  final List<ChunkData> chunksToDelete;
  final List<String> fileIdsToPurge;
  final List<String> folderIdsToPurge;
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
    return Isolate.run(() async {
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

  /// Deletes Telegram messages for the given chunks using the telegram service.
  /// This ensures .tmp files are cleaned up on Telegram's side.
  static Future<void> deleteTelegramMessages(List<ChunkData> chunks, dynamic telegramService) async {
    for (final chunk in chunks) {
      if (chunk.channelId == null || chunk.messageId == null) continue;
      try {
        await telegramService.sendRequest({
          "@type": "deleteMessages",
          "chat_id": chunk.channelId,
          "message_ids": [chunk.messageId],
          "revoke": true,
        });
        await Future.delayed(const Duration(milliseconds: 100)); // Rate limiting
      } catch (e) {
        AppLogger.warning('Failed to delete Telegram message for chunk ${chunk.id}: $e');
      }
    }
  }

  /// Completes the purge by removing the rows from SQLite ONLY AFTER TDLib has successfully deleted the messages.
  static Future<void> completeHardDelete(AeroDriveDatabase db, ExpiredMessagesPayload payload) async {
    await db.transaction(() async {
      // Delete chunks and other relations first to satisfy foreign key constraints
      if (payload.fileIdsToPurge.isNotEmpty) {
        await (db.delete(db.chunks)..where((c) => c.fileId.isIn(payload.fileIdsToPurge))).go();
        await (db.delete(db.thumbnails)..where((t) => t.fileId.isIn(payload.fileIdsToPurge))).go();
        await (db.delete(db.fileTags)..where((ft) => ft.fileId.isIn(payload.fileIdsToPurge))).go();
        await (db.delete(db.photoFaces)..where((pf) => pf.fileId.isIn(payload.fileIdsToPurge))).go();
        await (db.delete(db.filePlaces)..where((fp) => fp.fileId.isIn(payload.fileIdsToPurge))).go();
        await (db.delete(db.shareLinks)..where((sl) => sl.fileId.isIn(payload.fileIdsToPurge))).go();
        // Delete files
        await (db.delete(db.files)..where((f) => f.id.isIn(payload.fileIdsToPurge))).go();
      }

      // Delete folders
      if (payload.folderIdsToPurge.isNotEmpty) {
        // Delete share links pointing to folders being purged first
        await (db.delete(db.shareLinks)..where((sl) => sl.folderId.isIn(payload.folderIdsToPurge))).go();
        await (db.delete(db.folders)..where((f) => f.id.isIn(payload.folderIdsToPurge))).go();
      }
    });
  }
}
