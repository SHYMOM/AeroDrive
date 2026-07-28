import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/logger.dart';
import '../../core/providers.dart';
import '../../core/security/master_key_provider.dart';
import '../../data/crypto/encryption_engine.dart';
import '../../data/db/database.dart';
import '../telegram/telegram_manager.dart';

/// Decrypts a file into memory. Returns null for files > 50MB (use
/// [streamDecryptedFileToDisk] instead) or on failure.
/// Only suitable for small files (text, thumbnails, archives under 50MB).
Future<Uint8List?> loadDecryptedFile(ProviderContainer ref, FileData file) async {
  try {
    final fileSize = file.size ?? 0;
    if (fileSize > 50 * 1024 * 1024) {
      AppLogger.warning('loadDecryptedFile: file ${file.id} is ${fileSize ~/ (1024*1024)} MB, use streamDecryptedFileToDisk instead');
      return null;
    }

    final result = await streamDecryptedFileToDisk(ref, file);
    if (result == null) return null;
    final bytes = await result.readAsBytes();
    try {
      await result.delete();
    } catch (_) {}
    return bytes;
  } catch (e, s) {
    AppLogger.error('Failed to load decrypted file ${file.id}', e, s);
    return null;
  }
}

/// Decrypts a file by streaming each chunk to a temp file on disk.
/// Returns the temp [File] path, or null on failure.
/// Never loads the full decrypted content into memory — bounded by 4MB buffers.
/// Suitable for large files (images, videos, etc.).
Future<File?> streamDecryptedFileToDisk(ProviderContainer ref, FileData file) async {
  try {
    final masterKeyBytes = MasterKeyProvider.instance.key;
    if (masterKeyBytes == null) return null;

    final db = ref.read(databaseProvider);
    final engine = EncryptionEngine();

    final dekResult = await engine.unwrapDek(file.sha256Hash!, masterKeyBytes);
    final dekBytes = dekResult[0];
    if (dekBytes == null) return null;
    final ctrIv = dekResult[1];

    final chunks = await (db.select(db.chunks)
      ..where((c) => c.fileId.equals(file.id))
      ..orderBy([(c) => OrderingTerm.asc(c.chunkIndex)])
    ).get();

    if (chunks.isEmpty) return null;

    final manager = ref.read(telegramManagerProvider.notifier);
    final tempDir = await getTemporaryDirectory();
    final outputFile = File('${tempDir.path}${Platform.pathSeparator}decrypted_${file.id}');
    final outputSink = outputFile.openWrite();
    var processedBytes = 0;

    try {
      for (final chunk in chunks) {
        if (chunk.messageId == null || chunk.channelId == null) continue;

        final telegram = manager.getClient('primary');
        final message = await telegram.getMessage(chunk.channelId!, chunk.messageId!);

        final content = message['content'];
        int? remoteFileId;
        if (content != null && content['@type'] == 'messageDocument') {
          remoteFileId = content['document']['document']['id'] as int?;
        }

        if (remoteFileId == null) {
          AppLogger.warning('No remote file ID for chunk ${chunk.chunkIndex}');
          continue;
        }

        final chunkBytes = await _downloadChunk(telegram, remoteFileId, chunk.size ?? (20 * 1024 * 1024));
        if (chunkBytes.isEmpty) continue;

        final plain = await engine.decryptBytes(
          data: chunkBytes,
          dekBytes: dekBytes,
          ctrIv: ctrIv,
          globalByteOffset: processedBytes,
        );

        outputSink.add(plain);
        processedBytes += plain.length;
      }
    } finally {
      await outputSink.flush();
      await outputSink.close();
    }

    return outputFile;
  } catch (e, s) {
    AppLogger.error('Failed to stream decrypted file ${file.id}', e, s);
    return null;
  }
}

Future<Uint8List> _downloadChunk(dynamic telegram, int fileId, int expectedSize) async {
  final res = await telegram.sendRequest({
    '@type': 'downloadFile',
    'file_id': fileId,
    'priority': 32,
    'synchronous': true,
  });

  final localPath = res['local']['path'] as String?;
  if (localPath == null || localPath.isEmpty) return Uint8List(0);

  final file = File(localPath);
  if (!await file.exists()) return Uint8List(0);

  final bytes = await file.readAsBytes();
  return bytes;
}
