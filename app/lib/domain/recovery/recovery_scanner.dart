import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../data/db/database.dart';
import '../../features/telegram/telegram_service.dart';
import '../thumbnail_cache_manager.dart';
import 'manifest_encoder.dart';

class ZeroDBRecoveryService {

  ZeroDBRecoveryService(this._ref, this._db, this._telegramService);
  final Ref _ref;
  final AeroDriveDatabase _db;
  final TelegramService _telegramService;

  /// Scans Telegram storage channels and reconstructs the local SQLite database.
  Future<void> runDisasterRecovery({
    required SecretKey masterKey,
    // Optional fallback channelId if storage_channels_list is empty
    int? channelId,
    Function(int messagesScanned, int itemsRecovered)? onProgress,
  }) async {
    var messagesScanned = 0;
    var itemsRecovered = 0;

    // 1. Resolve channel IDs to scan
    final settingsRepo = _ref.read(settingsRepositoryProvider);
    final savedChannelsJson = await settingsRepo.getSetting('storage_channels_list');
    final Set<int> channelSet = {};

    if (savedChannelsJson != null && savedChannelsJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(savedChannelsJson);
        for (final ch in decoded) {
          final id = ch['id'];
          if (id != null) {
            channelSet.add(id is String ? int.parse(id) : id as int);
          }
        }
      } catch (e) {
        debugPrint('ZeroDBRecovery: failed to parse storage_channels_list: $e');
      }
    }

    // Always include the active channel (if provided) in addition to the list
    if (channelId != null) {
      channelSet.add(channelId);
    }

    final List<int> channelsToScan = channelSet.toList();
    if (channelsToScan.isEmpty) {
      debugPrint("ZeroDBRecovery: No channels configured to scan.");
      return;
    }
    debugPrint('ZeroDBRecovery: scanning channels $channelsToScan');

    final List<FoldersCompanion> recoveredFolders = [];
    final List<FilesCompanion> recoveredFiles = [];
    final List<ChunksCompanion> recoveredChunks = [];
    final Set<String> recoveredFolderIds = {};
    final Set<String> recoveredFileIds = {};
    const uuid = Uuid();

