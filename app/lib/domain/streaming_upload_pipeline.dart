import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// Describes one chunk to encrypt within a batch.
class _ChunkDef {
  final int index;
  final int startOffset;
  final int length;
  final String outputPath;

  const _ChunkDef({
    required this.index,
    required this.startOffset,
    required this.length,
    required this.outputPath,
  });
}

/// Payload for the batch encryption isolate.
class _BatchPayload {
  final String sourceFilePath;
  final List<int> dekBytes;
  final List<int>? ctrIv;
  final List<_ChunkDef> chunks;
  final bool computeSourceHash;

  _BatchPayload({
    required this.sourceFilePath,
    required this.dekBytes,
    this.ctrIv,
    required this.chunks,
    this.computeSourceHash = false,
  });
}

/// Result from the batch encryption isolate.
class BatchResult {
  final List<String> chunkPaths;
  final String? sourceFileHash;
  final bool success;
  final String? error;

  BatchResult({
    required this.chunkPaths,
    this.sourceFileHash,
    this.success = true,
    this.error,
  });
}

/// Encrypts file chunks in batches inside a single isolate per batch.
///
/// ## Why this fixes the large-file upload crash
///
/// **Old approach** (crashes on large files):
/// - Read entire source file for SHA-256 hash FIRST (await, blocks pipeline)
/// - Loop: `compute()` per chunk → N isolates for N chunks
/// - Each isolate creates/destroys AES cipher, opens/seeks file independently
/// - Sequential: encrypt → upload → encrypt → upload (idle time between)
///
/// **New approach**:
/// - Batch 5 chunks per isolate (80% fewer isolates)
/// - Source file hash computed inside first batch's isolate (no pre-read)
/// - Pipeline: upload previous batch while encrypting next batch
/// - Temp files cleaned immediately after each chunk uploads
class BatchEncryptor {
  /// How many chunks to encrypt per isolate call.
  static const int batchSize = 5;

  static const int _bufferSize = 4 * 1024 * 1024; // 4MB

  /// Encrypts a batch of chunks in ONE isolate.
  ///
  /// If [computeSourceHash] is true (first batch only), the isolate also reads
  /// the entire source file to compute SHA-256 after encrypting the batch
  /// chunks. This replaces the separate `_calculateFileHash` pass.
  static Future<BatchResult> encryptBatch({
    required String sourceFilePath,
    required int fileLength,
    required List<int> dekBytes,
    required List<int>? ctrIv,
    required int chunkIndexStart,
    required int chunkCount,
    required int chunkThreshold,
    required String tempDir,
    bool computeSourceHash = false,
  }) async {
    final chunks = <_ChunkDef>[];
    for (var i = 0; i < chunkCount; i++) {
      final globalIndex = chunkIndexStart + i;
      final startOffset = globalIndex * chunkThreshold;
      final length = min(chunkThreshold, fileLength - startOffset);
      if (length <= 0) break;
      chunks.add(_ChunkDef(
        index: globalIndex,
        startOffset: startOffset,
        length: length,
        outputPath: '$tempDir${Platform.pathSeparator}chunk_${globalIndex}.enc',
      ));
    }

    if (chunks.isEmpty) {
      return BatchResult(chunkPaths: []);
    }

    final payload = _BatchPayload(
      sourceFilePath: sourceFilePath,
      dekBytes: dekBytes,
      ctrIv: ctrIv,
      chunks: chunks,
      computeSourceHash: computeSourceHash,
    );

    debugPrint('[BatchEncryptor] Spawning isolate for ${chunks.length} chunks, computeSourceHash=$computeSourceHash, file=${sourceFilePath.split(Platform.pathSeparator).last}');
    final result = compute(_runBatchIsolate, payload);
    debugPrint('[BatchEncryptor] Isolate spawned successfully');
    // 10-minute timeout prevents indefinite hangs if isolate stalls
    return result.timeout(const Duration(minutes: 10), onTimeout: () {
      debugPrint('[BatchEncryptor] Isolate timed out after 10 minutes');
      return BatchResult(
        chunkPaths: [],
        success: false,
        error: 'Batch encryption isolate timed out after 10 minutes',
      );
    });
  }

  /// The isolate entry point: encrypt all chunks in [payload].
  static Future<BatchResult> _runBatchIsolate(_BatchPayload payload) async {
    final engine = _BatchEncryptionEngine();
    final List<String> paths = [];

    for (final chunk in payload.chunks) {
      try {
        final outputFile = File(chunk.outputPath);
        await engine.encryptChunk(
          sourcePath: payload.sourceFilePath,
          startOffset: chunk.startOffset,
          length: chunk.length,
          dekBytes: payload.dekBytes,
          ctrIv: payload.ctrIv,
          outputFile: outputFile,
          isGcm: payload.ctrIv == null,
        );
        paths.add(chunk.outputPath);
      } catch (e) {
        return BatchResult(
          chunkPaths: paths,
          success: false,
          error: 'Chunk ${chunk.index} encryption failed: $e',
        );
      }
    }

    // Compute source file hash if requested (first batch only).
    // This replaces the separate full-file read in the old `_calculateFileHash`.
    String? sourceHash;
    if (payload.computeSourceHash) {
      sourceHash = await _hashFileInIsolate(payload.sourceFilePath);
    }

    return BatchResult(
      chunkPaths: paths,
      sourceFileHash: sourceHash,
      success: true,
    );
  }

