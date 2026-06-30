import 'dart:typed_data';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/data/crypto/encryption_engine.dart';
import 'package:aerodrive/core/security/master_key_provider.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/features/telegram/telegram_manager.dart';
import 'package:aerodrive/core/logger.dart';

Future<Uint8List?> loadDecryptedFile(ProviderContainer ref, FileData file) async {
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
    final bytesBuilder = BytesBuilder();
    int processedBytes = 0;

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

      bytesBuilder.add(plain);
      processedBytes += plain.length;
    }

    return bytesBuilder.toBytes();
  } catch (e, s) {
    AppLogger.error('Failed to load decrypted file ${file.id}', e, s);
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
  final data = bytes.sublist(0, expectedSize < bytes.length ? expectedSize : bytes.length);
  return Uint8List.fromList(data);
}