    // 2. Scan each channel
    for (final scanChannelId in channelsToScan) {
      var lastMessageId = 0;
      while (true) {
        final response = await _telegramService.sendRequest({
          "@type": "getChatHistory",
          "chat_id": scanChannelId,
          "from_message_id": lastMessageId,
          "offset": 0,
          "limit": 100,
          "only_local": false,
        });

        final List<dynamic>? messages = response['messages'];
        if (messages == null || messages.isEmpty) {
          break;
        }

        for (final msg in messages) {
          messagesScanned++;
          if (messagesScanned % 10 == 0) {
            onProgress?.call(messagesScanned, itemsRecovered);
          }

          String? caption;
          if (msg['content'] != null && msg['content']['caption'] != null) {
            caption = msg['content']['caption']['text'] as String?;
          }
          caption ??= msg['caption'] as String?; // Fallback

          if (caption == null || caption.isEmpty) continue;

          // Decode caption
          final manifest = await ManifestEncoder.decodeManifest(caption, masterKey);
          if (manifest == null) {
            if (messagesScanned <= 5) {
              debugPrint('ZeroDBRecovery: msg #$messagesScanned caption prefix=${caption.substring(0, caption.length > 40 ? 40 : caption.length)}... — not a valid manifest (wrong key or not a manifest)');
            }
            continue;
          }

          itemsRecovered++;

          if (manifest['t'] == 'dir') {
            final folderId = manifest['id'] as String;
            recoveredFolderIds.add(folderId);
            recoveredFolders.add(
              FoldersCompanion.insert(
                id: folderId,
                name: manifest['name'] as String,
                parentId: drift.Value(manifest['pid'] as String?), // Can be null
                color: drift.Value(manifest['col'] as String?),
                createdAt: drift.Value(DateTime.now()), 
                updatedAt: drift.Value(DateTime.now()),
              ),
            );
          } else if (manifest['t'] == 'thumb') {
            // ── Thumbnail recovery ────────────────────────────────
            final thumbFileId = manifest['fid'] as String;
            try {
              final document = msg['content']?['document'];
              if (document != null) {
                final thumbFileObj = document['document'];
                if (thumbFileObj != null) {
                  final remoteFileId = thumbFileObj['id'] as int;
                  // Download the encrypted thumbnail
                  await _telegramService.downloadFile(remoteFileId);
                  for (var i = 0; i < 30; i++) {
                    final fileInfo = await _telegramService.sendRequest({
                      '@type': 'getFile',
                      'file_id': remoteFileId,
                    });
                    if (fileInfo['local']?['is_downloading_completed'] == true) {
                      final encryptedBytes = await File(fileInfo['local']['path'] as String).readAsBytes();
                      if (encryptedBytes.length >= 28) {
                        final nonce = encryptedBytes.sublist(0, 12);
                        final ct = encryptedBytes.sublist(12, encryptedBytes.length - 16);
                        final mac = encryptedBytes.sublist(encryptedBytes.length - 16);
                        final decrypted = await AesGcm.with256bits().decrypt(
                          SecretBox(ct, nonce: nonce, mac: Mac(mac)),
                          secretKey: masterKey,
                        );
                        await ThumbnailCacheManager.saveThumbnail(
                          fileId: thumbFileId,
                          plaintextBytes: Uint8List.fromList(decrypted),
                          masterKey: masterKey,
                        );
                        debugPrint('Recovery: Thumbnail restored for $thumbFileId');
                      }
                      break;
                    }
                    await Future.delayed(const Duration(milliseconds: 200));
                  }
                }
              }
            } catch (e) {
              debugPrint('Recovery: Failed to restore thumbnail for $thumbFileId: $e');
            }
          } else {
            final fileId = manifest['id'] as String;
            recoveredFileIds.add(fileId);
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

            final existingFile = recoveredFiles.any((f) => f.id.value == fileId);
            if (!existingFile) {
              final document = msg['content']?['document'];
              final size = manifest['size'] as int? ?? document?['document']?['size'] as int? ?? 0;
              recoveredFiles.add(
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
            }

            recoveredChunks.add(
              ChunksCompanion.insert(
                id: uuid.v4(),
                fileId: drift.Value(fileId),
                chunkIndex: drift.Value(manifest['c'] as int? ?? 0),
                channelId: drift.Value(scanChannelId),
                messageId: drift.Value(msg['id'] as int?),
                size: drift.Value(msg['content']?['document']?['document']?['size'] as int?),
              ),
            );
          }
        }

        final nextLastMessageId = messages.last['id'] as int;
        if (nextLastMessageId == lastMessageId) {
          break; // Prevent infinite loop
        }
        lastMessageId = nextLastMessageId;
      }
    }

    // 3. Update database in transaction
    await _db.transaction(() async {
      // Upsert Folders
      if (recoveredFolders.isNotEmpty) {
        await _db.batch((batch) {
          batch.insertAllOnConflictUpdate(_db.folders, recoveredFolders);
        });
      }
      
      // Upsert Files
      if (recoveredFiles.isNotEmpty) {
        await _db.batch((batch) {
          batch.insertAllOnConflictUpdate(_db.files, recoveredFiles);
        });
      }

      // Re-insert Chunks
      if (recoveredChunks.isNotEmpty) {
        final List<String> fileIdsToClear = recoveredChunks.map((c) => c.fileId.value!).toSet().toList();
        for (final fid in fileIdsToClear) {
          await (_db.delete(_db.chunks)..where((c) => c.fileId.equals(fid))).go();
        }
        await _db.batch((batch) {
          batch.insertAllOnConflictUpdate(_db.chunks, recoveredChunks);
        });
      }

      // 4. Prune database records not found in Telegram (handling deletions)
      final allFiles = await _db.select(_db.files).get();
      for (final f in allFiles) {
        if (!recoveredFileIds.contains(f.id)) {
          // Delete chunks and file
          await (_db.delete(_db.chunks)..where((c) => c.fileId.equals(f.id))).go();
          await (_db.delete(_db.files)..where((file) => file.id.equals(f.id))).go();
        }
      }

      final allFolders = await _db.select(_db.folders).get();
      for (final f in allFolders) {
        if (!recoveredFolderIds.contains(f.id)) {
          await (_db.delete(_db.folders)..where((folder) => folder.id.equals(f.id))).go();
        }
      }
    });

    onProgress?.call(messagesScanned, itemsRecovered);
    debugPrint("ZeroDB disaster recovery scan complete! Recovered $itemsRecovered items.");
  }
}

// Retain alias for UI/GoRouter compatibility
typedef RecoveryScanner = ZeroDBRecoveryService;

final recoveryServiceProvider = Provider<ZeroDBRecoveryService>((ref) {
  final db = ref.read(databaseProvider);
  final telegram = ref.read(telegramServiceProvider.notifier);
  return ZeroDBRecoveryService(ref, db, telegram);
});
