import 'dart:async';
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

  /// Sub-chunk page size for AES-CTR streaming (2MB).
  /// Exactly divisible by 16 bytes (2,097,152 % 16 == 0), ensuring bounded heap (<30MB)
  /// and rapid cancellation when video playback seeks.
  static const int pagedSubChunkSize = 2 * 1024 * 1024;

  // Active streaming requests per fileId, allowing obsolete range requests to be cancelled on seeks
  final Map<String, List<ActiveStreamingRequest>> _activeRequestsByFile = {};

  // Active chunk downloads tracked by TDLib fileId with subscriber tokens for ref-counted cancellation
  final Map<int, _ChunkDownloadRecord> _activeDownloads = {};

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
    _server = await runZonedGuarded<Future<HttpServer>>(
      () => shelf_io.serve(router.call, InternetAddress.loopbackIPv4, 0),
      (error, stack) {
        if (error is HttpException &&
            error.message.contains('Content size below specified contentLength')) {
          AppLogger.info('StreamingServer: Client closed connection before full range delivered');
          return;
        }
        if (error is StreamCancelledException || error is SocketException) {
          AppLogger.info('StreamingServer: Range request aborted by client');
          return;
        }
        AppLogger.error('StreamingServer Zone Error', error, stack);
      },
    );
    AppLogger.info('Streaming server running on http://127.0.0.1:$port');
  }

  Future<void> stop() async {
    cancelAllStreams();
    await _server?.close(force: true);
    _server = null;
  }

  void _registerActiveRequest(ActiveStreamingRequest request) {
    _activeRequestsByFile.putIfAbsent(request.fileId, () => []).add(request);
  }

  void _unregisterActiveRequest(ActiveStreamingRequest request) {
    final list = _activeRequestsByFile[request.fileId];
    if (list != null) {
      list.removeWhere((r) => r.requestId == request.requestId);
      if (list.isEmpty) {
        _activeRequestsByFile.remove(request.fileId);
      }
    }
  }

  /// Cancels all active streaming requests and pipelines for a specific file (e.g. on screen exit or seek).
  void cancelStreamsForFile(dynamic fileId) {
    final key = fileId.toString();
    final list = _activeRequestsByFile.remove(key);
    if (list != null && list.isNotEmpty) {
      AppLogger.info('StreamingServer: Cancelling ${list.length} active streams for file $key');
      for (final req in list) {
        req.cancellationToken.cancel('File streaming closed by client/screen exit');
      }
    }
  }

  /// Cancels all active streaming requests across all files.
  void cancelAllStreams() {
    _activeRequestsByFile.keys.toList().forEach(cancelStreamsForFile);
  }

  Stream<List<int>> _bindStreamCancellation({
    required Stream<List<int>> source,
    required CancellationToken token,
    required void Function() onCancel,
  }) {
    late StreamController<List<int>> controller;
    StreamSubscription<List<int>>? subscription;

    void onTokenCancelled() {
      if (!controller.isClosed) {
        controller.addError(
          const SocketException('Stream cancelled: client disconnected or seek'),
        );
        unawaited(controller.close());
      }
    }

    void cleanup() {
      token.removeListener(onTokenCancelled);
      onCancel();
    }

    controller = StreamController<List<int>>(
      onListen: () {
        subscription = source.listen(
          (data) {
            if (!controller.isClosed) {
              controller.add(data);
            }
          },
          onError: (err, stack) {
            if (!controller.isClosed) {
              if (err is StreamCancelledException || token.isCancelled) {
                controller.addError(
                  const SocketException('Stream cancelled: client disconnected or seek'),
                );
              } else {
                controller.addError(err, stack);
              }
              unawaited(controller.close());
            }
            cleanup();
          },
          onDone: () {
            if (!controller.isClosed) {
              if (token.isCancelled) {
                controller.addError(
                  const SocketException('Stream cancelled: client disconnected or seek'),
                );
              }
              unawaited(controller.close());
            }
            cleanup();
          },
          cancelOnError: true,
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () async {
        token.cancel('HTTP client disconnected');
        cleanup();
        await subscription?.cancel();
      },
    );

    token.addListener(onTokenCancelled);

    return controller.stream;
  }

  Future<void> _cancellableDelay(Duration duration, CancellationToken token) {
    if (token.isCancelled) return Future.error(const StreamCancelledException());
    final completer = Completer<void>();
    final timer = Timer(duration, () {
      if (!completer.isCompleted) completer.complete();
    });
    void listener() {
      timer.cancel();
      if (!completer.isCompleted) {
        completer.completeError(const StreamCancelledException());
      }
    }
    token.addListener(listener);
    return completer.future.whenComplete(() {
      token.removeListener(listener);
    });
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

      final requestToken = CancellationToken();
      final requestId = '${fileId}_${start}_${end}_${DateTime.now().microsecondsSinceEpoch}';
      final activeReq = ActiveStreamingRequest(
        requestId: requestId,
        fileId: fileId,
        rangeStart: start,
        rangeEnd: end,
        createdAt: DateTime.now(),
        cancellationToken: requestToken,
      );
      _registerActiveRequest(activeReq);

      // 6. Create streaming response body with cancellation binding and backpressure
      final rawStream = _createDecryptionStream(
        chunkInfos,
        start,
        end,
        dekBytes,
        ctrIv,
        requestToken,
      );

      final stream = _bindStreamCancellation(
        source: rawStream,
        token: requestToken,
        onCancel: () {
          _unregisterActiveRequest(activeReq);
        },
      );

      return Response(
        statusCode,
        headers: headers,
        body: stream,
      );
    } on Object catch (e, s) {
      if (e is StreamCancelledException) {
        return Response(499, body: 'Stream cancelled');
      }
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
    CancellationToken token,
  ) async* {
    try {
      token.throwIfCancelled();
      final telegram = ref.read(telegramServiceProvider.notifier);

    // Iterate over chunks and stream relevant bytes
    for (final chunkInfo in chunkInfos) {
      token.throwIfCancelled();
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
        token.throwIfCancelled();
        final content = message['content'] as Map<String, dynamic>?;
        if (content != null && content['@type'] == 'messageDocument') {
          final documentObj = content['document'] as Map<String, dynamic>?;
          final doc = documentObj?['document'] as Map<String, dynamic>?;
          remoteFileId = doc?['id'] as int?;
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
        // AES-CTR Mode range seek with 2MB paged sub-chunk streaming:
        var subChunkStart = chunkStart;
        while (subChunkStart <= chunkEnd) {
          token.throwIfCancelled();
          final int subChunkEnd = min(subChunkStart + pagedSubChunkSize - 1, chunkEnd);

          // Align sub-chunk range to 16-byte counter block boundaries:
          final int cipherStart = (subChunkStart ~/ 16) * 16;
          final int cipherEnd = ((subChunkEnd ~/ 16) + 1) * 16;
          final int limit = cipherEnd - cipherStart;

          // Compute 16-byte counter block offset.
          // startOffset is chunk base plain offset. Because chunk sizes are multiples
          // of 16 bytes (20/25/50MB), (startOffset + cipherStart) ~/ 16 is exact.
          final int startBlock = (startOffset + cipherStart) ~/ 16;
          final incrementedNonce = EncryptionEngine.incrementNonce(ctrIv, startBlock);

          // Fetch exact CTR sub-chunk range from disk cache via TDLib
          final cipherBytes = await _downloadAndReadRange(
            telegram: telegram,
            fileId: remoteFileId,
            offset: cipherStart,
            limit: limit,
            token: token,
          );

          token.throwIfCancelled();

          // Offload decryption to background isolate via compute
          final decryptedBlock = await compute(
            decryptCtrSubChunkIsolate,
            CtrDecryptPayload(
              cipherBytes: cipherBytes,
              dekBytes: dekBytes,
              nonce: incrementedNonce,
            ),
          );

          token.throwIfCancelled();

          final int offsetInBlock = subChunkStart - cipherStart;
          final int sliceLength = subChunkEnd - subChunkStart + 1;

          final safeStart = min(max(0, offsetInBlock), decryptedBlock.length);
          final safeEnd = min(safeStart + sliceLength, decryptedBlock.length);
          if (safeStart < safeEnd) {
            if (safeStart == 0 && safeEnd == decryptedBlock.length) {
              yield decryptedBlock;
            } else {
              yield decryptedBlock.sublist(safeStart, safeEnd);
            }
          }

          subChunkStart = subChunkEnd + 1;
        }
      } else {
        // Fallback AES-GCM block decryption:
        // Since GCM has 12-byte nonces and 16-byte MACs prepended to each 4MB block on disk,
        // we must download the full block(s) that overlap with the request.
        const int plainBlockSize = 4 * 1024 * 1024;
        const int cryptoBlockSize = plainBlockSize + 12 + 16;

        var currentChunkOffset = chunkStart;
        while (currentChunkOffset <= chunkEnd) {
          token.throwIfCancelled();
          final int blockIndex = currentChunkOffset ~/ plainBlockSize;
          final int blockStartPlain = blockIndex * plainBlockSize;
          final int blockStartCrypto = blockIndex * cryptoBlockSize;

          // Poll/Download GCM block
          final cipherBytes = await _downloadAndReadRange(
            telegram: telegram,
            fileId: remoteFileId,
            offset: blockStartCrypto,
            limit: cryptoBlockSize,
            token: token,
          );
          if (cipherBytes.length < 28) {
            throw Exception("GCM block too small");
          }

          token.throwIfCancelled();

          final nonce = cipherBytes.sublist(0, 12);
          final macBytes = cipherBytes.sublist(12, 28);
          final cipherText = cipherBytes.sublist(28);

          final gcmCipher = AesGcm.with256bits();
          final gcmSecretKey = await gcmCipher.newSecretKeyFromBytes(dekBytes);
          final decryptedData = await gcmCipher.decrypt(
            SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
            secretKey: gcmSecretKey,
          );

          token.throwIfCancelled();

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
    } on StreamCancelledException catch (e) {
      token.cancel(e.message);
      return;
    }
  }

  /// Standalone background task that drives TDLib polling for a chunk.
  /// Runs independently of any individual client request frame until completed or all subscribers cancel.
  Future<void> _startChunkDownload(
    _ChunkDownloadRecord record,
    TelegramService telegram,
  ) async {
    final fileId = record.fileId;
    try {
      final res = await telegram.sendRequest({
        "@type": "downloadFile",
        "file_id": fileId,
        "priority": 32,
        "synchronous": false,
      });

      if (record.isCancelled) return;

      final file = res['file'] as Map<String, dynamic>? ?? res;
      final local = file['local'] as Map<String, dynamic>?;
      final path = local?['path'] as String?;

      if (local?['is_downloading_completed'] == true && path != null && path.isNotEmpty) {
        _cacheLocalFilePath(fileId, path);
        if (!record.completer.isCompleted) {
          record.completer.complete(path);
        }
        return;
      }

      String? completedPath;
      for (var i = 0; i < 480; i++) {
        if (record.isCancelled) return;

        // Non-blocking cancellable delay: wake up after 250ms OR immediately if cancelSignal fires
        await Future.any([
          Future<void>.delayed(const Duration(milliseconds: 250)),
          record.cancelSignal.future,
        ]);

        if (record.isCancelled) return;

        final getFileRes = await telegram.sendRequest({
          "@type": "getFile",
          "file_id": fileId,
        });

        if (record.isCancelled) return;

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

      if (record.isCancelled) return;

      if (completedPath == null) {
        throw Exception("Timeout waiting for TDLib download of chunk $fileId");
      }

      if (!record.completer.isCompleted) {
        record.completer.complete(completedPath);
      }
    } catch (e, st) {
      if (!record.completer.isCompleted) {
        record.completer.completeError(e, st);
      }
    } finally {
      _activeDownloads.remove(fileId);
    }
  }

  /// Awaits a shared future while allowing the individual client's token to abort locally.
  Future<T> _awaitWithCancellation<T>(Future<T> future, CancellationToken token) {
    if (token.isCancelled) {
      return Future.error(StreamCancelledException(token.cancelReason ?? 'Stream cancelled'));
    }
    final completer = Completer<T>();
    completer.future.ignore();
    void listener() {
      if (!completer.isCompleted) {
        completer.completeError(StreamCancelledException(token.cancelReason ?? 'Stream cancelled'));
      }
    }
    token.addListener(listener);

    unawaited(
      future.then((value) {
        if (!completer.isCompleted) completer.complete(value);
      }, onError: (Object err, StackTrace st) {
        if (!completer.isCompleted) completer.completeError(err, st);
      }).whenComplete(() {
        token.removeListener(listener);
      }),
    );

    return completer.future;
  }

  /// Downloads a specific offset and limit range via TDLib, polling until downloaded.
  /// Uses a per-fileId record lock and subscriber tokens so concurrent Range requests wait,
  /// and in-flight downloads are cancelled when all subscribers disconnect.
  Future<Uint8List> _downloadAndReadRange({
    required TelegramService telegram,
    required int fileId,
    required int offset,
    required int limit,
    required CancellationToken token,
  }) async {
    token.throwIfCancelled();

    String? localPath = _localFilePathCache[fileId];

    if (localPath == null) {
      var record = _activeDownloads[fileId];
      if (record == null) {
        record = _ChunkDownloadRecord(fileId: fileId);
        _activeDownloads[fileId] = record;
        unawaited(_startChunkDownload(record, telegram));
      }

      final chunkRecord = record;
      chunkRecord.subscribers.add(token);

      void onCancel() {
        chunkRecord.subscribers.remove(token);
        // Only cancel TDLib download and complete completer with error if ALL subscribers disconnected
        if (chunkRecord.subscribers.isEmpty && !chunkRecord.completer.isCompleted) {
          AppLogger.info('StreamingServer: All subscribers cancelled for chunk $fileId. Aborting TDLib download.');
          chunkRecord.isCancelled = true;
          if (!chunkRecord.cancelSignal.isCompleted) {
            chunkRecord.cancelSignal.complete();
          }
          unawaited(telegram.cancelDownloadFile(fileId));
          chunkRecord.completer.completeError(const StreamCancelledException());
        }
      }

      token.addListener(onCancel);
      try {
        localPath = await _awaitWithCancellation(chunkRecord.completer.future, token);
      } finally {
        token.removeListener(onCancel);
      }
    }

    token.throwIfCancelled();

    final fileOnDisk = File(localPath!);
    if (!fileOnDisk.existsSync()) {
      _localFilePathCache.remove(fileId);
      throw Exception("Downloaded file not found at $localPath");
    }

    // Read requested bytes with retries in case file flushing is in progress
    final raf = await fileOnDisk.open();
    try {
      List<int> bytes = [];
      for (var attempt = 0; attempt < 5; attempt++) {
        token.throwIfCancelled();
        await raf.setPosition(offset);
        bytes = await raf.read(limit);
        if (bytes.isNotEmpty) break;
        await _cancellableDelay(const Duration(milliseconds: 100), token);
      }

      if (bytes.isEmpty) {
        throw Exception("Read 0 bytes at offset $offset from $localPath");
      }
      return bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    } finally {
      await raf.close();
    }
  }
}

final streamingServerProvider = Provider<StreamingServer>(StreamingServer.new);

class StreamChunkInfo {
  const StreamChunkInfo({
    required this.chunk,
    required this.start,
    required this.end,
    required this.plainSize,
  });

  final ChunkData chunk;
  final int start;
  final int end;
  final int plainSize;
}

/// Data payload for isolated AES-CTR sub-chunk decryption
class CtrDecryptPayload {
  const CtrDecryptPayload({
    required this.cipherBytes,
    required this.dekBytes,
    required this.nonce,
  });

  final Uint8List cipherBytes;
  final List<int> dekBytes;
  final Uint8List nonce;
}

/// Static isolate entrypoint for AES-CTR sub-chunk decryption.
/// Decoupled from StreamingServer to guarantee zero lexical capture of Riverpod Ref.
@visibleForTesting
Future<Uint8List> decryptCtrSubChunkIsolate(CtrDecryptPayload payload) async {
  final ctrAlgorithm = AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty);
  final secretKey = await ctrAlgorithm.newSecretKeyFromBytes(payload.dekBytes);
  final decrypted = await ctrAlgorithm.decrypt(
    SecretBox(payload.cipherBytes, nonce: payload.nonce, mac: Mac.empty),
    secretKey: secretKey,
  );
  return decrypted is Uint8List ? decrypted : Uint8List.fromList(decrypted);
}

class StreamCancelledException implements Exception {
  const StreamCancelledException([this.message = 'Stream cancelled by client']);

  final String message;
  @override
  String toString() => 'StreamCancelledException: $message';
}

class CancellationToken {
  bool _isCancelled = false;
  bool get isCancelled => _isCancelled;
  String? cancelReason;

  final List<void Function()> _listeners = [];

  void cancel([String reason = 'Cancelled']) {
    if (_isCancelled) return;
    _isCancelled = true;
    cancelReason = reason;
    for (final listener in List.of(_listeners)) {
      try {
        listener();
      } on Object catch (e, s) {
        AppLogger.error('CancellationToken listener error', e, s);
      }
    }
    _listeners.clear();
  }

  void addListener(void Function() listener) {
    if (_isCancelled) {
      try {
        listener();
      } on Object catch (e, s) {
        AppLogger.error('CancellationToken listener error', e, s);
      }
    } else {
      _listeners.add(listener);
    }
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw StreamCancelledException(cancelReason ?? 'Stream cancelled');
    }
  }
}

class ActiveStreamingRequest {
  ActiveStreamingRequest({
    required this.requestId,
    required this.fileId,
    required this.rangeStart,
    required this.rangeEnd,
    required this.createdAt,
    required this.cancellationToken,
  });

  final String requestId;
  final String fileId;
  final int rangeStart;
  final int rangeEnd;
  final DateTime createdAt;
  final CancellationToken cancellationToken;
}

class _ChunkDownloadRecord {
  _ChunkDownloadRecord({required this.fileId}) {
    // Defect 1 fix: Suppress unhandled Zone errors if all subscribers detach
    completer.future.ignore();
  }

  final int fileId;
  final Completer<String> completer = Completer<String>();
  final Set<CancellationToken> subscribers = {};
  bool isCancelled = false;
  final Completer<void> cancelSignal = Completer<void>();
}
