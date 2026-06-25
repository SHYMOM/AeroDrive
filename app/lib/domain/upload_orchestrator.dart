import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:aerodrive/data/crypto/encryption_engine.dart';
import 'package:aerodrive/features/telegram/telegram_service.dart';
import 'package:path_provider/path_provider.dart';

// Payload for Isolate argument
class EncryptJobPayload {
  final String sourceFilePath;
  final String outputDirectory;
  final List<int> dekBytes;
  final int? chunkLimit;
  final List<int>? ctrIv;

  EncryptJobPayload({
    required this.sourceFilePath,
    required this.outputDirectory,
    required this.dekBytes,
    this.chunkLimit,
    this.ctrIv,
  });
}

class UploadOrchestrator {
  final EncryptionEngine _encryptionEngine;

  UploadOrchestrator(this._encryptionEngine);

  /// Runs the Stream-to-Disk encryption pipeline inside a background Isolate.
  /// This ensures that reading 4MB buffers and running AES-GCM/CTR never blocks the UI.
  Future<List<String>> processFileForUpload(File sourceFile, List<int> dekBytes, {List<int>? ctrIv}) async {
    final fileLength = await sourceFile.length();
    // Split files larger than 20MB into 20MB chunks
    final int chunkThreshold = 20 * 1024 * 1024;
    final int? selectedLimit = (fileLength > chunkThreshold) ? chunkThreshold : null;

    final tempDir = await getTemporaryDirectory();
    final outputDir = '${tempDir.path}/aerodrive_chunks_${DateTime.now().millisecondsSinceEpoch}';
    await Directory(outputDir).create(recursive: true);

    final payload = EncryptJobPayload(
      sourceFilePath: sourceFile.path,
      outputDirectory: outputDir,
      dekBytes: dekBytes,
      chunkLimit: selectedLimit,
      ctrIv: ctrIv,
    );

    // Offload the heavy streaming encryption to a background worker
    final chunkPaths = await compute(_runEncryptionIsolate, payload);

    return chunkPaths;
  }

  /// The static isolate entrypoint for the encryption job.
  static Future<List<String>> _runEncryptionIsolate(EncryptJobPayload payload) async {
    // We instantiate a new engine inside the isolate because isolates don't share memory.
    final engine = EncryptionEngine();
    
    return await engine.encryptStreamToDisk(
      sourceFile: File(payload.sourceFilePath),
      outputDirectory: payload.outputDirectory,
      dekBytes: payload.dekBytes,
      chunkLimit: payload.chunkLimit,
      ctrIv: payload.ctrIv,
    );
  }

  /// Hands off the encrypted temporary chunk to TDLib for upload.
  Future<void> handoffToTelegram(TelegramService telegramService, int chatId, List<String> encryptedChunkPaths, {String? caption}) async {
    for (final path in encryptedChunkPaths) {
      final file = File(path);
      if (await file.exists()) {
        await telegramService.uploadDocument(chatId, file.path, caption: caption);
        // Note: The temporary file will be deleted by UploadQueueService 
        // once it receives updateMessageSendSucceeded from TDLib.
      }
    }
  }
}
