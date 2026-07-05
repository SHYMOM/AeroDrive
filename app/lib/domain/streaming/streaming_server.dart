import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../../core/logger.dart';
import '../../core/providers.dart';
import '../../core/security/master_key_provider.dart';
import '../../data/crypto/encryption_engine.dart';
import '../../data/db/database.dart';
import '../../features/telegram/telegram_service.dart';

class StreamingServer {

  StreamingServer(this.ref);
  final Ref ref;
  HttpServer? _server;
  
  static const int _maxCacheSize = 100;

  // Cache of messageId -> TDLib FFI remote file_id to avoid redundant FFI calls
  final Map<int, int> _remoteFileIdCache = {};
  // Cache of fileId -> local path to avoid redundant downloads
  final Map<int, String> _localFilePathCache = {};

  void _trimCache() {
    while (_remoteFileIdCache.length > _maxCacheSize) {
      _remoteFileIdCache.remove(_remoteFileIdCache.keys.first);
    }
    while (_localFilePathCache.length > _maxCacheSize) {
      _localFilePathCache.remove(_localFilePathCache.keys.first);
    }
  }

  void _cacheRemoteFileId(int messageId, int fileId) {
    _trimCache();
    _remoteFileIdCache[messageId] = fileId;
  }

  void _cacheLocalFilePath(int fileId, String path) {
    _trimCache();
    _localFilePathCache[fileId] = path;
  }

  int get port => _server?.port ?? 0;

  Future<void> start() async {
    if (_server != null) return;
    
    final router = Router();
    router.get('/stream', _handleStream);

    // Bind to Port 0 to request a dynamic ephemeral port from the OS
    _server = await shelf_io.serve(router.call, InternetAddress.loopbackIPv4, 0);
    AppLogger.info('Streaming server running on http://127.0.0.1:$port');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<Response> _handleStream(Request request) async {
    try {
      final fileId = request.url.queryParameters['id'];
      if (fileId == null || fileId.isEmpty) {
        return Response(400, body: 'Missing file id parameter');
      }

      final db = ref.read(databaseProvider);
      
      // 1. Fetch file info from local DB
      final fileData = await (db.select(db.files)..where((f) => f.id.equals(fileId))).getSingleOrNull();
      if (fileData == null) {
        return Response(404, body: 'File not found');
      }

      final plainFileSize = fileData.size ?? 0;
      final mimeType = fileData.mimeType ?? 'video/mp4';

      // 2. Fetch chunks from local DB
      final chunks = await (db.select(db.chunks)
        ..where((c) => c.fileId.equals(fileId))
        ..orderBy([(c) => OrderingTerm.asc(c.chunkIndex)])
      ).get();

      if (chunks.isEmpty) {
        return Response(404, body: 'File chunks metadata missing');
      }

      // 3. Unwrap DEK & CTR IV
      final masterKeyBytes = MasterKeyProvider.instance.key;
      if (masterKeyBytes == null) {
        AppLogger.warning('StreamingServer: Vault is locked - rejecting stream for $fileId');
        return Response(401, body: 'Vault is locked');
      }

      final cipher = AesGcm.with256bits();
      final masterKey = await cipher.newSecretKeyFromBytes(masterKeyBytes);

      final parts = fileData.sha256Hash!.contains('|') 
          ? fileData.sha256Hash!.split('|') 
          : fileData.sha256Hash!.split(':');
      if (parts.length < 3) {
        return Response(500, body: 'Invalid key material in database');
      }

      final dekNonce = base64Decode(parts[0]);
      final dekMac = base64Decode(parts[1]);
      final dekCipherText = base64Decode(parts[2]);
      
      final dekBytes = await cipher.decrypt(
        SecretBox(dekCipherText, nonce: dekNonce, mac: Mac(dekMac)),
        secretKey: masterKey,
      );

      List<int>? ctrIv;
      if (parts.length >= 4) {
        ctrIv = base64Decode(parts[3]);
      }

      // 4. Handle Range Header
      final rangeHeader = request.headers['range'];
      var start = 0;
      int end = plainFileSize - 1;

      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        final parts = rangeHeader.substring(6).split('-');
        if (parts[0].isNotEmpty) start = int.parse(parts[0]);
        if (parts.length > 1 && parts[1].isNotEmpty) {
          end = int.parse(parts[1]);
        }
      }

      if (start >= plainFileSize) {
        return Response(416, headers: {'Content-Range': 'bytes */$plainFileSize'});
      }

      end = min(end, plainFileSize - 1);
      final contentLength = end - start + 1;

      final headers = {
        'Content-Type': mimeType,
        'Accept-Ranges': 'bytes',
        'Content-Length': contentLength.toString(),
        'Content-Range': 'bytes $start-$end/$plainFileSize',
      };

      // 5. Create streaming response body
      final stream = _createDecryptionStream(chunks, start, end, dekBytes, ctrIv);

      return Response(
        206, // Partial Content
        headers: headers,
        body: stream,
      );
    } catch (e, s) {
      AppLogger.error('Streaming error', e, s);
      return Response.internalServerError(body: e.toString());
    }
  }

