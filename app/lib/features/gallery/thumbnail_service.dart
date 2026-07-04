import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../core/logger.dart';
import '../../core/providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/providers/security_providers.dart';
import '../../data/crypto/encryption_engine.dart';
import '../../data/db/database.dart';
import '../../domain/recovery/manifest_encoder.dart';
import '../../domain/thumbnail_cache_manager.dart';
import '../telegram/telegram_manager.dart';
import '../telegram/telegram_service.dart';

class ThumbnailService {

  ThumbnailService(this._ref);
  final Ref _ref;

  /// Retrieves the decrypted temporary thumbnail file path.
  Future<File?> getThumbnail(FileData file) async {
    AppLogger.info('ThumbnailService.getThumbnail: fileId=${file.id} mimeType=${file.mimeType}');
    if (file.mimeType == null || (!file.mimeType!.startsWith('image/') && !file.mimeType!.startsWith('video/'))) {
      AppLogger.info('ThumbnailService.getThumbnail: Skipping non-media file ${file.id} (mime=${file.mimeType})');
      return null;
    }

    final db = _ref.read(databaseProvider);
    final masterKeyBytes = _ref.read(masterKeyProvider);
    if (masterKeyBytes == null) {
      AppLogger.warning('ThumbnailService.getThumbnail: Vault locked, cannot decrypt thumbnails');
      return null;
    }

    final cipher = AesGcm.with256bits();
    final masterKey = await cipher.newSecretKeyFromBytes(masterKeyBytes);

    final tempDir = await getTemporaryDirectory();
    final tempDecryptedFile = File('${tempDir.path}/temp_thumb_${file.id}.jpg');

    // 1. Check if encrypted thumbnail already exists in local cache
    AppLogger.info('ThumbnailService.getThumbnail: Checking local cache for ${file.id}');
    final decryptedBytes = await ThumbnailCacheManager.readThumbnail(
      fileId: file.id,
      masterKey: masterKey,
    );

    if (decryptedBytes != null) {
      AppLogger.info('ThumbnailService.getThumbnail: Local cache HIT for ${file.id}');
      await tempDecryptedFile.parent.create(recursive: true);
      await tempDecryptedFile.writeAsBytes(decryptedBytes);
      
      await (db.update(db.files)..where((f) => f.id.equals(file.id))).write(
        FilesCompanion(
          thumbnailLastAccess: drift.Value(DateTime.now()),
        ),
      );
      return tempDecryptedFile;
    }
    AppLogger.info('ThumbnailService.getThumbnail: Local cache MISS for ${file.id}');

    // 2. Cache miss: try fetching thumbnail from Telegram storage channel
    AppLogger.info('ThumbnailService.getThumbnail: Fetching from Telegram for ${file.id}');
    final telegramThumb = await _fetchThumbnailFromTelegram(file, masterKey, tempDecryptedFile);
    if (telegramThumb != null) {
      AppLogger.info('ThumbnailService.getThumbnail: Telegram fetch SUCCESS for ${file.id}');
      return telegramThumb;
    }
    AppLogger.info('ThumbnailService.getThumbnail: Telegram fetch FAILED for ${file.id}, trying fallback generation');

    // 3. Fallback: generate thumbnail from source file via Telegram
    return _generateAndCacheThumbnail(file, tempDecryptedFile, masterKey);
  }

