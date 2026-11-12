import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/logger.dart';
import '../core/providers.dart';
import '../core/providers/repository_providers.dart';
import '../core/providers/security_providers.dart';
import '../data/db/database.dart';
import '../features/drive/providers/drive_providers.dart';
import '../features/telegram/telegram_manager.dart';
import '../features/telegram/telegram_service.dart';
import 'channel_load_balancer.dart';
import 'recovery/manifest_encoder.dart';
import 'sync/config_sync_service.dart';
import 'sync/realtime_sync_service.dart';

final driveOperationsServiceProvider = Provider<DriveOperationsService>((ref) {
  return DriveOperationsService(ref);
});

class DriveOperationsService {
  DriveOperationsService(this._ref);
  final Ref _ref;

  /// Tracks in-flight asynchronous folder creation / upload tasks to prevent
  /// rename or move races before the initial creation finishes.
  static final Map<String, Future<void>> inFlightFolderOps = {};

  /// Tombstones for old folder names / paths: key is "parentId/oldName" (or "ROOT/oldName"),
  /// value is the new folderId or target name, preventing ghost resurrection from TDLib cloud scans.
  static final Map<String, String> renamedFolderTombstones = {};

  static void recordFolderTombstone({String? parentId, required String oldName, required String newFolderId}) {
    final key = '${parentId ?? 'ROOT'}/${oldName.trim().toLowerCase()}';
    renamedFolderTombstones[key] = newFolderId;
    AppLogger.info('DriveOperationsService: Recorded folder tombstone $key -> $newFolderId');
  }

  static bool isFolderTombstoned({String? parentId, required String name}) {
    final key = '${parentId ?? 'ROOT'}/${name.trim().toLowerCase()}';
    return renamedFolderTombstones.containsKey(key);
  }

  static void loadTombstones(Map<String, String> tombstones) {
    renamedFolderTombstones.addAll(tombstones);
  }

  /// Renames a folder in the local database and persists the new name to Telegram.
  Future<bool> renameFolder(String folderId, String newName) async {
    final cleanName = newName.trim();
    if (cleanName.isEmpty) return false;

    // Await any pending in-flight creation to guarantee Telegram manifest ordering
    if (inFlightFolderOps.containsKey(folderId)) {
      try {
        await inFlightFolderOps[folderId];
      } catch (e) {
        AppLogger.warning('DriveOperationsService: inFlightFolderOp for $folderId failed: $e');
      }
    }

    final db = _ref.read(databaseProvider);
    final folder = await (db.select(db.folders)..where((f) => f.id.equals(folderId))).getSingleOrNull();
    if (folder == null) return false;

    if (folder.name == cleanName) return true;

    // Record tombstone for old folder name under this parent
    recordFolderTombstone(parentId: folder.parentId, oldName: folder.name, newFolderId: folderId);

    // 1. Immediate SQLite & In-Memory Update
    final now = DateTime.now();
    await (db.update(db.folders)..where((f) => f.id.equals(folderId))).write(
      FoldersCompanion(
        name: drift.Value(cleanName),
        updatedAt: drift.Value(now),
      ),
    );

    // 2. Lock against background sync overwrite
    RealtimeSyncService.recordRecentRename(folderId);

    // 3. Update active Inspector state if this folder is currently open
    final currentSelected = _ref.read(selectedFolderForInspectorProvider);
    if (currentSelected != null && currentSelected.id == folderId) {
      _ref.read(selectedFolderForInspectorProvider.notifier).state =
          currentSelected.copyWith(name: cleanName, updatedAt: drift.Value(now));
    }

    // 4. Invalidate UI lists
    _ref.read(dbRebuildVersionProvider.notifier).update((v) => v + 1);
    _ref.invalidate(folderContentsProvider);

    // 5. Background Cloud Manifest Sync to Telegram
    unawaited(_syncFolderManifestToTelegram(folderId, cleanName, folder.parentId));

    // 6. Sync updated tombstones and state to remote config channel
    unawaited(_ref.read(configSyncServiceProvider).syncConfigToChannel());

    AppLogger.info('DriveOperationsService: Renamed folder $folderId to "$cleanName"');
    return true;
  }

