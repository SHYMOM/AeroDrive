import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import '../../core/logger.dart';
import '../../data/crypto/encryption_engine.dart';
import '../../features/telegram/telegram_service.dart';
import '../recovery/manifest_encoder.dart';
import '../../data/db/database.dart';

/// Results from verifying a single verification stage.
enum VerificationResult { passed, failed, skipped }

/// Detailed report of an upload integrity check.
class VerificationReport {
  const VerificationReport({
    required this.fileId,
    required this.chunksChecked,
    required this.chunksPassed,
    required this.manifestResult,
    required this.dekWrappingResult,
    required this.thumbnailResult,
    required this.overallPassed,
    this.details,
  });

  final String fileId;
  final int chunksChecked;
  final int chunksPassed;
  final VerificationResult manifestResult;
  final VerificationResult dekWrappingResult;
  final VerificationResult thumbnailResult;
  final bool overallPassed;
  final String? details;

  bool get isFullyPassed =>
      overallPassed &&
      manifestResult == VerificationResult.passed &&
      dekWrappingResult == VerificationResult.passed;
}

/// Verifies upload integrity after a file has been uploaded to Telegram.
///
/// Checks performed:
/// 1. **Chunk integrity** — Downloads a sample of encrypted chunks and verifies
///    their SHA-256 hash matches what was stored during upload.
/// 2. **Manifest integrity** — Decrypts the chunk caption/manifest and verifies
///    the metadata matches the expected file.
/// 3. **DEK wrapping** — Verifies the Data Encryption Key can be unwrapped and
///    re-wrapped correctly with the Master Key.
/// 4. **Thumbnail** — If a thumbnail was uploaded, verifies it can be decrypted.
class IntegrityVerificationService {
  IntegrityVerificationService();

  final EncryptionEngine _engine = EncryptionEngine();

  /// Runs a full integrity check on an uploaded file.
  ///
  /// [fileId] — UUID of the file in the local DB
  /// [chunks] — List of chunk records from the DB
  /// [masterKey] — The user's 256-bit Master Key bytes
  /// [telegramService] — Connected Telegram service for downloading
  /// [dbFile] — The file record with metadata
  /// [verifyFullDownload] — If true, downloads and decrypts all chunks (slow).
  ///                        If false, only checks a sample (default: 2 chunks).
  Future<VerificationReport> verifyUpload({
    required String fileId,
    required List<ChunkData> chunks,
    required List<int> masterKey,
    required TelegramService telegramService,
    required FileData dbFile,
    bool verifyFullDownload = false,
  }) async {
    if (chunks.isEmpty) {
      return VerificationReport(
        fileId: fileId,
        chunksChecked: 0,
        chunksPassed: 0,
        manifestResult: VerificationResult.skipped,
        dekWrappingResult: VerificationResult.skipped,
        thumbnailResult: VerificationResult.skipped,
        overallPassed: false,
        details: 'No chunks to verify',
      );
    }

    AppLogger.info('IntegrityCheck: Starting verification for file $fileId '
        '(${chunks.length} chunks)');

    // 1. Verify DEK wrapping
    final dekResult = await _verifyDekWrapping(
      dbFile.sha256Hash,
      masterKey,
    );
    AppLogger.info('IntegrityCheck: DEK wrapping -> $dekResult');

    // 2. Verify manifest if present
    final manifestResult = await _verifyManifest(
      chunks.first,
      masterKey,
      fileId,
      telegramService,
    );
    AppLogger.info('IntegrityCheck: Manifest -> $manifestResult');

    // 3. Verify chunk integrity (sample-based)
    final int sampleSize = verifyFullDownload ? chunks.length : _sampleSize(chunks.length);
    final sampledChunks = _sampleChunks(chunks, sampleSize);

    int chunksPassed = 0;
    for (final chunk in sampledChunks) {
      final chunkResult = await _verifyChunkHash(
        chunk,
        telegramService,
      );
      if (chunkResult == VerificationResult.passed) {
        chunksPassed++;
      }
    }
    AppLogger.info('IntegrityCheck: Chunks $chunksPassed/$sampleSize passed');

    // 4. Verify thumbnail if applicable
    final thumbnailResult = await _verifyThumbnail(
      fileId: fileId,
      thumbMessageId: dbFile.thumbnailMessageId,
      thumbChannelId: dbFile.thumbnailChannelId,
      masterKey: masterKey,
      telegramService: telegramService,
    );
    AppLogger.info('IntegrityCheck: Thumbnail -> $thumbnailResult');

    final allPassed =
        chunksPassed == sampleSize &&
        manifestResult == VerificationResult.passed &&
        dekResult == VerificationResult.passed;

    return VerificationReport(
      fileId: fileId,
      chunksChecked: sampleSize,
      chunksPassed: chunksPassed,
      manifestResult: manifestResult,
      dekWrappingResult: dekResult,
      thumbnailResult: thumbnailResult,
      overallPassed: allPassed,
      details: allPassed
          ? 'All integrity checks passed'
          : '${sampleSize - chunksPassed}/$sampleSize chunks, '
              'manifest=$manifestResult, dek=$dekResult, thumb=$thumbnailResult',
    );
  }