  Stream<List<int>> _createDecryptionStream(
    List<ChunkData> chunks,
    int startPlain,
    int endPlain,
    List<int> dekBytes,
    List<int>? ctrIv,
  ) async* {
    final telegram = ref.read(telegramServiceProvider.notifier);

    // Calculate cumulative chunk boundaries
    var currentOffset = 0;
    final List<Map<String, dynamic>> chunkInfos = [];
    for (final chunk in chunks) {
      // If chunk size is not stored, fall back to the standard 20MB threshold
      final size = chunk.size ?? (20 * 1024 * 1024);
      chunkInfos.add({
        'chunk': chunk,
        'start': currentOffset,
        'end': currentOffset + size - 1,
      });
      currentOffset += size;
    }

    final ctrAlgorithm = AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty);
    final dekSecretKey = await ctrAlgorithm.newSecretKeyFromBytes(dekBytes);

    // Iterate over chunks and stream relevant bytes
    for (final chunkInfo in chunkInfos) {
      final ChunkData chunk = chunkInfo['chunk'];
      final int startOffset = chunkInfo['start'];
      final int endOffset = chunkInfo['end'];

      // Check if this chunk overlaps with requested range
      if (startOffset > endPlain || endOffset < startPlain) {
        continue;
      }

      // Compute overlapping range within this chunk
      final int chunkStart = max(0, startPlain - startOffset);
      final int chunkEnd = min(endOffset - startOffset, endPlain - startOffset);

      if (chunkStart > chunkEnd) continue;

      // 1. Resolve remote file ID for this chunk
      int? remoteFileId = _remoteFileIdCache[chunk.messageId ?? 0];
      if (remoteFileId == null) {
        final message = await telegram.getMessage(chunk.channelId!, chunk.messageId!);
        final content = message['content'];
        if (content != null && content['@type'] == 'messageDocument') {
          remoteFileId = content['document']['document']['id'] as int?;
          if (remoteFileId != null) {
            _cacheRemoteFileId(chunk.messageId!, remoteFileId);
          }
        }
      }

      if (remoteFileId == null) {
        throw Exception("Failed to resolve remote file ID for message ${chunk.messageId}");
      }

      // 2. Download and decrypt range
      if (ctrIv != null) {
        // AES-CTR Mode range seek:
        // Align chunk range to 16-byte boundaries
        final int startBlock = (startOffset + chunkStart) ~/ 16;
        final int endBlock = (startOffset + chunkEnd) ~/ 16;
        final int cipherStart = (chunkStart ~/ 16) * 16;
        final int cipherEnd = ((chunkEnd ~/ 16) + 1) * 16;
        final int limit = cipherEnd - cipherStart;

        // Fetch exact CTR range from Telegram
        final cipherBytes = await _downloadAndReadRange(telegram, remoteFileId, cipherStart, limit);
        
        final incrementedNonce = EncryptionEngine.incrementNonce(ctrIv, startBlock);
        final decryptedBlock = await ctrAlgorithm.decrypt(
          SecretBox(cipherBytes, nonce: incrementedNonce, mac: Mac.empty),
          secretKey: dekSecretKey,
        );

        final int offsetInBlock = chunkStart - cipherStart;
        final int sliceLength = chunkEnd - chunkStart + 1;

        yield decryptedBlock.sublist(offsetInBlock, offsetInBlock + sliceLength);
      } else {
        // Fallback AES-GCM block decryption:
        // Since GCM has 12-byte nonces and 16-byte MACs prepended to each 4MB block on disk,
        // we must download the full block(s) that overlap with the request.
        const int plainBlockSize = 4 * 1024 * 1024;
        const int cryptoBlockSize = plainBlockSize + 12 + 16;

        var currentChunkOffset = chunkStart;
        while (currentChunkOffset <= chunkEnd) {
          final int blockIndex = currentChunkOffset ~/ plainBlockSize;
          final int blockStartPlain = blockIndex * plainBlockSize;
          final int blockStartCrypto = blockIndex * cryptoBlockSize;

          // Poll/Download GCM block
          final cipherBytes = await _downloadAndReadRange(telegram, remoteFileId, blockStartCrypto, cryptoBlockSize);
          if (cipherBytes.length < 28) {
            throw Exception("GCM block too small");
          }

          final nonce = cipherBytes.sublist(0, 12);
          final macBytes = cipherBytes.sublist(12, 28);
          final cipherText = cipherBytes.sublist(28);

          final gcmCipher = AesGcm.with256bits();
          final gcmSecretKey = await gcmCipher.newSecretKeyFromBytes(dekBytes);
          final decryptedData = await gcmCipher.decrypt(
            SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
            secretKey: gcmSecretKey,
          );

          final int offsetInBlock = currentChunkOffset - blockStartPlain;
          final int remainingRequested = chunkEnd - currentChunkOffset + 1;
          final int lenToTake = min(decryptedData.length - offsetInBlock, remainingRequested);

          yield decryptedData.sublist(offsetInBlock, offsetInBlock + lenToTake);

          currentChunkOffset += lenToTake;
        }
      }
    }
  }

  /// Downloads a specific offset and limit range via TDLib, polling until downloaded.
  /// Uses the same reliable approach as _downloadFullChunk in decrypted_image_viewer.
  Future<Uint8List> _downloadAndReadRange(TelegramService telegram, int fileId, int offset, int limit) async {
    // Check if we already have a local path cached
    if (!_localFilePathCache.containsKey(fileId)) {
      // Download the entire file synchronously
      final res = await telegram.sendRequest({
        "@type": "downloadFile",
        "file_id": fileId,
        "priority": 32,
        "synchronous": true,
      });
      final file = res['file'] as Map<String, dynamic>? ?? res;
      final local = file['local'] as Map<String, dynamic>?;
      if (local == null) {
        throw Exception("No local info in TDLib download response for file $fileId");
      }

      final localPath = local['path'] as String?;
      if (localPath == null || localPath.isEmpty) {
        throw Exception("Empty local path for file $fileId");
      }

      if (local['is_downloading_completed'] == true) {
        _cacheLocalFilePath(fileId, localPath);
      } else {
        // Poll with getFile until download completes
        for (var i = 0; i < 240; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          final getFileRes = await telegram.sendRequest({
            "@type": "getFile",
            "file_id": fileId,
          });
          final getFileLocal = getFileRes['local'] as Map<String, dynamic>?;
          if (getFileLocal != null && getFileLocal['is_downloading_completed'] == true) {
            final path = getFileLocal['path'] as String?;
            if (path != null && path.isNotEmpty) {
              _cacheLocalFilePath(fileId, path);
              break;
            }
          }
          if (getFileRes['@type'] == 'error') {
            throw Exception("TDLib error downloading file $fileId: ${getFileRes['message']}");
          }
        }
      }
    }

    final cachedPath = _localFilePathCache[fileId];
    if (cachedPath == null) {
      throw Exception("Timeout waiting for TDLib download range at offset $offset");
    }

    final fileOnDisk = File(cachedPath);
    if (!await fileOnDisk.exists()) {
      _localFilePathCache.remove(fileId);
      throw Exception("Downloaded file not found at $cachedPath");
    }

    final raf = await fileOnDisk.open();
    try {
      await raf.setPosition(offset);
      final bytes = await raf.read(limit);
      if (bytes.isEmpty) {
        throw Exception("Read 0 bytes at offset $offset from $cachedPath");
      }
      return Uint8List.fromList(bytes);
    } finally {
      await raf.close();
    }
  }
}

final streamingServerProvider = Provider<StreamingServer>(StreamingServer.new);
