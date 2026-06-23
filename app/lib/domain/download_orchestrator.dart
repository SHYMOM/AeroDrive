import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:aerodrive/data/crypto/encryption_engine.dart';
import 'package:path_provider/path_provider.dart';

class DecryptJobPayload {
  final String sourceEncryptedPath;
  final String outputFilePath;
  final List<int> dekBytes;

  DecryptJobPayload({
    required this.sourceEncryptedPath,
    required this.outputFilePath,
    required this.dekBytes,
  });
}

class DownloadOrchestrator {
  final EncryptionEngine _encryptionEngine;

  DownloadOrchestrator(this._encryptionEngine);

  /// Runs the Disk-to-Stream decryption pipeline inside a background Isolate.
  /// This decrypts the file downloaded by TDLib into the OS Downloads folder.
  Future<File> processFileForDownload(File encryptedChunk, String originalFileName, List<int> dekBytes) async {
    Directory? downloadsDir;
    if (Platform.isAndroid || Platform.isIOS) {
      // For mobile, maybe use external storage or app documents
      // We'll use application documents for now to avoid broad storage permissions
      downloadsDir = await getApplicationDocumentsDirectory();
    } else {
      downloadsDir = await getDownloadsDirectory();
    }

    if (downloadsDir == null) {
      downloadsDir = await getApplicationDocumentsDirectory();
    }

    final outputFilePath = '${downloadsDir.path}${Platform.pathSeparator}$originalFileName';
    final payload = DecryptJobPayload(
      sourceEncryptedPath: encryptedChunk.path,
      outputFilePath: outputFilePath,
      dekBytes: dekBytes,
    );

    await compute(_runDecryptionIsolate, payload);

    return File(outputFilePath);
  }

  /// The static isolate entrypoint for the decryption job.
  static Future<void> _runDecryptionIsolate(DecryptJobPayload payload) async {
    final engine = EncryptionEngine();
    
    await engine.decryptDiskToStream(
      encryptedChunkFile: File(payload.sourceEncryptedPath),
      outputFile: File(payload.outputFilePath),
      dekBytes: payload.dekBytes,
    );
  }
}
