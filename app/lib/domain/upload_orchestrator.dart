import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/logger.dart';
import '../data/crypto/encryption_engine.dart';
import '../features/telegram/telegram_service.dart';

class EncryptJobPayload {
  EncryptJobPayload({
    required this.sourceFilePath,
    required this.outputDirectory,
    required this.dekBytes,
    this.chunkLimit,
    this.ctrIv,
  });

  final String sourceFilePath;
  final String outputDirectory;
  final List<int> dekBytes;
  final int? chunkLimit;
  final List<int>? ctrIv;
}

class _SingleChunkPayload {
  _SingleChunkPayload({
    required this.sourceFilePath,
    required this.outputFilePath,
    required this.startOffset,
    required this.chunkLength,
    required this.dekBytes,
    this.ctrIv,
  });

  final String sourceFilePath;
  final String outputFilePath;
  final int startOffset;
  final int chunkLength;
  final List<int> dekBytes;
  final List<int>? ctrIv;
}

class UploadOrchestrator {
  UploadOrchestrator();

  /// Determines optimal chunk size in bytes based on file length.
  /// - Files <= 20MB: single chunk (fileLength)
  /// - Files <= 500MB: 20MB chunks
  /// - Files <= 2GB: 25MB chunks
  /// - Files > 2GB: 50MB chunks (keeps chunks <= 80 even for 4GB files, well under Telegram limits)
  static int getOptimalChunkSize(int fileLength) {
    const int mb = 1024 * 1024;
    if (fileLength <= 20 * mb) {
      return fileLength;
    } else if (fileLength <= 500 * mb) {
      return 20 * mb;
    } else if (fileLength <= 2048 * mb) {
      return 25 * mb;
    } else {
      return 50 * mb;
    }
  }

  /// Computes full-file SHA-256 hash in a background isolate using 4MB streaming reads.
  /// This prevents freezing the UI or main event loop during large file processing.
  static Future<String> computeFileHash(File file) async {
    return compute(_hashFileIsolate, file.path);
  }

  static Future<String> _hashFileIsolate(String filePath) async {
    final algorithm = Sha256();
    final sink = algorithm.newHashSink();
    final openFile = await File(filePath).open();
    try {
      const int bufferSize = 4 * 1024 * 1024;
      final length = await openFile.length();
      var offset = 0;
      while (offset < length) {
        final toRead = (length - offset < bufferSize) ? length - offset : bufferSize;
        final block = await openFile.read(toRead);
        if (block.isEmpty) break;
        sink.add(block);
        offset += toRead;
        await Future.delayed(Duration.zero);
      }
    } finally {
      await openFile.close();
    }
    sink.close();
    final hash = await sink.hash();
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<String> processSingleChunkForUpload({
    required File sourceFile,
    required String outputFilePath,
    required int startOffset,
    required int chunkLength,
    required List<int> dekBytes,
    List<int>? ctrIv,
  }) async {
    final payload = _SingleChunkPayload(
      sourceFilePath: sourceFile.path,
      outputFilePath: outputFilePath,
      startOffset: startOffset,
      chunkLength: chunkLength,
      dekBytes: dekBytes,
      ctrIv: ctrIv,
    );
    return compute(_runSingleChunkEncryptionIsolate, payload);
  }

  static Future<String> _runSingleChunkEncryptionIsolate(_SingleChunkPayload payload) async {
    final engine = EncryptionEngine();
    return engine.encryptSingleChunkToDisk(
      sourceFile: File(payload.sourceFilePath),
      outputFilePath: payload.outputFilePath,
      startOffset: payload.startOffset,
      chunkLength: payload.chunkLength,
      dekBytes: payload.dekBytes,
      ctrIv: payload.ctrIv,
    );
  }

  Future<List<String>> processFileForUpload(File sourceFile, List<int> dekBytes, {List<int>? ctrIv}) async {
    final fileLength = await sourceFile.length();
    const int chunkThreshold = 20 * 1024 * 1024;
    final int? selectedLimit = (fileLength > chunkThreshold) ? chunkThreshold : null;

    final tempDir = await getTemporaryDirectory();
    final outputDir = '${tempDir.path}${Platform.pathSeparator}aerodrive_chunks_${DateTime.now().millisecondsSinceEpoch}';
    await Directory(outputDir).create(recursive: true);

    final payload = EncryptJobPayload(
      sourceFilePath: sourceFile.path,
      outputDirectory: outputDir,
      dekBytes: dekBytes,
      chunkLimit: selectedLimit,
      ctrIv: ctrIv,
    );

    final chunkPaths = await compute(_runEncryptionIsolate, payload);
    return chunkPaths;
  }

  static Future<List<String>> _runEncryptionIsolate(EncryptJobPayload payload) async {
    final engine = EncryptionEngine();
    return engine.encryptStreamToDisk(
      sourceFile: File(payload.sourceFilePath),
      outputDirectory: payload.outputDirectory,
      dekBytes: payload.dekBytes,
      chunkLimit: payload.chunkLimit,
      ctrIv: payload.ctrIv,
    );
  }

  /// Uploads encrypted chunks to Telegram and returns the message responses.
  Future<List<Map<String, dynamic>>> handoffToTelegram(
    TelegramService telegramService,
    int chatId,
    List<String> encryptedChunkPaths, {
    String? caption,
  }) async {
    AppLogger.info('handoffToTelegram: chatId=$chatId chunks=${encryptedChunkPaths.length} caption=${caption != null ? "PRESENT(${caption.length} chars)" : "NULL"}');
    final results = <Map<String, dynamic>>[];
    for (var idx = 0; idx < encryptedChunkPaths.length; idx++) {
      final path = encryptedChunkPaths[idx];
      final file = File(path);
      if (await file.exists()) {
        AppLogger.info('Uploading chunk $idx/${encryptedChunkPaths.length} with captionPresent=${caption != null}');
        final response = await telegramService.uploadDocument(chatId, file.path, caption: caption);
        results.add(response);
      } else {
        AppLogger.error('Chunk file not found at path: $path');
      }
    }
    return results;
  }
}