  /// Scans storage channels for a thumbnail message with `t: "thumb"` caption
  /// for the given file. If found, downloads the encrypted thumbnail, decrypts
  /// it with the Master Key, caches it locally, and returns the temp file.
  Future<File?> _fetchThumbnailFromTelegram(FileData file, SecretKey masterKey, File tempDecryptedFile) async {
    AppLogger.info('_fetchThumbnailFromTelegram: Scanning channels for thumbnail of fileId=${file.id}');
    try {
      final settingsRepo = _ref.read(settingsRepositoryProvider);
      final manager = _ref.read(telegramManagerProvider.notifier);
      final savedChannelsJson = await settingsRepo.getSetting('storage_channels_list');
      if (savedChannelsJson == null || savedChannelsJson.isEmpty) {
        AppLogger.warning('_fetchThumbnailFromTelegram: No storage channels configured');
        return null;
      }

      final List<dynamic> decoded = jsonDecode(savedChannelsJson);
      if (decoded.isEmpty) return null;

      // Scan each channel for thumbnail messages
      for (final ch in decoded) {
        final channelId = ch['id'] is String ? int.parse(ch['id']) : ch['id'] as int;
        final accountId = ch['accountId'] ?? 'primary';
        final telegram = manager.getClient(accountId);
        if (telegram.authState != TelegramAuthState.ready) {
          AppLogger.info('_fetchThumbnailFromTelegram: Account $accountId not ready, skipping');
          continue;
        }

        AppLogger.info('_fetchThumbnailFromTelegram: Scanning channel $channelId (account=$accountId)');
        try {
          // Search for recent messages with our file's thumbnail caption
          final response = await telegram.sendRequest({
            "@type": "getChatHistory",
            "chat_id": channelId,
            "from_message_id": 0,
            "offset": 0,
            "limit": 200,
            "only_local": false,
          });

          final List<dynamic>? messages = response['messages'];
          if (messages == null || messages.isEmpty) {
            AppLogger.info('_fetchThumbnailFromTelegram: No messages in channel $channelId');
            continue;
          }

          AppLogger.info('_fetchThumbnailFromTelegram: Scanning ${messages.length} messages in channel $channelId');
          for (final msg in messages) {
            String? captionText;
            final content = msg['content'];
            if (content != null && content['caption'] != null) {
              captionText = content['caption']['text'] as String?;
            }
            if (captionText == null || captionText.isEmpty) continue;

            // Try to decrypt and parse the caption
            final manifest = await ManifestEncoder.decodeManifest(captionText, masterKey);
            if (manifest == null) continue;
            if (manifest['t'] != 'thumb') continue;
            if (manifest['fid'] != file.id) continue;

            // Found the thumbnail message!
            AppLogger.info('_fetchThumbnailFromTelegram: Found thumbnail message for ${file.id} in channel $channelId');
            final document = content['document'];
            if (document == null) {
              AppLogger.warning('_fetchThumbnailFromTelegram: No document in thumbnail message');
              continue;
            }

            final thumbFileObj = document['document'];
            if (thumbFileObj == null) {
              AppLogger.warning('_fetchThumbnailFromTelegram: No document.file in thumbnail message');
              continue;
            }

            final remoteFileId = thumbFileObj['id'] as int;
            AppLogger.info('_fetchThumbnailFromTelegram: Downloading thumbnail file $remoteFileId');
            final downloadedPath = await _downloadFile(telegram, remoteFileId);
            if (downloadedPath == null) {
              AppLogger.warning('_fetchThumbnailFromTelegram: Download failed for file $remoteFileId');
              continue;
            }

            final encryptedBytes = await File(downloadedPath).readAsBytes();
            if (encryptedBytes.length < 28) {
              AppLogger.warning('_fetchThumbnailFromTelegram: Encrypted thumbnail too small');
              continue;
            }

            final nonce = encryptedBytes.sublist(0, 12);
            final cipherTextAndMac = encryptedBytes.sublist(12);
            final macBytes = cipherTextAndMac.sublist(cipherTextAndMac.length - 16);
            final cipherText = cipherTextAndMac.sublist(0, cipherTextAndMac.length - 16);

            final cipher = AesGcm.with256bits();
            List<int> decryptedBytes;
            try {
              decryptedBytes = await cipher.decrypt(
                SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
                secretKey: masterKey,
              );
            } catch (e) {
              AppLogger.error('_fetchThumbnailFromTelegram: Thumbnail decryption failed for ${file.id}', e);
              continue;
            }

            AppLogger.info('_fetchThumbnailFromTelegram: Decrypted thumbnail ${decryptedBytes.length} bytes for ${file.id}');

            // Cache locally
            await ThumbnailCacheManager.saveThumbnail(
              fileId: file.id,
              plaintextBytes: Uint8List.fromList(decryptedBytes),
              masterKey: masterKey,
            );

            await tempDecryptedFile.parent.create(recursive: true);
            await tempDecryptedFile.writeAsBytes(decryptedBytes);

            final db = _ref.read(databaseProvider);
            await (db.update(db.files)..where((f) => f.id.equals(file.id))).write(
              FilesCompanion(
                thumbnailPath: drift.Value(tempDecryptedFile.path),
                thumbnailSize: drift.Value(decryptedBytes.length),
                thumbnailLastAccess: drift.Value(DateTime.now()),
              ),
            );

            AppLogger.info('_fetchThumbnailFromTelegram SUCCESS for ${file.id}');
            return tempDecryptedFile;
          }
        } catch (e) {
          AppLogger.error('Error scanning channel $channelId for thumbnail', e);
          continue;
        }
      }
    } catch (e, s) {
      AppLogger.error('_fetchThumbnailFromTelegram failed', e, s);
    }
    AppLogger.warning('_fetchThumbnailFromTelegram: No thumbnail found for ${file.id}');
    return null;
  }