  /// Renames a file in the local database and persists the new name to Telegram.
  Future<bool> renameFile(String fileId, String newName) async {
    final cleanName = newName.trim();
    if (cleanName.isEmpty) return false;

    final db = _ref.read(databaseProvider);
    final file = await (db.select(db.files)..where((f) => f.id.equals(fileId))).getSingleOrNull();
    if (file == null) return false;

    if (file.name == cleanName) return true;

    // 1. Immediate SQLite & In-Memory Update
    final now = DateTime.now();
    await (db.update(db.files)..where((f) => f.id.equals(fileId))).write(
      FilesCompanion(
        name: drift.Value(cleanName),
        updatedAt: drift.Value(now),
      ),
    );

    // 2. Lock against background sync overwrite
    RealtimeSyncService.recordRecentRename(fileId);

    // 3. Update active Inspector state if this file is currently open
    final currentSelected = _ref.read(selectedFileForInspectorProvider);
    if (currentSelected != null && currentSelected.id == fileId) {
      _ref.read(selectedFileForInspectorProvider.notifier).state =
          currentSelected.copyWith(name: cleanName, updatedAt: drift.Value(now));
    }

    // 4. Invalidate UI lists
    _ref.read(dbRebuildVersionProvider.notifier).update((v) => v + 1);
    _ref.invalidate(folderContentsProvider);

    // 5. Background Cloud Manifest Sync to Telegram
    unawaited(_syncFileManifestToTelegram(fileId, cleanName, file.folderId));

    AppLogger.info('DriveOperationsService: Renamed file $fileId to "$cleanName"');
    return true;
  }

  /// Moves and optionally renames a folder (used by WebDAV MOVE across folders).
  Future<bool> moveFolder(String folderId, String? newParentId, {String? newName}) async {
    if (inFlightFolderOps.containsKey(folderId)) {
      try {
        await inFlightFolderOps[folderId];
      } catch (e) {
        AppLogger.warning('DriveOperationsService: inFlightFolderOp for $folderId failed: $e');
      }
    }

    final db = _ref.read(databaseProvider);
    final folder = await (db.select(db.folders)..where((f) => f.id.equals(folderId))).getSingleOrNull();
    if (folder == null) return false;

    final effectiveName = newName?.trim().isNotEmpty == true ? newName!.trim() : folder.name;
    final now = DateTime.now();

    // Record tombstone for old folder location
    recordFolderTombstone(parentId: folder.parentId, oldName: folder.name, newFolderId: folderId);

    await (db.update(db.folders)..where((f) => f.id.equals(folderId))).write(
      FoldersCompanion(
        name: drift.Value(effectiveName),
        parentId: drift.Value(newParentId),
        updatedAt: drift.Value(now),
      ),
    );

    RealtimeSyncService.recordRecentRename(folderId);

    final currentSelected = _ref.read(selectedFolderForInspectorProvider);
    if (currentSelected != null && currentSelected.id == folderId) {
      _ref.read(selectedFolderForInspectorProvider.notifier).state =
          currentSelected.copyWith(name: effectiveName, parentId: drift.Value(newParentId), updatedAt: drift.Value(now));
    }

    _ref.read(dbRebuildVersionProvider.notifier).update((v) => v + 1);
    _ref.invalidate(folderContentsProvider);

    unawaited(_syncFolderManifestToTelegram(folderId, effectiveName, newParentId));
    unawaited(_ref.read(configSyncServiceProvider).syncConfigToChannel());
    return true;
  }

  /// Moves and optionally renames a file (used by WebDAV MOVE across folders).
  Future<bool> moveFile(String fileId, String? newFolderId, {String? newName}) async {
    final db = _ref.read(databaseProvider);
    final file = await (db.select(db.files)..where((f) => f.id.equals(fileId))).getSingleOrNull();
    if (file == null) return false;

    final effectiveName = newName?.trim().isNotEmpty == true ? newName!.trim() : file.name;
    final now = DateTime.now();

    await (db.update(db.files)..where((f) => f.id.equals(fileId))).write(
      FilesCompanion(
        name: drift.Value(effectiveName),
        folderId: drift.Value(newFolderId),
        updatedAt: drift.Value(now),
      ),
    );

    RealtimeSyncService.recordRecentRename(fileId);

    final currentSelected = _ref.read(selectedFileForInspectorProvider);
    if (currentSelected != null && currentSelected.id == fileId) {
      _ref.read(selectedFileForInspectorProvider.notifier).state =
          currentSelected.copyWith(name: effectiveName, folderId: drift.Value(newFolderId), updatedAt: drift.Value(now));
    }

    _ref.read(dbRebuildVersionProvider.notifier).update((v) => v + 1);
    _ref.invalidate(folderContentsProvider);

    unawaited(_syncFileManifestToTelegram(fileId, effectiveName, newFolderId));
    return true;
  }