  /// Verifies DEK wrapping/unwrapping round-trip.
  Future<VerificationResult> _verifyDekWrapping(
    String? wrappedDekStr,
    List<int> masterKey,
  ) async {
    if (wrappedDekStr == null || wrappedDekStr.isEmpty) {
      return VerificationResult.skipped;
    }

    try {
      // Uses the existing unwrapDek method from EncryptionEngine
      final result = await _engine.unwrapDek(wrappedDekStr, masterKey);
      final dekBytes = result[0];
      final ctrIv = result[1];

      if (dekBytes == null || dekBytes.length != 32) {
        return VerificationResult.failed;
      }

      // Verify we can re-wrap and unwrap again
      final cipher = AesGcm.with256bits();
      final secretKey = await cipher.newSecretKeyFromBytes(masterKey);
      final nonce = cipher.newNonce();
      final secretBox = await cipher.encrypt(
        Uint8List.fromList(dekBytes),
        secretKey: secretKey,
        nonce: nonce,
      );

      final reWrappedDek = await cipher.decrypt(
        SecretBox(secretBox.cipherText, nonce: secretBox.nonce, mac: secretBox.mac),
        secretKey: secretKey,
      );

      if (reWrappedDek.length != 32) {
        return VerificationResult.failed;
      }

      return VerificationResult.passed;
    } catch (e) {
      AppLogger.error('IntegrityCheck: DEK wrapping verification failed', e);
      return VerificationResult.failed;
    }
  }

  /// Verifies that a chunk's manifest caption can be decrypted.
  Future<VerificationResult> _verifyManifest(
    ChunkData chunk,
    List<int> masterKey,
    String expectedFileId,
    TelegramService telegramService,
  ) async {
    if (chunk.channelId == null || chunk.messageId == null) {
      return VerificationResult.skipped;
    }

    try {
      final message = await telegramService.getMessage(
        chunk.channelId!,
        chunk.messageId!,
      );

      final content = message['content'] as Map<String, dynamic>?;
      if (content == null) return VerificationResult.failed;

      final text = content['text'] as Map<String, dynamic>?;
      final caption = text?['text'] as String?;

      if (caption == null || caption.isEmpty) {
        // Some chunks may not have captions (older uploads)
        return VerificationResult.skipped;
      }

      // Try to decrypt the caption as a manifest
      final secretKey = SecretKey(Uint8List.fromList(masterKey));
      final manifest = await ManifestEncoder.decodeManifest(caption, secretKey);

      if (manifest == null) {
        // Could not decrypt — wrong key or corrupted
        return VerificationResult.failed;
      }

      // Verify it references the correct file
      final manifestFileId = manifest['id'] as String?;
      if (manifestFileId != expectedFileId) {
        AppLogger.warning(
          'IntegrityCheck: Manifest fileId mismatch: '
          'expected=$expectedFileId, got=$manifestFileId',
        );
        return VerificationResult.failed;
      }

      return VerificationResult.passed;
    } catch (e) {
      AppLogger.error('IntegrityCheck: Manifest verification failed', e);
      return VerificationResult.failed;
    }
  }

  /// Verifies that an encrypted chunk's SHA-256 hash matches the stored value.
  Future<VerificationResult> _verifyChunkHash(
    ChunkData chunk,
    TelegramService telegramService,
  ) async {
    if (chunk.channelId == null || chunk.messageId == null) {
      return VerificationResult.skipped;
    }

    if (chunk.hash == null || chunk.hash!.isEmpty) {
      // Hash wasn't stored during upload — can't verify
      return VerificationResult.skipped;
    }

    try {
      // First, get the message to find the file ID
      final message = await telegramService.getMessage(
        chunk.channelId!,
        chunk.messageId!,
      );

      // Extract the document's TDLib file ID
      final content = message['content'] as Map<String, dynamic>?;
      if (content == null || content['@type'] != 'messageDocument') {
        return VerificationResult.failed;
      }

      final document = content['document'] as Map<String, dynamic>?;
      final fileObj = document?['document'] as Map<String, dynamic>?;
      final remoteFileId = fileObj?['id'] as int?;

      if (remoteFileId == null) {
        return VerificationResult.failed;
      }

      // Trigger download
      await telegramService.downloadFile(remoteFileId);

      // Poll for completion
      String? localPath;
      for (var i = 0; i < 30; i++) {
        await Future.delayed(const Duration(seconds: 1));
        try {
          final fileInfo = await telegramService.sendRequest({
            '@type': 'getFile',
            'file_id': remoteFileId,
          });
          final local = fileInfo['local'] as Map<String, dynamic>?;
          if (local != null && local['is_downloading_completed'] == true) {
            localPath = local['path'] as String?;
            break;
          }
        } catch (_) {
          continue;
        }
      }

      if (localPath == null || localPath!.isEmpty) {
        return VerificationResult.failed;
      }

      // Compute SHA-256 of downloaded file
      final downloadedFile = File(localPath!);
      if (!await downloadedFile.exists()) {
        return VerificationResult.failed;
      }

      final hash = await _hashFile(downloadedFile);

      if (hash == chunk.hash) {
        return VerificationResult.passed;
      } else {
        AppLogger.error(
          'IntegrityCheck: Chunk hash mismatch for chunk ${chunk.chunkIndex}. '
          'Expected: ${chunk.hash}, Got: $hash',
        );
        return VerificationResult.failed;
      }
    } catch (e) {
      AppLogger.error(
        'IntegrityCheck: Chunk verification failed for chunk ${chunk.chunkIndex}',
        e,
      );
      return VerificationResult.failed;
    }
  }

