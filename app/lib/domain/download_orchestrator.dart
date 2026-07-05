import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/logger.dart';
import '../data/crypto/encryption_engine.dart';

class DecryptJobPayload {

  DecryptJobPayload({
    required this.sourceEncryptedPaths,
    required this.outputFilePath,
    required this.dekBytes,
    this.ctrIv,
  });
  final List<String> sourceEncryptedPaths;
  final String outputFilePath;
  final List<int> dekBytes;
  final List<int>? ctrIv;
}

class DownloadOrchestrator {
  DownloadOrchestrator();

  /// Determines the correct public download subfolder based on MIME type.
  static String subfolderForMime(String? mimeType) {
    if (mimeType == null) return 'Other';
    if (mimeType.startsWith('image/')) return 'Photos';
    if (mimeType.startsWith('video/')) return 'Videos';
    if (mimeType.startsWith('audio/')) return 'Music';
    if (mimeType.contains('pdf') || mimeType.startsWith('text/') || mimeType.contains('document') || mimeType.contains('msword')) return 'Documents';
    if (mimeType.contains('zip') || mimeType.contains('rar') || mimeType.contains('tar') || mimeType.contains('7z') || mimeType.contains('compress')) return 'Archives';
    return 'Other';
  }

  /// Builds the public download path: Downloads/AeroDrive/{subfolder}/{fileName}
  ///
  /// Bug 5 fix: On Android, `path_provider`'s `getDownloadsDirectory()` returns
  /// the app-internal sandbox (/data/user/0/.../files) NOT the public Downloads
  /// folder visible in the Files app. We hardcode the correct public path instead,
  /// mirroring the already-working approach in backup_service.dart.
  static Future<Directory> ensureDownloadDirectory(String? mimeType) async {
    final subfolder = subfolderForMime(mimeType);
    Directory targetDir;

    if (Platform.isAndroid) {
      // Primary: public Downloads directory (visible in Files/Gallery apps)
      final publicPath = '/storage/emulated/0/Download/AeroDrive/$subfolder';
      targetDir = Directory(publicPath);
      try {
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
          AppLogger.info('Created public download dir: $publicPath');
        }
        return targetDir;
      } catch (e) {
        AppLogger.error('DownloadOrchestrator: public path failed, falling back to app docs', e);
        // Fallback 1: app documents directory
        try {
          final appDocs = await getApplicationDocumentsDirectory();
          targetDir = Directory('${appDocs.path}/AeroDrive/$subfolder');
          if (!await targetDir.exists()) {
            await targetDir.create(recursive: true);
          }
          return targetDir;
        } catch (e2) {
          AppLogger.error('DownloadOrchestrator: app docs failed, using temp', e2);
          // Fallback 2: temp dir (last resort)
          return Directory.systemTemp;
        }
      }
    } else {
      // Desktop/iOS: use path_provider (correct on these platforms)
      try {
        final downloadsDir = await getDownloadsDirectory();
        final base = downloadsDir ?? await getApplicationDocumentsDirectory();
        targetDir = Directory('${base.path}${Platform.pathSeparator}AeroDrive${Platform.pathSeparator}$subfolder');
      } catch (e) {
        AppLogger.error('DownloadOrchestrator: getDownloadsDirectory failed, falling back', e);
        final appDocs = await getApplicationDocumentsDirectory();
        targetDir = Directory('${appDocs.path}${Platform.pathSeparator}AeroDrive${Platform.pathSeparator}$subfolder');
      }
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
        AppLogger.info('Created download directory: ${targetDir.path}');
      }
      return targetDir;
    }
  }

  /// Runs the Disk-to-Stream decryption pipeline inside a background Isolate.
  /// Decrypts files and writes them to the organized public download folder.
  Future<File> processFileForDownload(
    List<String> encryptedChunkPaths,
    String originalFileName,
    List<int> dekBytes, {
    String? outputPath,
    List<int>? ctrIv,
  }) async {
    String finalPath;
    if (outputPath != null) {
      finalPath = outputPath;
    } else {
      final dir = await ensureDownloadDirectory(null);
      finalPath = '${dir.path}${Platform.pathSeparator}$originalFileName';
    }

    AppLogger.info('DownloadOrchestrator: Decrypting to $finalPath');

    final payload = DecryptJobPayload(
      sourceEncryptedPaths: encryptedChunkPaths,
      outputFilePath: finalPath,
      dekBytes: dekBytes,
      ctrIv: ctrIv,
    );

    await compute(_runDecryptionIsolate, payload);

    final result = File(finalPath);
    if (await result.exists()) {
      AppLogger.info('DownloadOrchestrator: Decrypt SUCCESS - ${result.path} (${await result.length()} bytes)');
      // Bug #5 fix: Notify Android MediaScanner so the file appears in Gallery/Files
      await _notifyMediaScanner(result.path);
    } else {
      AppLogger.error('DownloadOrchestrator: Decrypt completed but file not found at $finalPath');
    }
    return result;
  }

  /// Triggers Android MediaScanner to index the downloaded file so it appears
  /// immediately in the Gallery, Files app, and other media-aware apps.
  static Future<void> _notifyMediaScanner(String filePath) async {
    if (!Platform.isAndroid) return;
    try {
      const channel = MethodChannel('com.aerodrive/media_scanner');
      await channel.invokeMethod('scanFile', {'path': filePath});
      AppLogger.info('MediaScanner: notified for $filePath');
    } catch (e) {
      // Non-critical — file is still saved, just might not show in Gallery immediately
      AppLogger.warning('MediaScanner: notification failed (non-critical): $e');
    }
  }

  /// Returns a unique file path, appending (1), (2), etc. if the file already exists.
  static Future<String> dedupFilePath(String basePath) async {
    if (!await File(basePath).exists()) return basePath;

    final lastDot = basePath.lastIndexOf('.');
    final stem = lastDot > 0 ? basePath.substring(0, lastDot) : basePath;
    final ext = lastDot > 0 ? basePath.substring(lastDot) : '';

    for (var i = 1; i < 999; i++) {
      final candidate = '$stem ($i)$ext';
      if (!await File(candidate).exists()) return candidate;
    }
    return basePath; // Extremely unlikely fallback
  }

  /// The static isolate entrypoint for the decryption job.
  static Future<void> _runDecryptionIsolate(DecryptJobPayload payload) async {
    final engine = EncryptionEngine();
    var globalByteOffset = 0;
    
    for (var i = 0; i < payload.sourceEncryptedPaths.length; i++) {
      final encryptedFile = File(payload.sourceEncryptedPaths[i]);
      await engine.decryptDiskToStream(
        encryptedChunkFile: encryptedFile,
        outputFile: File(payload.outputFilePath),
        dekBytes: payload.dekBytes,
        append: i > 0,
        ctrIv: payload.ctrIv,
        globalByteOffset: globalByteOffset,
      );
      
      if (payload.ctrIv != null && await encryptedFile.exists()) {
        globalByteOffset += await encryptedFile.length();
      }
    }
  }
}