  /// Toggles favorite status of a folder, updating UI immediately and syncing to cloud.
  Future<bool> toggleFolderFavorite(String folderId) async {
    final db = _ref.read(databaseProvider);
    final folder = await (db.select(db.folders)..where((f) => f.id.equals(folderId))).getSingleOrNull();
    if (folder == null) return false;

    final newFav = !folder.isFavorite;
    final now = DateTime.now();

    // 1. Immediate SQLite update
    await (db.update(db.folders)..where((f) => f.id.equals(folderId))).write(
      FoldersCompanion(
        isFavorite: drift.Value(newFav),
        updatedAt: drift.Value(now),
      ),
    );

    // 2. Update Inspector if open
    final currentSelected = _ref.read(selectedFolderForInspectorProvider);
    if (currentSelected != null && currentSelected.id == folderId) {
      _ref.read(selectedFolderForInspectorProvider.notifier).state =
          currentSelected.copyWith(isFavorite: newFav, updatedAt: drift.Value(now));
    }

    // 3. Invalidate UI lists & refresh
    _ref.read(dbRebuildVersionProvider.notifier).update((v) => v + 1);
    _ref.invalidate(folderContentsProvider);

    // 4. Dual cloud sync:
    // Mechanism A: Update Telegram manifest caption
    unawaited(_syncFolderManifestToTelegram(folderId, folder.name, folder.parentId));

    // Mechanism B: Sync centralized config state (favorites, colors, etc.)
    unawaited(_ref.read(configSyncServiceProvider).syncConfigToChannel());

    AppLogger.info('DriveOperationsService: Toggled folder $folderId favorite -> $newFav');
    return newFav;
  }

  /// Toggles favorite status of a file, updating UI immediately and syncing to cloud.
  Future<bool> toggleFileFavorite(String fileId) async {
    final db = _ref.read(databaseProvider);
    final file = await (db.select(db.files)..where((f) => f.id.equals(fileId))).getSingleOrNull();
    if (file == null) return false;

    final newFav = !file.isFavorite;
    final now = DateTime.now();

    // 1. Immediate SQLite update
    await (db.update(db.files)..where((f) => f.id.equals(fileId))).write(
      FilesCompanion(
        isFavorite: drift.Value(newFav),
        updatedAt: drift.Value(now),
      ),
    );

    // 2. Update Inspector if open
    final currentSelected = _ref.read(selectedFileForInspectorProvider);
    if (currentSelected != null && currentSelected.id == fileId) {
      _ref.read(selectedFileForInspectorProvider.notifier).state =
          currentSelected.copyWith(isFavorite: newFav, updatedAt: drift.Value(now));
    }

    // 3. Invalidate UI lists & refresh
    _ref.read(dbRebuildVersionProvider.notifier).update((v) => v + 1);
    _ref.invalidate(folderContentsProvider);

    // 4. Dual cloud sync:
    // Mechanism A: Update Telegram chunk 0 manifest caption
    unawaited(_syncFileManifestToTelegram(fileId, file.name, file.folderId));

    // Mechanism B: Sync centralized config state
    unawaited(_ref.read(configSyncServiceProvider).syncConfigToChannel());

    AppLogger.info('DriveOperationsService: Toggled file $fileId favorite -> $newFav');
    return newFav;
  }