  /// Full-file SHA-256 hash in isolate. Uses streaming 4MB reads.
  static Future<String> _hashFileInIsolate(String filePath) async {
    final digestSink = _DigestSink();
    final hashSink = crypto.sha256.startChunkedConversion(digestSink);
    final file = await File(filePath).open();
    try {
      final length = await file.length();
      final buffer = Uint8List(_bufferSize);
      var offset = 0;
      while (offset < length) {
        final toRead = min(_bufferSize, length - offset);
        final bytesRead = await file.readInto(buffer, 0, toRead);
        if (bytesRead == 0) break;
        hashSink.add(Uint8List.view(buffer.buffer, 0, bytesRead));
        offset += bytesRead;
        await Future.delayed(Duration.zero);
      }
    } finally {
      await file.close();
    }
    hashSink.close();
    return digestSink.value.toString();
  }
}

/// Sink that captures a single crypto.Digest from startChunkedConversion.
class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? _digest;

  @override
  void add(crypto.Digest data) => _digest = data;

  @override
  void close() {}

  crypto.Digest? get value => _digest;
}

/// Lightweight chunk encryption engine for isolate use.
/// Uses `package:cryptography` (same as main-isolate EncryptionEngine).
class _BatchEncryptionEngine {
  static const int _bufferSize = 4 * 1024 * 1024; // 4MB

  /// Encrypts one chunk from source file range [startOffset, startOffset+length)
  /// into [outputFile]. Uses AES-256-GCM when [isGcm] is true, otherwise AES-256-CTR.
  Future<void> encryptChunk({
    required String sourcePath,
    required int startOffset,
    required int length,
    required List<int> dekBytes,
    required List<int>? ctrIv,
    required File outputFile,
    required bool isGcm,
  }) async {
    final file = await File(sourcePath).open();
    final sink = outputFile.openWrite();

    try {
      await file.setPosition(startOffset);

      if (isGcm) {
        // AES-256-GCM
        final cipher = AesGcm.with256bits();
        final secretKey = await cipher.newSecretKeyFromBytes(dekBytes);
        final buffer = Uint8List(_bufferSize);
        var processed = 0;

        while (processed < length) {
          final toRead = min(_bufferSize, length - processed);
          final bytesRead = await file.readInto(buffer, 0, toRead);
          if (bytesRead == 0) break;

          final nonce = cipher.newNonce();
          final block = Uint8List.fromList(buffer.sublist(0, bytesRead));
          final secretBox = await cipher.encrypt(
            block,
            secretKey: secretKey,
            nonce: nonce,
          );

          sink.add(secretBox.nonce);
          sink.add(secretBox.mac.bytes);
          sink.add(secretBox.cipherText);
          processed += bytesRead;
          await sink.flush();
          await Future.delayed(Duration.zero);
        }
      } else {
        // AES-256-CTR
        final ctrAlgorithm = AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty);
        final secretKey = await ctrAlgorithm.newSecretKeyFromBytes(dekBytes);
        final buffer = Uint8List(_bufferSize);
        var processed = 0;

        while (processed < length) {
          final toRead = min(_bufferSize, length - processed);
          final bytesRead = await file.readInto(buffer, 0, toRead);
          if (bytesRead == 0) break;

          final int startBlock = (startOffset + processed) ~/ 16;
          final incrementedNonce = _incrementNonceCtr(ctrIv!, startBlock);

          final block = Uint8List.fromList(buffer.sublist(0, bytesRead));
          final secretBox = await ctrAlgorithm.encrypt(
            block,
            secretKey: secretKey,
            nonce: incrementedNonce,
          );

          sink.add(secretBox.cipherText);
          processed += bytesRead;
          await sink.flush();
          await Future.delayed(Duration.zero);
        }
      }
    } finally {
      await file.close();
      await sink.flush();
      await sink.close();
    }
  }

  /// Big-endian 16-byte counter increment — matches EncryptionEngine.incrementNonce.
  static Uint8List _incrementNonceCtr(List<int> initialNonce, int increment) {
    final nonce = Uint8List.fromList(initialNonce);
    var carry = increment;
    for (var i = 15; i >= 0 && carry > 0; i--) {
      final val = nonce[i] + carry;
      nonce[i] = val & 0xFF;
      carry = val >> 8;
    }
    return nonce;
  }
}
