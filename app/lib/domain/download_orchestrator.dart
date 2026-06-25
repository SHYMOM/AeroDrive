import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:aerodrive/data/crypto/encryption_engine.dart';
import 'package:path_provider/path_provider.dart';

class DecryptJobPayload {
  final List<String> sourceEncryptedPaths;
  final String outputFilePath;
  final List<int> dekBytes;

  DecryptJobPayload({
    required this.sourceEncryptedPaths,
    required this.outputFilePath,
    required this.dekBytes,
  });
}

class DownloadOrchestrator {
  final EncryptionEngine _encryptionEngine;

  DownloadOrchestrator(this._encryptionEngine);

  /// Runs the Disk-to-Stream decryption pipeline inside a background Isolate.
  /// This decrypts the files downloaded by TDLib into the OS Downloads folder.
  Future<File> processFileForDownload(List<String> encryptedChunkPaths, String originalFileName, List<int> dekBytes) async {
    Directory? downloadsDir;
    if (Platform.isAndroid || Platform.isIOS) {
      // For mobile, use application documents
      downloadsDir = await getApplicationDocumentsDirectory();
    } else {
      downloadsDir = await getDownloadsDirectory();
    }

    if (downloadsDir == null) {
      downloadsDir = await getApplicationDocumentsDirectory();
    }

    final outputFilePath = '${downloadsDir.path}${Platform.pathSeparator}$originalFileName';
    final payload = DecryptJobPayload(
      sourceEncryptedPaths: encryptedChunkPaths,
      outputFilePath: outputFilePath,
      dekBytes: dekBytes,
    );

    await compute(_runDecryptionIsolate, payload);

    return File(outputFilePath);
  }

  /// The static isolate entrypoint for the decryption job.
  static Future<void> _runDecryptionIsolate(DecryptJobPayload payload) async {
    final engine = EncryptionEngine();
    
    for (int i = 0; i < payload.sourceEncryptedPaths.length; i++) {
      await engine.decryptDiskToStream(
        encryptedChunkFile: File(payload.sourceEncryptedPaths[i]),
        outputFile: File(payload.outputFilePath),
        dekBytes: payload.dekBytes,
        append: i > 0,
      );
    }
  }
}