  Future<File?> _generateAndCacheThumbnail(FileData file, File tempDecryptedFile, SecretKey masterKey) async {
    try {
      final db = _ref.read(databaseProvider);
      final masterKeyBytes = await masterKey.extractBytes();

      // Get the first chunk to decrypt the image
      final dbChunk = await (db.select(db.chunks)..where((c) => c.fileId.equals(file.id))..orderBy([(t) => drift.OrderingTerm.asc(t.chunkIndex)])).getSingleOrNull();
      if (dbChunk == null || dbChunk.messageId == null || dbChunk.channelId == null) {
        AppLogger.warning('_generateAndCacheThumbnail: No chunks found for file ${file.id}');
        return null;
      }

      final telegram = _ref.read(telegramServiceProvider.notifier);
      final message = await telegram.getMessage(dbChunk.channelId!, dbChunk.messageId!);
      
      final content = message['content'];
      if (content == null || content['@type'] != 'messageDocument') {
        AppLogger.warning('_generateAndCacheThumbnail: Message is not a document for file ${file.id}');
        return null;
      }
      
      final remoteFileId = content['document']['document']['id'];
      
      // Download the file from TDLib
      final downloadedPath = await _downloadFile(telegram, remoteFileId);
      if (downloadedPath == null) {
        AppLogger.warning('_generateAndCacheThumbnail: Failed to download file for ${file.id}');
        return null;
      }

      final engine = EncryptionEngine();
      final dekResult = await engine.unwrapDek(file.sha256Hash!, masterKeyBytes);
      final dekBytes = dekResult[0]!;
      final ctrIv = dekResult[1];

      final encryptedBytes = await File(downloadedPath).readAsBytes();

      final isCtr = file.encryptionAlgo == 'AES-256-CTR';
      final maxRead = isCtr
          ? (4 * 1024 * 1024)
          : (4 * 1024 * 1024) + 28;

      final chunkData = encryptedBytes.length > maxRead
          ? encryptedBytes.sublist(0, maxRead)
          : encryptedBytes;

      List<int> decryptedBytes;
      if (isCtr) {
        decryptedBytes = await engine.decryptBytes(
          data: chunkData,
          dekBytes: dekBytes,
          ctrIv: ctrIv,
        );
      } else {
        final nonce = chunkData.sublist(0, 12);
        final macBytes = chunkData.sublist(12, 28);
        final cipherText = chunkData.sublist(28);

        final cipher = AesGcm.with256bits();
        final dekSecretKey = await cipher.newSecretKeyFromBytes(dekBytes);
        decryptedBytes = await cipher.decrypt(
          SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
          secretKey: dekSecretKey,
        );
      }

      // Generate Thumbnail
      final image = img.decodeImage(Uint8List.fromList(decryptedBytes));
      if (image == null) {
        AppLogger.warning('_generateAndCacheThumbnail: img.decodeImage returned null for ${file.id} (likely unsupported format)');
        return null;
      }

      final thumbnail = img.copyResize(image, width: 256);
      final thumbnailJpgBytes = Uint8List.fromList(img.encodeJpg(thumbnail, quality: 70));
      AppLogger.info('_generateAndCacheThumbnail: Generated thumbnail ${thumbnailJpgBytes.length} bytes for ${file.id}');

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

      AppLogger.info('_generateAndCacheThumbnail SUCCESS for ${file.id}');
      return tempDecryptedFile;
    } catch (e, s) {
      AppLogger.error('_generateAndCacheThumbnail failed for ${file.id}', e, s);
      return null;
    }
  }

  Future<String?> _downloadFile(TelegramService telegram, int remoteFileId) async {
    await telegram.downloadFile(remoteFileId);
    // Poll until downloaded
    for (var i = 0; i < 50; i++) {
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

final thumbnailServiceProvider = Provider<ThumbnailService>(ThumbnailService.new);

