import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/logger.dart';
import '../../core/providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/providers/security_providers.dart';
import '../../data/db/database.dart';
import '../../features/drive/providers/drive_providers.dart';
import '../../features/telegram/telegram_manager.dart';
import '../recovery/manifest_encoder.dart';

final realtimeSyncServiceProvider = Provider<RealtimeSyncService>((ref) {
  final service = RealtimeSyncService(ref);
  ref.onDispose(service.dispose);
  return service;
});

class RealtimeSyncService {

  RealtimeSyncService(this._ref);
  final Ref _ref;
  bool _isListening = false;

  void startListening() {
    if (_isListening) return;
    _isListening = true;

    final telegramAccounts = _ref.read(telegramManagerProvider);
    for (final account in telegramAccounts) {
      account.tdlibEvents.listen((event) {
        if (event['@type'] == 'updateDeleteMessages') {
          _handleDeleteMessages(event);
        } else if (event['@type'] == 'updateNewMessage') {
          _handleNewMessage(event);
        }
      });
    }
  }

  void stopListening() {
    _isListening = false;
  }

  void dispose() {
    stopListening();
  }

  Future<void> _handleDeleteMessages(Map<String, dynamic> event) async {
    try {
      if (event['from_cache'] == true) {
        AppLogger.info('RealtimeSync: Ignoring delete messages event because it is only from cache');
        return;
      }

      final chatId = event['chat_id'] as int?;
      final messageIds = (event['message_ids'] as List<dynamic>?)?.cast<int>();

      if (chatId == null || messageIds == null || messageIds.isEmpty) return;

      final db = _ref.read(databaseProvider);
      
      var dbChanged = false;

      for (final messageId in messageIds) {
        // Find if this message ID belongs to any chunk
        final chunkMatches = await (db.select(db.chunks)
          ..where((c) => c.channelId.equals(chatId) & c.messageId.equals(messageId)))
          .get();

        for (final chunk in chunkMatches) {
          if (chunk.fileId != null) {
            final fileId = chunk.fileId!;
            // Mark file as deleted locally
            final updatedCount = await (db.update(db.files)
              ..where((f) => f.id.equals(fileId) & f.deletedAt.isNull()))
              .write(FilesCompanion(
                deletedAt: drift.Value(DateTime.now()),
                updatedAt: drift.Value(DateTime.now()),
              ));
              
            if (updatedCount > 0) {
              dbChanged = true;
              AppLogger.info('RealtimeSync: Marked file $fileId as deleted (Chunk $messageId deleted remotely)');
            }
          }
        }

        // Find if this message ID belongs to a manifest directly in files table
        final manifestMatches = await (db.select(db.files)
          ..where((f) => f.manifestMessageId.equals(messageId) & f.deletedAt.isNull()))
          .get();

        for (final file in manifestMatches) {
          final updatedCount = await (db.update(db.files)
            ..where((f) => f.id.equals(file.id)))
            .write(FilesCompanion(
              deletedAt: drift.Value(DateTime.now()),
              updatedAt: drift.Value(DateTime.now()),
            ));
            
          if (updatedCount > 0) {
            dbChanged = true;
            AppLogger.info('RealtimeSync: Marked file ${file.id} as deleted (Manifest $messageId deleted remotely)');
          }
        }
        
        // Find if this message ID belongs to manifest_messages table (folder metadata)
        final folderManifests = await (db.select(db.manifestMessages)
          ..where((m) => m.channelId.equals(chatId) & m.telegramMessageId.equals(messageId)))
          .get();
          
        for (final manifest in folderManifests) {
           // We would ideally parse the manifest to see what folder it was,
           // but we can also just run a quick incremental recovery sync if a folder manifest is deleted.
           // For now we just log it. Folder deletion sync is complex without ID mappings.
           AppLogger.info('RealtimeSync: Folder manifest $messageId deleted remotely. Triggering a quick recovery check might be needed.');
        }
      }

      if (dbChanged) {
        _ref.read(dbRebuildVersionProvider.notifier).update((state) => state + 1);
        _ref.invalidate(folderContentsProvider);
      }
    } catch (e, s) {
      AppLogger.error('RealtimeSyncService: Error handling deleted messages', e, s);
    }
  }

