import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
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
import '../upload_orchestrator.dart';

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

      final engine = EncryptionEngine();
      final unwrapped = await engine.unwrapDek(fileData.sha256Hash!, masterKeyBytes);
      final dekBytes = unwrapped[0]!;
      final ctrIv = unwrapped[1];
      final isCtr = ctrIv != null;

      // 4. Calculate chunk infos and exact plain file size
      final chunkInfos = _buildChunkInfos(
        rawChunks: chunks,
        isCtr: isCtr,
        dbFileSize: fileData.size ?? 0,
        totalChunks: fileData.totalChunks,
      );

      final int plainFileSize = chunkInfos.isNotEmpty
          ? (chunkInfos.last.end + 1)
          : (fileData.size ?? 0);

      // Self-heal file size in database if it was previously recorded as ciphertext size
      if (fileData.size != plainFileSize && plainFileSize > 0) {
        unawaited(
          (db.update(db.files)..where((f) => f.id.equals(fileId))).write(
            FilesCompanion(size: Value(plainFileSize)),
          ),
        );
      }

      final mimeType = fileData.mimeType ?? 'video/mp4';

      // 5. Handle Range Header
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

      final isPartial = rangeHeader != null;
      final statusCode = isPartial ? 206 : 200;
      final headers = <String, String>{
        'Content-Type': mimeType,
        'Accept-Ranges': 'bytes',
        'Content-Length': contentLength.toString(),
        if (isPartial) 'Content-Range': 'bytes $start-$end/$plainFileSize',
      };

      // 6. Create streaming response body
      final stream = _createDecryptionStream(
        chunkInfos,
        start,
        end,
        dekBytes,
        ctrIv,
      );

      return Response(
        statusCode,
        headers: headers,
        body: stream,
      );
    } catch (e, s) {
      AppLogger.error('Streaming error', e, s);
      return Response.internalServerError(body: e.toString());
    }
  }

  @visibleForTesting
  List<StreamChunkInfo> buildChunkInfosForTesting({
    required List<ChunkData> rawChunks,
    required bool isCtr,
    required int dbFileSize,
    required int totalChunks,
  }) => _buildChunkInfos(
    rawChunks: rawChunks,
    isCtr: isCtr,
    dbFileSize: dbFileSize,
    totalChunks: totalChunks,
  );

  List<StreamChunkInfo> _buildChunkInfos({
    required List<ChunkData> rawChunks,
    required bool isCtr,
    required int dbFileSize,
    required int totalChunks,
  }) {
    // Deduplicate chunks by chunkIndex, preferring valid messageId > 0
    final Map<int, ChunkData> uniqueChunksMap = {};
    for (final chunk in rawChunks) {
      final idx = chunk.chunkIndex ?? 0;
      final existing = uniqueChunksMap[idx];
      if (existing == null) {
        uniqueChunksMap[idx] = chunk;
      } else if ((existing.messageId == null || existing.messageId! <= 0) &&
          (chunk.messageId != null && chunk.messageId! > 0)) {
        uniqueChunksMap[idx] = chunk;
      }
    }
    final chunks = uniqueChunksMap.values.toList()
      ..sort((a, b) => (a.chunkIndex ?? 0).compareTo(b.chunkIndex ?? 0));

    final int optimalChunkSize = dbFileSize > 0
        ? UploadOrchestrator.getOptimalChunkSize(dbFileSize)
        : 20 * 1024 * 1024;

    var currentOffset = 0;
    final List<StreamChunkInfo> chunkInfos = [];
    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      final chunkIdx = chunk.chunkIndex ?? i;
      int plainSize;
      final isLastChunk = (i == chunks.length - 1) || (totalChunks > 0 && chunkIdx == totalChunks - 1);

      if (chunk.size != null && chunk.size! > 0) {
        if (isCtr) {
          plainSize = chunk.size!;
        } else {
          // In AES-GCM mode, each 4MB block on disk has 12-byte nonce + 16-byte MAC = 28 bytes overhead
          const int plainBlockSize = 4 * 1024 * 1024;
          const int cryptoBlockSize = plainBlockSize + 12 + 16;
          final size = chunk.size!;
          final fullBlocks = size ~/ cryptoBlockSize;
          final remainder = size % cryptoBlockSize;
          final remainderPlain = remainder > 28 ? remainder - 28 : 0;
          plainSize = (fullBlocks * plainBlockSize) + remainderPlain;
        }
      } else {
        // Fallback / Corrupt DB size recovery: compute from optimal chunk size and file boundaries
        if (isLastChunk && dbFileSize > 0) {
          plainSize = max(0, dbFileSize - currentOffset);
        } else {
          plainSize = optimalChunkSize;
        }
      }

      chunkInfos.add(StreamChunkInfo(
        chunk: chunk,
        start: currentOffset,
        end: currentOffset + plainSize - 1,
        plainSize: plainSize,
      ));
      currentOffset += plainSize;
    }
    return chunkInfos;
  }

  Stream<List<int>> _createDecryptionStream(
    List<StreamChunkInfo> chunkInfos,
    int startPlain,
    int endPlain,
    List<int> dekBytes,
    List<int>? ctrIv,
  ) async* {
    final telegram = ref.read(telegramServiceProvider.notifier);

    final ctrAlgorithm = AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty);
    final dekSecretKey = await ctrAlgorithm.newSecretKeyFromBytes(dekBytes);

    // Iterate over chunks and stream relevant bytes
    for (final chunkInfo in chunkInfos) {
      final ChunkData chunk = chunkInfo.chunk;
      final int startOffset = chunkInfo.start;
      final int endOffset = chunkInfo.end;

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

        final safeStart = min(max(0, offsetInBlock), decryptedBlock.length);
        final safeEnd = min(safeStart + sliceLength, decryptedBlock.length);
        if (safeStart < safeEnd) {
          yield decryptedBlock.sublist(safeStart, safeEnd);
        }
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
          if (lenToTake <= 0) break;

          final safeStart = min(max(0, offsetInBlock), decryptedData.length);
          final safeEnd = min(safeStart + lenToTake, decryptedData.length);
          if (safeStart < safeEnd) {
            yield decryptedData.sublist(safeStart, safeEnd);
          }

          currentChunkOffset += lenToTake;
        }
      }
    }
  }

  // Cache of fileId -> active download completer to deduplicate concurrent TDLib requests
  final Map<int, Completer<String>> _downloadLocks = {};

  /// Downloads a specific offset and limit range via TDLib, polling until downloaded.
  /// Uses a per-fileId Completer lock so concurrent Range requests wait for the single download.
  Future<Uint8List> _downloadAndReadRange(TelegramService telegram, int fileId, int offset, int limit) async {
    String? localPath = _localFilePathCache[fileId];

    if (localPath == null) {
      // Check if another request is currently downloading this fileId
      if (_downloadLocks.containsKey(fileId)) {
        localPath = await _downloadLocks[fileId]!.future;
      } else {
        final completer = Completer<String>();
        _downloadLocks[fileId] = completer;

        try {
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

          final path = local['path'] as String?;
          if (path == null || path.isEmpty) {
            throw Exception("Empty local path for file $fileId");
          }

          if (local['is_downloading_completed'] == true) {
            _cacheLocalFilePath(fileId, path);
            localPath = path;
            completer.complete(path);
          } else {
            // Poll with getFile until download completes
            String? completedPath;
            for (var i = 0; i < 240; i++) {
              await Future.delayed(const Duration(milliseconds: 500));
              final getFileRes = await telegram.sendRequest({
                "@type": "getFile",
                "file_id": fileId,
              });
              final getFileLocal = getFileRes['local'] as Map<String, dynamic>?;
              if (getFileLocal != null && getFileLocal['is_downloading_completed'] == true) {
                final p = getFileLocal['path'] as String?;
                if (p != null && p.isNotEmpty) {
                  completedPath = p;
                  _cacheLocalFilePath(fileId, p);
                  break;
                }
              }
              if (getFileRes['@type'] == 'error') {
                throw Exception("TDLib error downloading file $fileId: ${getFileRes['message']}");
              }
            }

            if (completedPath == null) {
              throw Exception("Timeout waiting for TDLib download of file $fileId");
            }
            localPath = completedPath;
            completer.complete(completedPath);
          }
        } catch (e) {
          if (!completer.isCompleted) {
            completer.completeError(e);
          }
          rethrow;
        } finally {
          _downloadLocks.remove(fileId);
        }
      }
    }

    if (localPath == null || localPath.isEmpty) {
      throw Exception("Timeout waiting for TDLib download range at offset $offset");
    }

    final fileOnDisk = File(localPath);
    if (!await fileOnDisk.exists()) {
      _localFilePathCache.remove(fileId);
      throw Exception("Downloaded file not found at $localPath");
    }

    // Read requested bytes with retries in case file flushing is in progress
    final raf = await fileOnDisk.open();
    try {
      List<int> bytes = [];
      for (var attempt = 0; attempt < 5; attempt++) {
        await raf.setPosition(offset);
        bytes = await raf.read(limit);
        if (bytes.isNotEmpty) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (bytes.isEmpty) {
        throw Exception("Read 0 bytes at offset $offset from $localPath");
      }
      return Uint8List.fromList(bytes);
    } finally {
      await raf.close();
    }
  }
}

final streamingServerProvider = Provider<StreamingServer>(StreamingServer.new);

class StreamChunkInfo {
  final ChunkData chunk;
  final int start;
  final int end;
  final int plainSize;

  const StreamChunkInfo({
    required this.chunk,
    required this.start,
    required this.end,
    required this.plainSize,
  });
}