  /// Verifies thumbnail decryption.
  Future<VerificationResult> _verifyThumbnail({
    required String fileId,
    required int? thumbMessageId,
    required int? thumbChannelId,
    required List<int> masterKey,
    required TelegramService telegramService,
  }) async {
    if (thumbMessageId == null || thumbChannelId == null) {
      return VerificationResult.skipped;
    }

    try {
      final message = await telegramService.getMessage(
        thumbChannelId,
        thumbMessageId,
      );

      // Extract document file ID
      final content = message['content'] as Map<String, dynamic>?;
      if (content == null || content['@type'] != 'messageDocument') {
        return VerificationResult.failed;
      }

      final document = content['document'] as Map<String, dynamic>?;
      final fileObj = document?['document'] as Map<String, dynamic>?;
      final remoteFileId = fileObj?['id'] as int?;

      if (remoteFileId == null) return VerificationResult.failed;

      // Trigger download
      await telegramService.downloadFile(remoteFileId);

      // Poll for completion
      String? localPath;
      for (var i = 0; i < 30; i++) {
        await Future.delayed(const Duration(seconds: 1));
        try {
          final fileInfo = await telegramService.sendRequest({
            '@type': 'getFile',
            'file_id': remoteFileId,
          });
          final local = fileInfo['local'] as Map<String, dynamic>?;
          if (local != null && local['is_downloading_completed'] == true) {
            localPath = local['path'] as String?;
            break;
          }
        } catch (_) {
          continue;
        }
      }

      if (localPath == null || localPath!.isEmpty) {
        return VerificationResult.failed;
      }

      // Try to decrypt the thumbnail
      final thumbFile = File(localPath!);
      final thumbBytes = await thumbFile.readAsBytes();

      if (thumbBytes.length < 28) {
        return VerificationResult.failed; // Too small to contain valid encrypted data
      }

      // Attempt AES-256-GCM decryption
      final nonce = thumbBytes.sublist(0, 12);
      final macBytes = thumbBytes.sublist(thumbBytes.length - 16);
      final cipherText = thumbBytes.sublist(12, thumbBytes.length - 16);

      final cipher = AesGcm.with256bits();
      final secretKey = await cipher.newSecretKeyFromBytes(masterKey);

      try {
        await cipher.decrypt(
          SecretBox(
            Uint8List.fromList(cipherText),
            nonce: Uint8List.fromList(nonce),
            mac: Mac(Uint8List.fromList(macBytes)),
          ),
          secretKey: secretKey,
        );
        return VerificationResult.passed;
      } catch (e) {
        // Decryption failed — corrupt thumbnail or wrong key
        return VerificationResult.failed;
      }
    } catch (e) {
      AppLogger.error('IntegrityCheck: Thumbnail verification failed', e);
      return VerificationResult.failed;
    }
  }

  /// Computes SHA-256 hash of a file using streaming reads (4MB buffer).
  Future<String> _hashFile(File file) async {
    final sink = _DigestSink();
    final input = crypto.sha256.startChunkedConversion(sink);
    final openFile = await file.open();
    try {
      const int bufferSize = 4 * 1024 * 1024;
      final length = await openFile.length();
      var offset = 0;
      while (offset < length) {
        final toRead = (length - offset < bufferSize) ? length - offset : bufferSize;
        final block = await openFile.read(toRead);
        input.add(block);
        offset += toRead;
      }
    } finally {
      await openFile.close();
    }
    input.close();
    return sink.value.toString();
  }

  /// Determines sample size based on total chunks.
  int _sampleSize(int totalChunks) {
    if (totalChunks <= 3) return totalChunks;
    // Sample sqrt of total, min 2, max 10
    final sample = (totalChunks * 0.1).ceil();
    return sample.clamp(2, 10);
  }

  /// Picks a representative sample of chunks (first, last, and evenly spaced).
  List<ChunkData> _sampleChunks(List<ChunkData> chunks, int sampleSize) {
    if (chunks.length <= sampleSize) return chunks;

    final sampled = <ChunkData>[];
    // Always include first and last
    sampled.add(chunks.first);
    if (sampleSize > 1) {
      final step = (chunks.length - 2) / (sampleSize - 1);
      for (var i = 1; i < sampleSize - 1; i++) {
        final index = 1 + (step * i).round();
        sampled.add(chunks[index.clamp(1, chunks.length - 2)]);
      }
      sampled.add(chunks.last);
    }
    return sampled;
  }
}

class _DigestSink implements Sink<crypto.Digest> {
  late crypto.Digest value;
  @override
  void add(crypto.Digest data) => value = data;
  @override
  void close() {}
}