  Future<void> _handleNewMessage(Map<String, dynamic> event) async {
    try {
      final msg = event['message'];
      if (msg == null) return;
      
      final chatId = msg['chat_id'] as int?;
      if (chatId == null) return;
      
      // Check if it's one of our storage channels
      final settingsRepo = _ref.read(settingsRepositoryProvider);
      final rawChannels = await settingsRepo.getSetting('storage_channels_list');
      if (rawChannels == null || !rawChannels.contains(chatId.toString())) return;

      String? caption;
      if (msg['content'] != null && msg['content']['caption'] != null) {
        caption = msg['content']['caption']['text'] as String?;
      }
      caption ??= msg['caption'] as String?; // Fallback
      if (caption == null || caption.isEmpty) return;

      final masterKeyBytes = _ref.read(masterKeyProvider);
      if (masterKeyBytes == null) return;
      final masterKey = SecretKey(masterKeyBytes);

      final manifest = await ManifestEncoder.decodeManifest(caption, masterKey);
      if (manifest == null) return;

      final db = _ref.read(databaseProvider);
      const uuid = Uuid();
      var dbChanged = false;

      await db.transaction(() async {
        if (manifest['t'] == 'dir') {
          final folderId = manifest['id'] as String;
          await db.into(db.folders).insertOnConflictUpdate(
            FoldersCompanion.insert(
              id: folderId,
              name: manifest['name'] as String,
              parentId: drift.Value(manifest['pid'] as String?),
              color: drift.Value(manifest['col'] as String?),
              createdAt: drift.Value(DateTime.now()), 
              updatedAt: drift.Value(DateTime.now()),
            ),
          );
          dbChanged = true;
          AppLogger.info('RealtimeSync: Added folder $folderId');
        } else if (manifest['t'] == 'thumb') {
           final thumbFileId = manifest['fid'] as String;
           // Realtime thumbnail download could be slow, skipping for now
           // Let UI fetch it later if needed, or we can queue it.
        } else {
          final fileId = manifest['id'] as String;
          final dekBase64 = manifest['k'] as String?;
          final ctrIvBase64 = manifest['iv'] as String?;
          
          String? wrappedDekString;
          if (dekBase64 != null) {
            if (ctrIvBase64 != null) {
              wrappedDekString = '$dekBase64|$ctrIvBase64';
            } else {
              wrappedDekString = dekBase64;
            }
          }

          final document = msg['content']?['document'];
          final size = manifest['size'] as int? ?? document?['document']?['size'] as int? ?? 0;
          
          await db.into(db.files).insertOnConflictUpdate(
            FilesCompanion.insert(
              id: fileId,
              name: manifest['name'] as String,
              folderId: drift.Value(manifest['pid'] as String?),
              size: drift.Value(size),
              mimeType: drift.Value(manifest['mime'] as String?),
              isEncrypted: drift.Value(manifest['enc'] == 1),
              isChunked: drift.Value(manifest['chk'] == 1),
              sha256Hash: drift.Value(wrappedDekString),
              createdAt: drift.Value(DateTime.now()),
            ),
          );

          await db.into(db.chunks).insertOnConflictUpdate(
            ChunksCompanion.insert(
              id: uuid.v4(),
              fileId: drift.Value(fileId),
              chunkIndex: drift.Value(manifest['c'] as int? ?? 0),
              channelId: drift.Value(chatId),
              messageId: drift.Value(msg['id'] as int?),
              size: drift.Value(size),
            ),
          );
          dbChanged = true;
          AppLogger.info('RealtimeSync: Added/Updated file $fileId');
        }
      });

      if (dbChanged) {
        _ref.read(dbRebuildVersionProvider.notifier).update((state) => state + 1);
        _ref.invalidate(folderContentsProvider);
      }
    } catch (e, s) {
      AppLogger.error('RealtimeSyncService: Error handling new message', e, s);
    }
  }
}
