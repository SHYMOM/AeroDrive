import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' as drift;
import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/core/providers/security_providers.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/features/telegram/telegram_service.dart';
import 'package:aerodrive/domain/thumbnail_cache_manager.dart';

class ThumbnailService {
  final Ref _ref;

  ThumbnailService(this._ref);

  /// Retrieves the decrypted temporary thumbnail file path.
  Future<File?> getThumbnail(FileData file) async {
    if (file.mimeType == null || !file.mimeType!.startsWith('image/')) {
      return null; // For now, only generate thumbnails for images
    }

    final db = _ref.read(databaseProvider);
    final masterKeyBytes = _ref.read(masterKeyProvider);
    if (masterKeyBytes == null) return null;

    final cipher = AesGcm.with256bits();
    final masterKey = await cipher.newSecretKeyFromBytes(masterKeyBytes);

    final tempDir = await getTemporaryDirectory();
    final tempDecryptedFile = File('${tempDir.path}/temp_thumb_${file.id}.jpg');

    // 1. Check if encrypted thumbnail already exists in cache
    final decryptedBytes = await ThumbnailCacheManager.readThumbnail(
      fileId: file.id,
      masterKey: masterKey,
    );

    if (decryptedBytes != null) {
      await tempDecryptedFile.parent.create(recursive: true);
      await tempDecryptedFile.writeAsBytes(decryptedBytes);
      
      // Update LRU access timestamp in DB
      await (db.update(db.files)..where((f) => f.id.equals(file.id))).write(
        FilesCompanion(
          thumbnailLastAccess: drift.Value(DateTime.now()),
        ),
      );
      return tempDecryptedFile;
    }

    // 2. Generate thumbnail from source/Telegram
    return _generateAndCacheThumbnail(file, tempDecryptedFile, masterKey);
  }

  Future<File?> _generateAndCacheThumbnail(FileData file, File tempDecryptedFile, SecretKey masterKey) async {
    try {
      final db = _ref.read(databaseProvider);
      
      // Get the first chunk to decrypt the image
      final dbChunk = await (db.select(db.chunks)..where((c) => c.fileId.equals(file.id))..orderBy([(t) => drift.OrderingTerm.asc(t.chunkIndex)])).getSingleOrNull();
      if (dbChunk == null || dbChunk.messageId == null || dbChunk.channelId == null) {
        return null;
      }

      final telegram = _ref.read(telegramServiceProvider.notifier);
      final message = await telegram.getMessage(dbChunk.channelId!, dbChunk.messageId!);
      
      final content = message['content'];
      if (content == null || content['@type'] != 'messageDocument') return null;
      
      final remoteFileId = content['document']['document']['id'];
      
      // Download the file from TDLib
      final downloadedPath = await _downloadFile(telegram, remoteFileId);
      if (downloadedPath == null) return null;

      // Decrypt the file DEK
      final parts = file.sha256Hash!.contains('|') ? file.sha256Hash!.split('|') : file.sha256Hash!.split(':');
      if (parts.length < 3) return null;

      final dekNonce = base64Decode(parts[0]);
      final dekMac = base64Decode(parts[1]);
      final dekCipherText = base64Decode(parts[2]);

      final cipher = AesGcm.with256bits();
      final dekBytes = await cipher.decrypt(
        SecretBox(dekCipherText, nonce: dekNonce, mac: Mac(dekMac)),
        secretKey: masterKey,
      );

      final encryptedBytes = await File(downloadedPath).readAsBytes();

      // Read IV from first 12 bytes
      final iv = encryptedBytes.sublist(0, 12);
      final ciphertext = encryptedBytes.sublist(12, encryptedBytes.length - 16);
      final mac = encryptedBytes.sublist(encryptedBytes.length - 16);

      final dekSecretKey = await cipher.newSecretKeyFromBytes(dekBytes);
      final decryptedBytes = await cipher.decrypt(
        SecretBox(ciphertext, nonce: iv, mac: Mac(mac)),
        secretKey: dekSecretKey,
      );

      // Generate Thumbnail
      final image = img.decodeImage(Uint8List.fromList(decryptedBytes));
      if (image == null) return null;

      final thumbnail = img.copyResize(image, width: 256);
      final thumbnailJpgBytes = Uint8List.fromList(img.encodeJpg(thumbnail, quality: 70));

      // Save encrypted thumbnail persistently to /cache/thumbs/[fileId].enc
      final encryptedPath = await ThumbnailCacheManager.saveThumbnail(
        fileId: file.id,
        plaintextBytes: thumbnailJpgBytes,
        masterKey: masterKey,
      );

      // Write temp unencrypted thumbnail for current UI usage
      await tempDecryptedFile.parent.create(recursive: true);
      await tempDecryptedFile.writeAsBytes(thumbnailJpgBytes);

      final size = thumbnailJpgBytes.length;

      // Update the database record with the encrypted file path, size, and access time
      await (db.update(db.files)..where((f) => f.id.equals(file.id))).write(
        FilesCompanion(
          thumbnailPath: drift.Value(encryptedPath),
          thumbnailSize: drift.Value(size),
          thumbnailLastAccess: drift.Value(DateTime.now()),
        ),
      );

      return tempDecryptedFile;
    } catch (e) {
      // Return null on failure so UI handles it gracefully
      return null;
    }
  }

  Future<String?> _downloadFile(TelegramService telegram, int remoteFileId) async {
    await telegram.downloadFile(remoteFileId);
    // Poll until downloaded
    for (int i = 0; i < 50; i++) {
      final file = await telegram.sendRequest({
        '@type': 'getFile',
        'file_id': remoteFileId,
      });
      if (file['local']['is_downloading_completed'] == true) {
        return file['local']['path'];
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return null;
  }
}

final thumbnailServiceProvider = Provider<ThumbnailService>((ref) {
  return ThumbnailService(ref);
});

