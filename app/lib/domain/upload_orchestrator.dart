import 'dart:io';

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

class UploadOrchestrator {
  UploadOrchestrator();

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
