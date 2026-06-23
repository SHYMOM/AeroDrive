import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cryptography/cryptography.dart';
import 'package:aerodrive/domain/recovery/manifest_encoder.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:drift/drift.dart' as drift;
import 'package:aerodrive/features/telegram/telegram_service.dart';
import 'package:uuid/uuid.dart';

class RecoveryScanner {
  final AeroDriveDatabase _db;
  final TelegramService _telegramService;

  RecoveryScanner(this._db, this._telegramService);

  /// Scans a Telegram channel's entire history and reconstructs the SQLite database.
  Future<void> runDisasterRecovery({
    required SecretKey masterKey,
    required int channelId,
    // Provide a callback to update UI progress
    Function(int messagesScanned, int itemsRecovered)? onProgress,
  }) async {
    int messagesScanned = 0;
    int itemsRecovered = 0;

    // We will collect the data in memory, then bulk insert to SQLite at the end
    // to prevent disk I/O bottlenecks.
    final List<FoldersCompanion> recoveredFolders = [];
    final List<FilesCompanion> recoveredFiles = [];
    final List<ChunksCompanion> recoveredChunks = [];
    final Uuid uuid = const Uuid();

    int lastMessageId = 0;
    while (true) {
      final response = await _telegramService.sendRequest({
        "@type": "getChatHistory",
        "chat_id": channelId,
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
        if (manifest == null) continue;

        itemsRecovered++;

        if (manifest['t'] == 'dir') {
          // It's a Folder Metadata Message
          recoveredFolders.add(
            FoldersCompanion.insert(
              id: manifest['i'],
              name: manifest['n'],
              parentId: drift.Value(manifest['p']), // Can be null
              createdAt: drift.Value(DateTime.now()), 
              updatedAt: drift.Value(DateTime.now()),
            ),
          );
        } else {
          // It's a File Chunk Message
          final fileId = manifest['i'];
          final dekBase64 = manifest['k'] as String?;
          String? wrappedDekString;
          if (dekBase64 != null) {
            final dekBytes = base64Decode(dekBase64);
            final cipher = AesGcm.with256bits();
            final nonce = cipher.newNonce();
            final secretBox = await cipher.encrypt(
              dekBytes,
              secretKey: masterKey,
              nonce: nonce,
            );
            wrappedDekString = '${base64Encode(secretBox.nonce)}|${base64Encode(secretBox.mac.bytes)}|${base64Encode(secretBox.cipherText)}';
          }
          
          // We only insert the File row once, even if it has multiple chunks
          final existingFile = recoveredFiles.any((f) => f.id.value == fileId);
          if (!existingFile) {
            final document = msg['content']?['document'];
            final size = document?['document']?['size'] as int?;
            recoveredFiles.add(
              FilesCompanion.insert(
                id: fileId,
                name: manifest['n'],
                folderId: drift.Value(manifest['f']),
                size: drift.Value(size),
                isEncrypted: const drift.Value(true),
                sha256Hash: drift.Value(wrappedDekString),
                createdAt: drift.Value(DateTime.now()),
              ),
            );
          }

          // Insert the Chunk
          recoveredChunks.add(
            ChunksCompanion.insert(
              id: uuid.v4(),
              fileId: drift.Value(fileId),
              chunkIndex: drift.Value(0), // Would be in a full chunk manifest
              channelId: drift.Value(channelId),
              messageId: drift.Value(msg['id']),
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

    // After scanning all messages, bulk insert them into Drift
    await _db.transaction(() async {
      if (recoveredFolders.isNotEmpty) {
        await _db.batch((batch) {
          batch.insertAllOnConflictUpdate(_db.folders, recoveredFolders);
        });
      }
      
      if (recoveredFiles.isNotEmpty) {
        await _db.batch((batch) {
          batch.insertAllOnConflictUpdate(_db.files, recoveredFiles);
        });
      }

      if (recoveredChunks.isNotEmpty) {
        await _db.batch((batch) {
          batch.insertAllOnConflictUpdate(_db.chunks, recoveredChunks);
        });
      }
    });

    onProgress?.call(messagesScanned, itemsRecovered);
    debugPrint("Disaster Recovery complete! Recovered $itemsRecovered items.");
  }
}