  /// Syncs folder manifest changes to Telegram.
  Future<void> _syncFolderManifestToTelegram(String folderId, String folderName, String? parentFolderId) async {
    try {
      final db = _ref.read(databaseProvider);
      final masterKeyBytes = _ref.read(masterKeyProvider);
      if (masterKeyBytes == null) {
        AppLogger.warning('DriveOperationsService: Cannot sync folder to Telegram, masterKey is null');
        return;
      }

      final cipher = AesGcm.with256bits();
      final secretKey = await cipher.newSecretKeyFromBytes(masterKeyBytes);

      final folder = await (db.select(db.folders)..where((f) => f.id.equals(folderId))).getSingleOrNull();
      final manifestCaption = await ManifestEncoder.encodeFolderManifest(
        folderId: folderId,
        folderName: folderName,
        parentFolderId: parentFolderId,
        masterKey: secretKey,
        color: folder?.color,
        isEncrypted: (folder?.isEncrypted ?? true) ? 1 : 0,
        createdAt: folder?.createdAt,
        isFavorite: (folder?.isFavorite ?? false) ? 1 : 0,
      );

      // Check if we have an existing telegram message ID for this folder
      final manifestRecord = await (db.select(db.manifestMessages)..where((m) => m.id.equals(folderId))).getSingleOrNull();

      bool captionEdited = false;
      if (manifestRecord?.channelId != null && manifestRecord?.telegramMessageId != null) {
        try {
          final telegram = _ref.read(telegramServiceProvider.notifier);
          final res = await telegram.editMessageCaption(
            manifestRecord!.channelId!,
            manifestRecord.telegramMessageId!,
            manifestCaption,
          );
          if (res['@type'] != 'error') {
            captionEdited = true;
            AppLogger.info('DriveOperationsService: Edited Telegram caption for folder $folderId');
          }
        } catch (e) {
          AppLogger.warning('DriveOperationsService: editMessageCaption failed: $e');
        }
      }

      // If caption edit didn't succeed, upload a new manifest document
      if (!captionEdited) {
        final settingsRepo = _ref.read(settingsRepositoryProvider);
        final targetChannel = await ChannelLoadBalancer.selectStorageChannel(settings: settingsRepo);
        if (targetChannel == null) return;
        final chatId = targetChannel['id'] is String ? int.parse(targetChannel['id']) : targetChannel['id'] as int;

        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}${Platform.pathSeparator}folder_$folderId.png');
        final pngBytes = Uint8List.fromList([
          137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 108, 137, 0, 0, 0, 11, 73, 68, 65, 84, 120, 156, 99, 96, 0, 0, 0, 2, 0, 1, 226, 33, 188, 51, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130
        ]);
        await tempFile.writeAsBytes(pngBytes);

        final targetAccountId = targetChannel['accountId']?.toString();
        final accounts = _ref.read(telegramManagerProvider);
        final telegram = (targetAccountId != null && targetAccountId.isNotEmpty)
            ? accounts.firstWhere(
                (c) => c.accountId == targetAccountId,
                orElse: () => _ref.read(telegramServiceProvider.notifier),
              )
            : _ref.read(telegramServiceProvider.notifier);

        // If old manifest message existed, revoke it to prevent ghost resurrection
        if (manifestRecord?.channelId != null && manifestRecord?.telegramMessageId != null) {
          try {
            await telegram.deleteMessages(manifestRecord!.channelId!, [manifestRecord.telegramMessageId!], revoke: true);
          } catch (_) {}
        }

        final sentMsg = await telegram.uploadDocument(chatId, tempFile.path, caption: manifestCaption);
        final msgId = sentMsg['id'] as int?;
        if (msgId != null) {
          await db.into(db.manifestMessages).insertOnConflictUpdate(
            ManifestMessagesCompanion.insert(
              id: folderId,
              channelId: drift.Value(chatId),
              telegramMessageId: drift.Value(msgId),
              manifestVersion: const drift.Value(1),
            ),
          );
        }
        if (await tempFile.exists()) {
          try {
            await tempFile.delete();
          } catch (_) {}
        }
        AppLogger.info('DriveOperationsService: Uploaded new folder manifest for $folderId ($folderName)');
      }
    } catch (e) {
      AppLogger.warning('DriveOperationsService: Failed to sync folder manifest to Telegram: $e');
    }
  }

  /// Syncs file manifest changes to Telegram.
  Future<void> _syncFileManifestToTelegram(String fileId, String fileName, String? parentFolderId) async {
    try {
      final db = _ref.read(databaseProvider);
      final file = await (db.select(db.files)..where((f) => f.id.equals(fileId))).getSingleOrNull();
      if (file == null) return;

      final masterKeyBytes = _ref.read(masterKeyProvider);
      if (masterKeyBytes == null) return;

      final cipher = AesGcm.with256bits();
      final secretKey = await cipher.newSecretKeyFromBytes(masterKeyBytes);

      final chunk0 = await (db.select(db.chunks)
        ..where((c) => c.fileId.equals(fileId) & c.chunkIndex.equals(0))
      ).getSingleOrNull();

      if (chunk0?.channelId != null && chunk0?.messageId != null) {
        final manifestCaption = await ManifestEncoder.encodeFileManifest(
          fileId: fileId,
          fileName: fileName,
          parentFolderId: parentFolderId,
          masterKey: secretKey,
          hash: file.sha256Hash ?? '',
          size: file.size ?? 0,
          mime: file.mimeType ?? 'application/octet-stream',
          isChunked: file.isChunked ? 1 : 0,
          totalChunks: file.totalChunks,
          chunkIndex: 0,
          isEncrypted: file.isEncrypted ? 1 : 0,
          photoTakenAt: file.photoTakenAt,
          duration: file.duration,
          isFavorite: file.isFavorite ? 1 : 0,
        );

        final telegram = _ref.read(telegramServiceProvider.notifier);
        await telegram.editMessageCaption(chunk0!.channelId!, chunk0.messageId!, manifestCaption);
        AppLogger.info('DriveOperationsService: Updated file caption in Telegram for $fileId ($fileName)');
      }
    } catch (e) {
      AppLogger.warning('DriveOperationsService: Failed to sync file manifest to Telegram: $e');
    }
  }
}
