import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' as drift;
import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/logger.dart';
import '../core/providers/security_providers.dart';
import '../data/db/database.dart';
import '../data/repositories/settings_repository.dart';
import '../features/media/media_screen.dart';
import '../features/ml/ml_service.dart';
import '../features/places/places_service.dart';
import '../features/telegram/telegram_manager.dart';
import '../features/telegram/telegram_service.dart';
import 'channel_load_balancer.dart';
import 'notification_service.dart';
import 'recovery/manifest_encoder.dart';
import 'smart_analyzer.dart';
import 'thumbnail_cache_manager.dart';
import 'upload_crash_debugger.dart';
import 'upload_orchestrator.dart';
import 'video_thumbnail_service.dart';

class ActiveUploadInfo {
  ActiveUploadInfo({
    required this.queueId,
    required this.fileId,
    required this.chunkIndex,
    required this.totalChunks,
    required this.chatId,
    required this.messageId,
    required this.fileName,
  });
  final String queueId;
  final String fileId;
  final int chunkIndex;
  final int totalChunks;
  final int chatId;
  final int messageId;
  final String fileName;
}

/// Payload for the isolate-based thumbnail extraction.
class _ThumbnailPayload {
  const _ThumbnailPayload(this.filePath, this.maxDimension);
  final String filePath;
  final int maxDimension;
}

/// Runs in a background isolate. Loads and resizes image, returns JPEG bytes.
/// Returns null on failure (unsupported format, OOM, etc).
/// Bug #3 fix: Skip thumbnail generation for files > 50 MB to prevent OOM.
Future<Uint8List?> _extractImageThumbnailIsolate(_ThumbnailPayload payload) async {
  try {
    final file = File(payload.filePath);
    final fileSize = file.lengthSync();

    // Bug #3 fix: guard against loading huge files into RAM for thumbnailing
    const maxThumbnailSourceSize = 50 * 1024 * 1024; // 50 MB
    if (fileSize > maxThumbnailSourceSize) {
      return null; // Skip thumbnail for very large files
    }

    // img.decodeImageFile is synchronous in the image package — no await needed.
    // We wrap the whole thing in a try/catch to handle unsupported formats.
    final image = img.decodeJpg(file.readAsBytesSync());
    if (image == null) {
      // Try generic decoder for non-JPEG files
      final bytes = file.readAsBytesSync();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final resized = img.copyResize(decoded, width: payload.maxDimension);
      return Uint8List.fromList(img.encodeJpg(resized, quality: 70));
    }
    final resized = img.copyResize(image, width: payload.maxDimension);
    return Uint8List.fromList(img.encodeJpg(resized, quality: 70));
  } catch (_) {
    return null;
  }
}

class UploadQueueService {

  UploadQueueService(this._ref, this._db, this._settings, this._telegramManager, this._orchestrator) {
    _resetInterruptedTransfers();
    _sanitizeChunksDatabase();
    _startPolling();
    _listenToTdlibEvents();
    _startConfirmationWatcher();
  }
  final ProviderRef _ref;
  final AeroDriveDatabase _db;
  final SettingsRepository _settings;
  final TelegramManager _telegramManager;
  final UploadOrchestrator _orchestrator;

  Timer? _pollingTimer;
  StreamSubscription? _tdlibSub;
  Timer? _confirmationWatcher;

  // Bug 4 fix: replace single bool with a set of active queue IDs so we can
  // process multiple uploads concurrently instead of blocking on a global flag.
  final Set<String> _processingIds = {};
  static const int _maxConcurrent = 2; // respects parallel_threads setting, safe default for mobile
  final Map<String, String> _fileAbortReasons = {};

  final _uuid = const Uuid();

  // Maps TDLib file_id -> ActiveUploadInfo for progress tracking
  final Map<int, ActiveUploadInfo> _uploadFileIdMap = {};

  // Phase 3: Round-robin index for distributing thumbnail uploads across accounts
  int _thumbnailClientIndex = 0;

  // Maps "messageId:chatId" -> ActiveUploadInfo for completion tracking
  final Map<String, ActiveUploadInfo> _uploadMessageMap = {};

  // Track chunk upload progress: fileId -> {chunkIndex: bytesUploaded}
  final Map<String, Map<int, int>> _uploadProgress = {};

  // ── Chunk confirmation recovery ──
  // Tracks file IDs where all chunks uploaded to Telegram but confirmation
  // (updateMessageSendSucceeded) hasn't arrived for all chunks yet.
  final Set<String> _pendingFinalization = {};

  // Tracks file IDs where an upload chunk failed or was aborted to cancel remaining tasks
  final Set<String> _abortedFileIds = {};

  // Tracks when each file's chunks were all sent (for timeout detection).
  final Map<String, DateTime> _allChunksSentAt = {};

  // Maps fileId -> {chunkIndex: Completer<void>} to gate in-flight chunk concurrency
  final Map<String, Map<int, Completer<void>>> _chunkUploadedCompleters = {};

  // Tracks confirmed chunk indices for each fileId (set in updateMessageSendSucceeded)
  final Map<String, Set<int>> _confirmedChunksPerFile = {};

  // Maps fileId -> active temp upload directory for cleanup
  final Map<String, Directory> _activeUploadDirs = {};

  // ── Confirmation timeout ──
  // If updateMessageSendSucceeded hasn't arrived for all chunks within this
  // duration after the last chunk was sent, we try to finalize from the DB.
  static const Duration _confirmationTimeout = Duration(minutes: 5);

  String _getMimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'mp4':
        return 'video/mp4';
      case 'mkv':
        return 'video/x-matroska';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'webm':
        return 'video/webm';
      case 'flv':
        return 'video/x-flv';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
        return 'audio/ogg';
      case 'm4a':
        return 'audio/mp4';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
      case 'docx':
        return 'application/msword';
      case 'xls':
      case 'xlsx':
        return 'application/vnd.ms-excel';
      case 'ppt':
      case 'pptx':
        return 'application/vnd.ms-powerpoint';
      case 'txt':
        return 'text/plain';
      case 'html':
      case 'htm':
        return 'text/html';
      case 'json':
        return 'application/json';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }

  Future<String> _calculateFileHash(File file) async {
    return UploadOrchestrator.computeFileHash(file);
  }


  /// Periodically checks if all chunks for a file are in the chunks table
  /// and triggers finalization if the confirmation timeout has elapsed.
  void _startConfirmationWatcher() {
    _confirmationWatcher = Timer.periodic(const Duration(seconds: 30), (_) async {
      final now = DateTime.now();
      final timedOut = <String>[];
      for (final entry in _allChunksSentAt.entries) {
        if (now.difference(entry.value) > _confirmationTimeout) {
          timedOut.add(entry.key);
        }
      }

      for (final fileId in timedOut) {
        _allChunksSentAt.remove(fileId);
        _pendingFinalization.remove(fileId);
        AppLogger.warning('Confirmation timeout for file $fileId — attempting recovery finalization');

        try {
          // Check if all chunks are in the DB
          final chunks = await (_db.select(_db.chunks)..where((c) => c.fileId.equals(fileId))).get();
          // Find the queue info from any remaining uploadMessageMap entry
          final queueId = _uploadMessageMap.values
              .where((v) => v.fileId == fileId)
              .map((v) => v.queueId)
              .toSet()
              .firstOrNull;

          if (queueId != null) {
            final item = await (_db.select(_db.transferQueue)..where((q) => q.id.equals(queueId))).getSingleOrNull();
            if (item != null) {
              final originalFileId = item.fileId;
              final fileName = originalFileId?.split('|').firstOrNull
                  ?.split(RegExp(r'[\\/]')).last ?? 'Unknown';

              // Try to get totalChunks from the file record (inserted during processQueueItem)
              final fileRecord = await (_db.select(_db.files)..where((f) => f.id.equals(fileId))).getSingleOrNull();
              final totalChunks = fileRecord?.totalChunks ?? chunks.length;

              final confirmedChunks = chunks.where((c) => c.messageId != null && c.messageId! > 0).toList();
              final confirmedIndicesInDb = confirmedChunks.map((c) => c.chunkIndex).whereType<int>().toSet();
              final allIndicesConfirmed = totalChunks > 0 &&
                  List.generate(totalChunks, (i) => i).every((idx) => confirmedIndicesInDb.contains(idx));

              if (totalChunks > 0 && chunks.length >= totalChunks && confirmedChunks.length >= totalChunks && allIndicesConfirmed && !_abortedFileIds.contains(fileId)) {
                AppLogger.info('Recovery: All $totalChunks chunks confirmed in DB with real message IDs, finalizing file $fileId');
                // Register a synthetic entry so _finalizeUpload can find it
                final lastChunk = confirmedChunks.last;
                final syntheticKey = '${lastChunk.messageId}:${lastChunk.channelId}';
                _uploadMessageMap[syntheticKey] = ActiveUploadInfo(
                  queueId: queueId,
                  fileId: fileId,
                  chunkIndex: lastChunk.chunkIndex ?? 0,
                  totalChunks: totalChunks,
                  chatId: lastChunk.channelId ?? 0,
                  messageId: lastChunk.messageId ?? 0,
                  fileName: fileName,
                );
                await _finalizeUpload(syntheticKey, null);
              } else {
                AppLogger.warning('Recovery: Only ${confirmedChunks.length}/$totalChunks confirmed chunks found for file $fileId, marking as failed');
                await (_db.update(_db.transferQueue)..where((q) => q.id.equals(queueId)))
                    .write(const TransferQueueCompanion(
                  status: drift.Value('FAILED'),
                  errorMessage: drift.Value('Chunks not confirmed by Telegram after multiple retries'),
                ));
                _uploadProgress.remove(fileId);
                _confirmedChunksPerFile.remove(fileId);
                _uploadFileIdMap.removeWhere((_, v) => v.queueId == queueId);
                _uploadMessageMap.removeWhere((_, v) => v.queueId == queueId);
                _abortedFileIds.add(fileId);

                // Clean up orphaned DB records
                try {
                  await (_db.delete(_db.chunks)..where((c) => c.fileId.equals(fileId))).go();
                  await (_db.delete(_db.files)..where((f) => f.id.equals(fileId))).go();
                } catch (_) {}
              }
            }
          }
        } catch (e) {
          AppLogger.error('Confirmation recovery failed for file $fileId', e);
        }
      }
    });
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_telegramManager.readyClients.isEmpty) return;

      // Determine how many concurrent slots are available
      final maxConcurrent = int.tryParse(
        await _settings.getSetting('parallel_threads') ?? '$_maxConcurrent',
      ) ?? _maxConcurrent;

      final available = maxConcurrent - _processingIds.length;
      if (available <= 0) return;

      // Fetch up to [available] pending items
      final pendingItems = await (_db.select(_db.transferQueue)
        ..where((q) => q.status.equals('PENDING'))
        ..where((q) => q.type.equals('UPLOAD_FILE'))
        ..orderBy([(q) => drift.OrderingTerm.asc(q.createdAt)])
        ..limit(available)
      ).get();

      if (pendingItems.isEmpty) return;

      // Dispatch each item with a stagger to prevent simultaneous TDLib/isolate spikes
      for (final item in pendingItems) {
        if (_processingIds.contains(item.id)) continue;
        _processingIds.add(item.id);
        _processQueueItem(item).catchError((e) {
          AppLogger.error('UploadQueue Error for ${item.id}', e);
        }).whenComplete(() {
          _processingIds.remove(item.id);
        });
        // Stagger dispatch by 350ms to prevent flood/rate-limit and CPU spike
        await Future.delayed(const Duration(milliseconds: 350));
      }
    });
  }

  Future<void> _resetInterruptedTransfers() async {
    try {
      final resetCount = await (_db.update(_db.transferQueue)
        ..where((q) => q.type.equals('UPLOAD_FILE') & 
            (q.status.equals('PROCESSING') | q.status.equals('ENCRYPTING')))
      ).write(const TransferQueueCompanion(
        status: drift.Value('PENDING'),
      ));
      if (resetCount > 0) {
        AppLogger.info('UploadQueueService: Reset $resetCount interrupted upload(s) to PENDING');
      }
    } catch (e) {
      AppLogger.error('Failed to reset interrupted uploads', e);
    }
  }

  /// Deduplicates any duplicate chunk entries and repairs chunk sizes in the SQLite database.
  Future<void> _sanitizeChunksDatabase() async {
    try {
      final allChunks = await _db.select(_db.chunks).get();
      final seen = <String, ChunkData>{};
      final toDelete = <String>[];

      for (final chunk in allChunks) {
        final key = '${chunk.fileId}:${chunk.chunkIndex}';
        if (seen.containsKey(key)) {
          final existing = seen[key]!;
          if ((existing.messageId == null || existing.messageId! <= 0) &&
              (chunk.messageId != null && chunk.messageId! > 0)) {
            toDelete.add(existing.id);
            seen[key] = chunk;
          } else {
            toDelete.add(chunk.id);
          }
        } else {
          seen[key] = chunk;
        }
      }

      if (toDelete.isNotEmpty) {
        await (_db.delete(_db.chunks)..where((c) => c.id.isIn(toDelete))).go();
        AppLogger.info('Sanitized database: removed ${toDelete.length} duplicate chunk rows');
      }

      // Fix corrupt chunk size where chunk.size >= file.size on multi-chunk files
      final multiChunkFiles = await (_db.select(_db.files)
        ..where((f) => f.totalChunks.isBiggerThanValue(1))
      ).get();

      for (final file in multiChunkFiles) {
        final fileSize = file.size ?? 0;
        if (fileSize <= 0) continue;
        final totalChunks = file.totalChunks;
        final optimalSize = UploadOrchestrator.getOptimalChunkSize(fileSize);

        final fileChunks = await (_db.select(_db.chunks)..where((c) => c.fileId.equals(file.id))).get();
        for (final chunk in fileChunks) {
          if (chunk.size != null && chunk.size! >= fileSize) {
            final idx = chunk.chunkIndex ?? 0;
            final isLast = idx == totalChunks - 1;
            final trueSize = isLast ? (fileSize - idx * optimalSize) : optimalSize;
            await (_db.update(_db.chunks)..where((c) => c.id.equals(chunk.id)))
                .write(ChunksCompanion(size: drift.Value(trueSize)));
          }
        }
      }
    } catch (e) {
      AppLogger.warning('Database chunk sanitization error: $e');
    }
  }

  void _listenToTdlibEvents() {
    _tdlibSub = _telegramManager.allEvents.listen((event) async {
      final type = event['@type'];

      if (type == 'updateMessageSendSucceeded') {
        final message = event['message'];
        if (message != null) {
          final msgId = message['id'] as int?;
          final chatId = message['chat_id'] as int?;
          if (msgId == null || chatId == null) return;
          final oldMsgId = event['old_message_id'] as int?;

          // Try matching with old_message_id first (correct approach for TDLib)
          String? matchKey;
          if (oldMsgId != null) {
            matchKey = '$oldMsgId:$chatId';
            if (!_uploadMessageMap.containsKey(matchKey)) {
              matchKey = null;
            }
          }

          // Fallback: try the new message ID
          if (matchKey == null) {
            final newKey = '$msgId:$chatId';
            if (_uploadMessageMap.containsKey(newKey)) {
              matchKey = newKey;
            }
          }

          if (matchKey != null) {
            final info = _uploadMessageMap[matchKey]!;

            // Record that this chunk index is confirmed by Telegram server
            _confirmedChunksPerFile.putIfAbsent(info.fileId, () => {}).add(info.chunkIndex);

            // Update the chunk record with the REAL message ID from Telegram
            await (_db.update(_db.chunks)
              ..where((c) => c.fileId.equals(info.fileId))
              ..where((c) => c.chunkIndex.equals(info.chunkIndex))
            ).write(ChunksCompanion(
              messageId: drift.Value(msgId),
            ));

            // Re-key the info with the real message ID
            _uploadMessageMap.remove(matchKey);
            final newKey = '$msgId:$chatId';
            _uploadMessageMap[newKey] = info;

            // Signal chunk upload completed to unblock sliding window
            final c = _chunkUploadedCompleters[info.fileId]?[info.chunkIndex];
            if (c != null && !c.isCompleted) {
              c.complete();
            }

            await _finalizeUpload(newKey, message);
          } else {
            AppLogger.info('updateMessageSendSucceeded received but no matching upload found for msgId=$msgId chatId=$chatId');
          }
        }
      } else if (type == 'updateMessageSendFailed') {
        final message = event['message'];
        if (message != null) {
          final msgId = message['id'] as int?;
          final chatId = message['chat_id'] as int?;
          if (msgId == null || chatId == null) return;

          final oldMsgId = event['old_message_id'] as int?;
          final errorCode = event['error_code'];
          final errorMsg = event['error_message'];
          final reason = (errorMsg != null && errorMsg.toString().isNotEmpty)
              ? 'Telegram rejected upload: [$errorCode] $errorMsg'
              : 'Telegram rejected the upload.';
          AppLogger.error('TDLib updateMessageSendFailed: msgId=$msgId chatId=$chatId code=$errorCode msg=$errorMsg');

          String? matchKey;
          if (oldMsgId != null) {
            matchKey = '$oldMsgId:$chatId';
            if (!_uploadMessageMap.containsKey(matchKey)) {
              matchKey = null;
            }
          }
          if (matchKey == null) {
            final newKey = '$msgId:$chatId';
            if (_uploadMessageMap.containsKey(newKey)) {
              matchKey = newKey;
            }
          }

          if (matchKey != null) {
            final info = _uploadMessageMap[matchKey]!;
            _fileAbortReasons[info.fileId] = reason;
            await (_db.update(_db.transferQueue)
              ..where((q) => q.id.equals(info.queueId)))
              .write(TransferQueueCompanion(
                status: const drift.Value('FAILED'),
                errorMessage: drift.Value(reason),
              ));

            NotificationService.instance.showUploadFailed(
              NotificationService.instance.getSafeNotificationId(info.queueId),
              info.fileName,
              reason,
            );
            _uploadMessageMap.remove(matchKey);
            _uploadFileIdMap.removeWhere((_, v) => v.queueId == info.queueId);
            _uploadProgress.remove(info.fileId);
            _pendingFinalization.remove(info.fileId);
            _allChunksSentAt.remove(info.fileId);
            _abortedFileIds.add(info.fileId);

            final c = _chunkUploadedCompleters[info.fileId]?[info.chunkIndex];
            if (c != null && !c.isCompleted) {
              c.completeError(Exception(reason));
            }

            // Clean up orphaned DB records (file + chunks) so incomplete uploads don't persist
            try {
              await (_db.delete(_db.chunks)..where((c) => c.fileId.equals(info.fileId))).go();
              await (_db.delete(_db.files)..where((f) => f.id.equals(info.fileId))).go();
              AppLogger.info('Cleaned up orphaned DB records for updateMessageSendFailed fileId=${info.fileId}');
            } catch (cleanupErr) {
              AppLogger.warning('Failed to clean up orphaned records on send failure: $cleanupErr');
            }
          }
        }
      } else if (type == 'updateFile') {
        final file = event['file'];
        if (file != null) {
          final fileId = file['id'] as int?;
          if (fileId != null && _uploadFileIdMap.containsKey(fileId)) {
            final info = _uploadFileIdMap[fileId]!;
            final remote = file['remote'] as Map<String, dynamic>?;
            if (remote == null) return;

            // Use remote.uploaded_size for upload progress (TDLib field)
            final uploadedSize = remote['uploaded_size'] as int? ?? 0;
            final expectedSize = file['expected_size'] as int? ?? file['size'] as int? ?? 0;
            final isUploadCompleted = remote['is_uploading_completed'] == true;

            _uploadProgress.putIfAbsent(info.fileId, () => {})[info.chunkIndex] = uploadedSize;

            final chunkProgress = _uploadProgress[info.fileId]!;
            final totalUploaded = chunkProgress.values.fold<int>(0, (a, b) => a + b);
            final totalFileBytes = await _getTotalFileBytes(info.queueId);

            await (_db.update(_db.transferQueue)..where((q) => q.id.equals(info.queueId)))
              .write(TransferQueueCompanion(
                bytesTransferred: drift.Value(totalUploaded),
                totalBytes: drift.Value(totalFileBytes),
              ));

            if (totalFileBytes > 0) {
              NotificationService.instance.showUploadProgress(
                NotificationService.instance.getSafeNotificationId(info.queueId),
                info.fileName,
                totalUploaded,
                totalFileBytes,
              );
            }

            // Detect upload completion from updateFile
            if (isUploadCompleted || (expectedSize > 0 && uploadedSize >= expectedSize)) {
              AppLogger.info('Upload completed via updateFile for file $fileId');

              // Update progress to 100%
              final uploadTotal = chunkProgress.values.fold<int>(0, (a, b) => a + b);
              await (_db.update(_db.transferQueue)..where((q) => q.id.equals(info.queueId)))
                .write(TransferQueueCompanion(
                  bytesTransferred: drift.Value(uploadTotal),
                ));

              // Note: Do NOT complete chunkCompleter or remove from tracking maps here.
              // Wait for updateMessageSendSucceeded to ensure Telegram server acknowledges
              // the message and TDLib is completely done with the chunk file.
            }
          }
        }
      }
    });
  }

  Future<int> _getTotalFileBytes(String queueId) async {
    try {
      final item = await (_db.select(_db.transferQueue)..where((q) => q.id.equals(queueId))).getSingleOrNull();
      if (item != null && item.totalBytes != null) return item.totalBytes!;
    } catch (e) {
      AppLogger.error('UploadQueue: failed to get total bytes for $queueId', e);
    }
    return 0;
  }

  Future<void> _uploadThumbnailManifest({
    required String fileId,
    required Uint8List encryptedThumbBytes,
    required List<int> masterKey,
    required int channelId,
  }) async {
    try {
      final cipher = AesGcm.with256bits();
      final secretKey = await cipher.newSecretKeyFromBytes(masterKey);

      final manifestData = {
        't': 'thumb',
        'fid': fileId,
      };

      final jsonStr = jsonEncode(manifestData);
      final jsonBytes = utf8.encode(jsonStr);

      final nonce = cipher.newNonce();
      final secretBox = await cipher.encrypt(
        jsonBytes,
        secretKey: secretKey,
        nonce: nonce,
      );

      final ctBase64 = base64Encode(secretBox.cipherText);
      final nonceBase64 = base64Encode(secretBox.nonce);
      final macBase64 = base64Encode(secretBox.mac.bytes);
      final finalCaption = 'aero:$ctBase64:$nonceBase64:$macBase64';

      final dir = await getTemporaryDirectory();
      final tempFile = File('${dir.path}${Platform.pathSeparator}thumb_$fileId.tmp');
      await tempFile.writeAsBytes(encryptedThumbBytes);

      final readyClients = _telegramManager.readyClients;
      if (readyClients.isEmpty) return;
      final client = readyClients.first;

      await _orchestrator.handoffToTelegram(
        client,
        channelId,
        [tempFile.path],
        caption: finalCaption,
      );

      // We don't delete tempFile immediately since handoffToTelegram is async and might need it.
      // It will be cleaned up by OS temp directory cleaner or can be safely ignored for small thumbnails.
    } catch (e) {
      AppLogger.error('UploadQueue: Failed to upload thumbnail manifest for $fileId', e);
    }
  }

  Future<void> _processQueueItem(TransferQueueData item) async {
    final storageChannels = await ChannelLoadBalancer.getStorageChannels(_settings);
    if (storageChannels.isEmpty) {
      await (_db.update(_db.transferQueue)..where((q) => q.id.equals(item.id)))
        .write(const TransferQueueCompanion(status: drift.Value('FAILED'), errorMessage: drift.Value('No Storage Channels available.')));
      return;
    }

    final fileBaseIndex = await ChannelLoadBalancer.selectFileBaseIndex(
      settings: _settings,
      channelCount: storageChannels.length,
      fileSize: item.totalBytes,
    );

    await (_db.update(_db.transferQueue)..where((q) => q.id.equals(item.id)))
      .write(const TransferQueueCompanion(status: drift.Value('PROCESSING')));

    final parts = item.fileId?.split('|');
    if (parts == null || parts.length < 2) {
      await (_db.update(_db.transferQueue)..where((q) => q.id.equals(item.id)))
        .write(const TransferQueueCompanion(status: drift.Value('FAILED'), errorMessage: drift.Value('Invalid path data.')));
      return;
    }

    final localFilePath = parts[0];
    // Bug 4 fix: treat empty string and literal "null" both as SQL NULL
    final rawFolderId = parts.length > 1 ? parts[1] : '';
    final targetFolderId = (rawFolderId.isEmpty || rawFolderId == 'null') ? null : rawFolderId;

    final sourceFile = File(localFilePath);
    if (!await sourceFile.exists()) {
      await (_db.update(_db.transferQueue)..where((q) => q.id.equals(item.id)))
        .write(const TransferQueueCompanion(status: drift.Value('FAILED'), errorMessage: drift.Value('File not found on disk.')));
      return;
    }

    final fileLength = await sourceFile.length();
    await (_db.update(_db.transferQueue)..where((q) => q.id.equals(item.id)))
        .write(TransferQueueCompanion(totalBytes: drift.Value(fileLength)));
    final fileName = sourceFile.path.contains('/') ? sourceFile.path.split('/').last : sourceFile.path.split('\\').last;
    final mimeType = _getMimeType(fileName);
    final isStreamable = mimeType.startsWith('video/') || mimeType.startsWith('audio/');

    final random = Random.secure();
    final dekBytes = List<int>.generate(32, (_) => random.nextInt(256));
    final encryptionNonce = List<int>.generate(12, (_) => random.nextInt(256));
    final encryptionAlgo = isStreamable ? 'AES-256-CTR' : 'AES-256-GCM';

    List<int>? ctrIv;
    if (isStreamable) {
      ctrIv = List<int>.generate(16, (_) => random.nextInt(256));
    }

    final chunkSize = UploadOrchestrator.getOptimalChunkSize(fileLength);
    final totalChunks = (fileLength <= chunkSize) ? 1 : ((fileLength + chunkSize - 1) ~/ chunkSize);

    final hashStr = await UploadOrchestrator.computeFileHash(sourceFile);

    final masterKey = _ref.read(masterKeyProvider);
    final fileId = _uuid.v4();

    final tempBaseDir = await getTemporaryDirectory();
    final uploadDir = Directory('${tempBaseDir.path}${Platform.pathSeparator}aerodrive_upload_$fileId');
    await uploadDir.create(recursive: true);
    _activeUploadDirs[fileId] = uploadDir;

    DateTime? photoTakenAt;
    double? latitude;
    double? longitude;
    String? locality;
    String? country;
    List<String>? tags;
    List<Map<String, dynamic>>? faces;

    if (mimeType.startsWith('image/')) {
      try {
        final analyzer = SmartAnalyzer(_db);
        final result = await analyzer.analyzeImageForUpload(sourceFile, fileId);
        photoTakenAt = result.photoTakenAt;
        latitude = (result.latitude != null && result.latitude!.isFinite) ? result.latitude : null;
        longitude = (result.longitude != null && result.longitude!.isFinite) ? result.longitude : null;
        locality = result.locality;
        country = result.country;
        tags = result.tags;
        faces = result.faces;
      } catch (e) {
        AppLogger.error('Failed to run smart analyzer before upload', e);
      }
    }

    // Bug Fix: Generate and cache thumbnail immediately during upload
    Uint8List? finalThumbBytes;
    Duration? videoDuration;

    if (mimeType.startsWith('image/')) {
      final payload = _ThumbnailPayload(localFilePath, 256);
      finalThumbBytes = await compute(_extractImageThumbnailIsolate, payload);
    } else if (mimeType.startsWith('video/')) {
      final videoService = _ref.read(videoThumbnailServiceProvider);
      final result = await videoService.generateSmartThumbnail(localFilePath);
      finalThumbBytes = result.path != null ? await File(result.path!).readAsBytes() : null;
      videoDuration = result.duration;
      if (result.path != null) {
        try {
          await File(result.path!).delete(); // cleanup
        } catch (_) {}
      }
    }

    // Pre-insert file record to satisfy SQLite foreign key constraints for chunk mapping
    final uploadDate = item.createdAt ?? DateTime.now();
    await _db.into(_db.files).insert(
      FilesCompanion.insert(
        id: fileId,
        name: fileName,
        folderId: drift.Value(targetFolderId),
        size: drift.Value(fileLength),
        mimeType: drift.Value(mimeType),
        isEncrypted: const drift.Value(true),
        isChunked: drift.Value(totalChunks > 1),
        totalChunks: drift.Value(totalChunks),
        sha256Hash: const drift.Value(''), // updated on finalize
        createdAt: drift.Value(uploadDate),
        updatedAt: drift.Value(uploadDate),
        photoTakenAt: drift.Value(photoTakenAt),
        duration: drift.Value(videoDuration?.inSeconds),
      )
    );

    if (finalThumbBytes != null && masterKey != null) {
      try {
        final cipher = AesGcm.with256bits();
        final secretKey = await cipher.newSecretKeyFromBytes(masterKey);

        final encryptedPath = await ThumbnailCacheManager.saveThumbnail(
          fileId: fileId,
          plaintextBytes: finalThumbBytes,
          masterKey: secretKey,
        );

        await (_db.update(_db.files)..where((f) => f.id.equals(fileId))).write(
          FilesCompanion(
            thumbnailPath: drift.Value(encryptedPath),
            thumbnailSize: drift.Value(finalThumbBytes.length),
            thumbnailLastAccess: drift.Value(DateTime.now()),
          ),
        );
      } catch (e) {
        AppLogger.error('Failed to save thumbnail during upload for $fileId', e);
      }
    }

    if (mimeType.startsWith('image/')) {
      _ref.invalidate(exploreDataProvider);
    }

    final ivPart = ctrIv != null ? base64Encode(ctrIv) : '';
    final nonceBase64 = base64Encode(encryptionNonce);
    await (_db.update(_db.transferQueue)..where((q) => q.id.equals(item.id)))
      .write(TransferQueueCompanion(
        errorMessage: drift.Value('$targetFolderId|${dekBytes.join(',')}|$ivPart|$nonceBase64|$encryptionAlgo'),
      ));

    final readyClients = _telegramManager.readyClients;
    if (readyClients.isEmpty) {
      await (_db.update(_db.transferQueue)..where((q) => q.id.equals(item.id)))
        .write(const TransferQueueCompanion(status: drift.Value('FAILED'), errorMessage: drift.Value('No ready Telegram accounts available.')));
      return;
    }

    await UploadFileLogger.instance.startUpload(
      fileId,
      fileName,
      fileLength,
    );

    _uploadProgress[fileId] = {};
    _abortedFileIds.remove(fileId);
    _confirmedChunksPerFile.remove(fileId);

    const int maxInFlight = 2;
    final inFlightFutures = <Future<void>>[];

    try {
      for (var i = 0; i < totalChunks; i++) {
        if (_abortedFileIds.contains(fileId)) {
          AppLogger.warning('Aborting chunk dispatch for file $fileId — upload was aborted');
          break;
        }

        // Wait until there is a free slot in the sliding window
        while (inFlightFutures.length >= maxInFlight) {
          await Future.any(inFlightFutures);
          if (_abortedFileIds.contains(fileId)) break;
        }
        if (_abortedFileIds.contains(fileId)) break;

        final startOffset = i * chunkSize;
        final currentChunkLen = (i == totalChunks - 1) ? (fileLength - startOffset) : chunkSize;
        final chunkOutputPath = '${uploadDir.path}${Platform.pathSeparator}chunk_$i.bin';

        UploadFileLogger.instance.logStage('Encrypting chunk $i/$totalChunks');
        await _orchestrator.processSingleChunkForUpload(
          sourceFile: sourceFile,
          outputFilePath: chunkOutputPath,
          startOffset: startOffset,
          chunkLength: currentChunkLen,
          dekBytes: dekBytes,
          ctrIv: ctrIv,
        );

        final targetIndex = (fileBaseIndex + i) % storageChannels.length;
        final ch = storageChannels[targetIndex];
        final chunkChannelId = ch['id'] is String ? int.parse(ch['id']) : ch['id'] as int;

        // Route chunk to the client associated with the storage channel if available
        final targetAccountId = ch['accountId']?.toString();
        TelegramService telegramClient;
        if (targetAccountId != null && targetAccountId.isNotEmpty) {
          telegramClient = readyClients.firstWhere(
            (c) => c.accountId == targetAccountId,
            orElse: () => readyClients[targetIndex % readyClients.length],
          );
        } else {
          telegramClient = readyClients[targetIndex % readyClients.length];
        }

        String? chunkCaption;
        AppLogger.info('Caption generation: masterKey=${masterKey != null ? "PRESENT" : "NULL"}');
        if (masterKey != null) {
          final cipher = AesGcm.with256bits();
          final secretKey = await cipher.newSecretKeyFromBytes(masterKey);

          final nonce = cipher.newNonce();
          final secretBox = await cipher.encrypt(
            dekBytes,
            secretKey: secretKey,
            nonce: nonce,
          );
          final wrappedDekBase64 = '${base64Encode(secretBox.nonce)}|${base64Encode(secretBox.mac.bytes)}|${base64Encode(secretBox.cipherText)}';

          chunkCaption = await ManifestEncoder.encodeFileManifest(
            fileId: fileId,
            fileName: fileName,
            parentFolderId: targetFolderId == null || targetFolderId.isEmpty ? null : targetFolderId,
            masterKey: secretKey,
            hash: hashStr,
            size: item.totalBytes ?? 0,
            mime: mimeType,
            wrappedDekBase64: wrappedDekBase64,
            ctrIvBase64: ctrIv != null ? base64Encode(ctrIv) : null,
            chunkIndex: i,
            totalChunks: totalChunks,
            isChunked: totalChunks > 1 ? 1 : 0,
            duration: (videoDuration?.inSeconds != null && videoDuration!.inSeconds > 0)
                ? videoDuration.inSeconds
                : null,
            photoTakenAt: photoTakenAt,
            latitude: (latitude != null && latitude.isFinite) ? latitude : null,
            longitude: (longitude != null && longitude.isFinite) ? longitude : null,
            locality: locality,
            country: country,
            tags: tags,
            faces: faces,
            createdAt: uploadDate,
          );
        }

        final chunkCompleter = Completer<void>();
        _chunkUploadedCompleters.putIfAbsent(fileId, () => {})[i] = chunkCompleter;

        UploadFileLogger.instance.logChunk(i, totalChunks);

        late Future<void> future;
        future = _uploadChunkWithTracking(
          telegramClient,
          chunkChannelId,
          chunkOutputPath,
          queueId: item.id,
          fileId: fileId,
          fileName: fileName,
          chunkIndex: i,
          totalChunks: totalChunks,
          caption: chunkCaption,
          chunkCompleter: chunkCompleter,
        ).whenComplete(() {
          inFlightFutures.remove(future);
        });

        inFlightFutures.add(future);
      }

      if (inFlightFutures.isNotEmpty) {
        await Future.wait(inFlightFutures);
      }
    } catch (e) {
      AppLogger.error('One or more chunk uploads failed for file $fileId', e);
      _abortedFileIds.add(fileId);
      _fileAbortReasons[fileId] ??= 'Chunk upload failed: $e';
    }

    if (_abortedFileIds.contains(fileId)) {
      final failReason = _fileAbortReasons[fileId] ?? 'Upload failed due to missing or failed chunk uploads.';
      AppLogger.warning('Upload process failed or aborted for file $fileId ($failReason) — ensuring cleanup.');
      await (_db.update(_db.transferQueue)..where((q) => q.id.equals(item.id)))
        .write(TransferQueueCompanion(
          status: const drift.Value('FAILED'),
          errorMessage: drift.Value(failReason),
        ));
      _fileAbortReasons.remove(fileId);
      _uploadMessageMap.removeWhere((_, v) => v.queueId == item.id);
      _uploadFileIdMap.removeWhere((_, v) => v.queueId == item.id);
      _uploadProgress.remove(fileId);
      _confirmedChunksPerFile.remove(fileId);
      _pendingFinalization.remove(fileId);
      _allChunksSentAt.remove(fileId);
      _chunkUploadedCompleters.remove(fileId);

      try {
        final dir = _activeUploadDirs.remove(fileId);
        if (dir != null && await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {}

      try {
        await (_db.delete(_db.chunks)..where((c) => c.fileId.equals(fileId))).go();
        await (_db.delete(_db.files)..where((f) => f.id.equals(fileId))).go();
      } catch (_) {}
      return;
    }

    // Post-wait check: If all inFlightFutures completed and file not yet COMPLETED in DB,
    // trigger _finalizeUpload immediately instead of waiting for periodic timeout.
    final currentQueueItem = await (_db.select(_db.transferQueue)..where((q) => q.id.equals(item.id))).getSingleOrNull();
    if (currentQueueItem != null && currentQueueItem.status != 'COMPLETED') {
      AppLogger.info('Post-Future.wait: File $fileId not yet marked COMPLETED. Invoking finalization check.');
      final syntheticKey = '$fileId:post_wait';
      _uploadMessageMap[syntheticKey] = ActiveUploadInfo(
        queueId: item.id,
        fileId: fileId,
        chunkIndex: totalChunks - 1,
        totalChunks: totalChunks,
        chatId: storageChannels[fileBaseIndex % storageChannels.length]['id'] is String
            ? int.parse(storageChannels[fileBaseIndex % storageChannels.length]['id'])
            : storageChannels[fileBaseIndex % storageChannels.length]['id'] as int,
        messageId: 0,
        fileName: fileName,
      );
      await _finalizeUpload(syntheticKey, null);
    }

    // Track this for the confirmation recovery watcher in case TDLib confirmations lag.
    _allChunksSentAt[fileId] = DateTime.now();
  }

  Future<void> _uploadChunkWithTracking(
    TelegramService client,
    int channelId,
    String chunkPath, {
    required String queueId,
    required String fileId,
    required String fileName,
    required int chunkIndex,
    required int totalChunks,
    String? caption,
    Completer<void>? chunkCompleter,
  }) async {
    AppLogger.info('_uploadChunkWithTracking: chunk=$chunkIndex/$totalChunks fileId=$fileId captionPresent=${caption != null} captionLen=${caption?.length ?? 0}');

    if (_abortedFileIds.contains(fileId)) {
      throw Exception('Upload aborted for file $fileId');
    }

    const maxRetries = 3;
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      if (_abortedFileIds.contains(fileId)) {
        throw Exception('Upload aborted for file $fileId');
      }
      try {
        final chunkFile = File(chunkPath);
        int? chunkSize;
        if (await chunkFile.exists()) {
          chunkSize = await chunkFile.length();
        }

        // Clean up any old chunk record for this index before inserting
        await (_db.delete(_db.chunks)
          ..where((c) => c.fileId.equals(fileId))
          ..where((c) => c.chunkIndex.equals(chunkIndex))
        ).go();

        // CRITICAL FIX: Pre-insert chunk in SQLite BEFORE calling handoffToTelegram.
        // For small files (photos < 2MB), TDLib sends updateMessageSendSucceeded in milliseconds.
        // Pre-inserting guarantees the chunk row exists in DB so updateMessageSendSucceeded
        // can immediately find and update its messageId without dropping it.
        await _db.into(_db.chunks).insert(
          ChunksCompanion.insert(
            id: _uuid.v4(),
            fileId: drift.Value(fileId),
            chunkIndex: drift.Value(chunkIndex),
            channelId: drift.Value(channelId),
            messageId: const drift.Value(null),
            size: drift.Value(chunkSize),
          )
        );

        final response = await _orchestrator.handoffToTelegram(
          client, channelId, [chunkPath], caption: caption,
        );

        if (response.isEmpty) {
          throw Exception('Telegram returned empty response for chunk $chunkIndex');
        }

        final msg = response.first;
        if (msg['@type'] == 'error') {
          throw Exception('Telegram error: [${msg['code']}] ${msg['message']}');
        }

        final messageId = msg['id'];
        final chatId = msg['chat_id'];

        final content = msg['content'];
        int? tdlibFileId;
        if (content != null) {
          final document = content['document'];
          if (document != null) {
            final fileObj = document['document'];
            if (fileObj != null) {
              tdlibFileId = fileObj['id'] as int?;
            }
          }
        }

        final key = '$messageId:$chatId';
        final info = ActiveUploadInfo(
          queueId: queueId,
          fileId: fileId,
          chunkIndex: chunkIndex,
          totalChunks: totalChunks,
          chatId: chatId,
          messageId: messageId,
          fileName: fileName,
        );

        _uploadMessageMap[key] = info;

        if (tdlibFileId != null) {
          _uploadFileIdMap[tdlibFileId] = info;
        }

        AppLogger.info('Upload chunk $chunkIndex/$totalChunks sent (temp msg $messageId, awaiting server confirmation)');

        // Await completion of network upload for this chunk before freeing window slot
        if (chunkCompleter != null) {
          await chunkCompleter.future.timeout(const Duration(minutes: 15));
        }

        // Immediately clean up this chunk's encrypted temporary file from disk
        try {
          if (await chunkFile.exists()) {
            await chunkFile.delete();
            AppLogger.info('Cleaned up uploaded chunk file: $chunkPath');
          }
        } catch (e) {
          AppLogger.warning('Failed to delete chunk file $chunkPath: $e');
        }

        return; // Success - exit retry loop
      } catch (e, s) {
        AppLogger.error('Upload chunk $chunkIndex attempt ${attempt + 1}/$maxRetries failed', e, s);

        if (attempt < maxRetries - 1) {
          final backoff = Duration(seconds: 2 * (attempt + 1));
          AppLogger.info('Retrying chunk $chunkIndex in ${backoff.inSeconds}s...');
          await Future.delayed(backoff);
        } else {
          _abortedFileIds.add(fileId);
          _fileAbortReasons[fileId] = 'Chunk $chunkIndex upload failed: $e';
          await (_db.update(_db.transferQueue)..where((q) => q.id.equals(queueId)))
            .write(TransferQueueCompanion(
              status: const drift.Value('FAILED'),
              errorMessage: drift.Value('Chunk $chunkIndex upload failed after $maxRetries attempts: $e'),
            ));
          // Clean up stale tracking entries
          _uploadMessageMap.removeWhere((_, v) => v.queueId == queueId);
          _uploadFileIdMap.removeWhere((_, v) => v.queueId == queueId);
          _uploadProgress.remove(fileId);
          _confirmedChunksPerFile.remove(fileId);
          _pendingFinalization.remove(fileId);
          _allChunksSentAt.remove(fileId);
          _chunkUploadedCompleters.remove(fileId);

          try {
            final dir = _activeUploadDirs.remove(fileId);
            if (dir != null && await dir.exists()) {
              await dir.delete(recursive: true);
            }
          } catch (_) {}

          // Clean up orphaned DB records (file + chunks) so they don't
          // appear as "Files in online" despite a failed upload.
          try {
            await (_db.delete(_db.chunks)..where((c) => c.fileId.equals(fileId))).go();
            await (_db.delete(_db.files)..where((f) => f.id.equals(fileId))).go();
            AppLogger.info('Cleaned up orphaned DB records for failed upload fileId=$fileId');
          } catch (cleanupErr) {
            AppLogger.warning('Failed to clean up orphaned records: $cleanupErr');
          }

          throw Exception('Chunk $chunkIndex upload failed after $maxRetries attempts: $e');
        }
      }
    }
  }

  Future<void> _finalizeUpload(String messageKey, Map<String, dynamic>? message) async {
    final uploadInfo = _uploadMessageMap[messageKey];
    if (uploadInfo == null) return;
    final queueId = uploadInfo.queueId;
    final fileId = uploadInfo.fileId;
    final totalChunks = uploadInfo.totalChunks;

    if (_abortedFileIds.contains(fileId)) {
      AppLogger.warning('Ignoring _finalizeUpload for aborted fileId=$fileId');
      return;
    }

    final item = await (_db.select(_db.transferQueue)..where((q) => q.id.equals(queueId))).getSingleOrNull();
    if (item == null || item.status == 'FAILED') return;

    final metaParts = item.errorMessage?.split('|');
    if (metaParts == null || metaParts.length < 2) return;
    final rawFolderId = metaParts[0];
    final String? folderId = (rawFolderId.isEmpty || rawFolderId == 'null') ? null : rawFolderId;
    final dekBytesString = metaParts[1];
    final ctrIvBase64 = metaParts.length >= 3 ? metaParts[2] : '';
    final encryptionNonceBase64 = metaParts.length >= 4 ? metaParts[3] : '';
    final encryptionAlgoStr = metaParts.length >= 5 ? metaParts[4] : 'AES-256-GCM';

    // Check if all chunks for this upload are complete AND have confirmed real message IDs (messageId > 0)
    final completedChunks = await (_db.select(_db.chunks)..where((c) => c.fileId.equals(fileId))).get();
    final confirmedMemoryIndices = _confirmedChunksPerFile[fileId] ?? {};

    // If memory has confirmation but DB doesn't have messageId yet, sync it
    for (final chunk in completedChunks) {
      if (chunk.messageId == null || chunk.messageId! <= 0) {
        if (confirmedMemoryIndices.contains(chunk.chunkIndex)) {
          final match = _uploadMessageMap.values
              .where((m) => m.fileId == fileId && m.chunkIndex == chunk.chunkIndex && m.messageId > 0)
              .firstOrNull;
          if (match != null) {
            await (_db.update(_db.chunks)..where((c) => c.id.equals(chunk.id)))
                .write(ChunksCompanion(messageId: drift.Value(match.messageId)));
          }
        }
      }
    }

    final freshChunks = await (_db.select(_db.chunks)..where((c) => c.fileId.equals(fileId))).get();
    final confirmedChunks = freshChunks.where((c) => c.messageId != null && c.messageId! > 0).toList();
    final confirmedIndicesInDb = confirmedChunks.map((c) => c.chunkIndex).whereType<int>().toSet();

    // Verify all chunk indices 0 .. totalChunks - 1 are confirmed
    final allIndicesConfirmed = totalChunks > 0 &&
        List.generate(totalChunks, (i) => i).every((idx) =>
            confirmedIndicesInDb.contains(idx) || confirmedMemoryIndices.contains(idx));

    if (totalChunks > 0 &&
        allIndicesConfirmed &&
        (confirmedIndicesInDb.length >= totalChunks || confirmedMemoryIndices.length >= totalChunks)) {
      final masterKey = _ref.read(masterKeyProvider);
      var wrappedDekString = dekBytesString;

      if (masterKey != null) {
        final dekBytes = dekBytesString.split(',').map(int.parse).toList();
        final cipher = AesGcm.with256bits();
        final secretKey = await cipher.newSecretKeyFromBytes(masterKey);
        final nonce = cipher.newNonce();

        final secretBox = await cipher.encrypt(
          dekBytes,
          secretKey: secretKey,
          nonce: nonce,
        );

        wrappedDekString = '${base64Encode(secretBox.nonce)}|${base64Encode(secretBox.mac.bytes)}|${base64Encode(secretBox.cipherText)}';

        if (ctrIvBase64.isNotEmpty) {
          wrappedDekString = '$wrappedDekString|$ctrIvBase64';
        }
      }

      final originalFileId = item.fileId;
      if (originalFileId == null) return;
      final originalPath = originalFileId.split('|')[0];
      final fileName = originalPath.contains('/') ? originalPath.split('/').last : originalPath.split('\\').last;
      final mimeType = _getMimeType(fileName);
      final uploadDate = item.createdAt ?? DateTime.now();

      // Check if file already inserted (placeholder) and update or fallback insert
      final existingFile = await (_db.select(_db.files)..where((f) => f.id.equals(fileId))).getSingleOrNull();
      if (existingFile != null) {
        await (_db.update(_db.files)..where((f) => f.id.equals(fileId))).write(
          FilesCompanion(
            sha256Hash: drift.Value(wrappedDekString),
            encryptionNonce: encryptionNonceBase64.isNotEmpty
                ? drift.Value(encryptionNonceBase64)
                : const drift.Value(null),
            encryptionAlgo: drift.Value(encryptionAlgoStr),
            updatedAt: drift.Value(DateTime.now()),
          )
        );
      } else {
        await _db.into(_db.files).insert(
          FilesCompanion.insert(
            id: fileId,
            name: fileName,
            folderId: drift.Value(folderId),
            size: drift.Value(item.totalBytes),
            mimeType: drift.Value(mimeType),
            isEncrypted: const drift.Value(true),
            isChunked: drift.Value(totalChunks > 1),
            totalChunks: drift.Value(totalChunks),
            sha256Hash: drift.Value(wrappedDekString),
            encryptionNonce: encryptionNonceBase64.isNotEmpty
                ? drift.Value(encryptionNonceBase64)
                : const drift.Value(null),
            encryptionAlgo: drift.Value(encryptionAlgoStr),
            createdAt: drift.Value(uploadDate),
            updatedAt: drift.Value(DateTime.now()),
          )
        );
      }

      final fileData = await (_db.select(_db.files)..where((f) => f.id.equals(fileId))).getSingle();
      _ref.read(mlServiceProvider).processImage(fileData);
      try {
        await _ref.read(placesServiceProvider).processImageLocation(fileData);
      } catch (e) {
        AppLogger.error('Failed to process image location on sync/finalize', e);
      }

      // Mark transfer queue as COMPLETED
      await (_db.update(_db.transferQueue)..where((q) => q.id.equals(queueId)))
        .write(TransferQueueCompanion(
          status: const drift.Value('COMPLETED'),
          bytesTransferred: drift.Value(item.totalBytes ?? 0),
        ));

      // Clean up tracking maps
      _uploadProgress.remove(fileId);
      _confirmedChunksPerFile.remove(fileId);
      _uploadFileIdMap.removeWhere((_, v) => v.queueId == queueId);
      _uploadMessageMap.removeWhere((_, v) => v.queueId == queueId);
      _pendingFinalization.remove(fileId);
      _allChunksSentAt.remove(fileId);
      _chunkUploadedCompleters.remove(fileId);
      _fileAbortReasons.remove(fileId);

      try {
        final dir = _activeUploadDirs.remove(fileId);
        if (dir != null && await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {}

      await UploadFileLogger.instance.finishUpload();

      AppLogger.info('Upload Completed and Finalized for $fileName!');

      NotificationService.instance.showUploadComplete(
        NotificationService.instance.getSafeNotificationId(queueId),
        fileName,
      );

      // ─────────────────────────────────────────────────────────────
      // Section 2: Upload encrypted thumbnail to Telegram
      // ─────────────────────────────────────────────────────────────
      if (masterKey != null) {
        AppLogger.info('Thumbnail upload check: mimeType=$mimeType startsWithImage=${mimeType.startsWith('image/')} startsWithVideo=${mimeType.startsWith('video/')}');
        if (mimeType.startsWith('image/') || mimeType.startsWith('video/')) {
          await _uploadThumbnail(fileId, originalPath, message, masterKey);
        } else {
          AppLogger.info('Non-image/video file - skipping thumbnail upload for $fileId');
        }
      } else {
        AppLogger.warning('Master key is null - cannot encrypt/upload thumbnail for $fileId');
      }
    }

    // Clean up temp ZIP files after successful upload
    try {
      final origFileId = item.fileId;
      if (origFileId != null) {
        final origPath = origFileId.split('|').first;
        if (origPath.endsWith('.zip')) {
          final tempDir = await getTemporaryDirectory();
          if (origPath.startsWith(tempDir.path)) {
            final tempFile = File(origPath);
            if (await tempFile.exists()) {
              await tempFile.delete();
              AppLogger.info('Cleaned up temp ZIP: $origPath');
            }
          }
        }
      }
    } catch (_) {}
  }

  /// Uploads an encrypted thumbnail for a completed file upload.
  /// Uses safe type-specific extraction:
  ///   - Images: downsampled to 512px max in background isolate
  ///   - Videos:  skipped (media_kit frame extraction to be added in Phase D)
  /// A strict 5-second timeout + catch-all ensures the upload never crashes.
  Future<void> _uploadThumbnail(String fileId, String originalPath,
      Map<String, dynamic>? fileMessage, List<int> masterKey) async {
    AppLogger.info('_uploadThumbnail START for fileId=$fileId');
    try {
      final originalFile = File(originalPath);
      if (!await originalFile.exists()) {
        AppLogger.warning('_uploadThumbnail: source file not found at $originalPath');
        return;
      }

      Uint8List? thumbnailJpgBytes;
      final mimeType = _getMimeType(originalFile.path);

      if (mimeType.startsWith('image/')) {
        try {
          thumbnailJpgBytes = await Future.any([
            compute(
              _extractImageThumbnailIsolate,
              _ThumbnailPayload(originalPath, 512),
            ),
            Future.delayed(
              const Duration(seconds: 5),
              () => null, // timeout sentinel
            ),
          ]);
        } catch (e) {
          AppLogger.warning('_uploadThumbnail: isolate image extraction failed. Error: $e');
        }
      } else if (mimeType.startsWith('video/')) {
        try {
          final videoService = _ref.read(videoThumbnailServiceProvider);
          final result = await videoService.generateSmartThumbnail(originalPath);
          final thumbPath = result.path;
          if (thumbPath != null) {
            final f = File(thumbPath);
            if (await f.exists()) {
              thumbnailJpgBytes = await f.readAsBytes();
              try { await f.delete(); } catch (_) {}
            }
          }
        } catch (e) {
          AppLogger.warning('_uploadThumbnail: video thumbnail extraction failed. Error: $e');
        }
      }

      if (thumbnailJpgBytes == null) {
        AppLogger.warning('_uploadThumbnail: extraction failed, timed out, or returned null — skipping thumbnail for $fileId');
        return;
      }

      AppLogger.info('_uploadThumbnail: generated ${thumbnailJpgBytes.length} bytes thumbnail');

      // 2. Encrypt thumbnail with Master Key (AES-256-GCM)
      final cipher = AesGcm.with256bits();
      final secretKey = await cipher.newSecretKeyFromBytes(masterKey);
      final nonce = cipher.newNonce();
      final secretBox = await cipher.encrypt(thumbnailJpgBytes, secretKey: secretKey, nonce: nonce);

      final builder = BytesBuilder();
      builder.add(secretBox.nonce);
      builder.add(secretBox.cipherText);
      builder.add(secretBox.mac.bytes);
      final encryptedThumbBytes = builder.toBytes();

      // 3. Write encrypted thumbnail to temp file
      final tempDir = await getTemporaryDirectory();
      final thumbFile = File('${tempDir.path}${Platform.pathSeparator}thumb_$fileId.enc');
      await thumbFile.writeAsBytes(encryptedThumbBytes);

      // 4. Encrypt thumbnail caption: {"t":"thumb","fid":"<fileId>"}
      final thumbManifestJson = jsonEncode({'t': 'thumb', 'fid': fileId});
      final thumbNonce = cipher.newNonce();
      final thumbSecretBox = await cipher.encrypt(
        utf8.encode(thumbManifestJson),
        secretKey: secretKey,
        nonce: thumbNonce,
      );
      final thumbCaptionBuilder = BytesBuilder();
      thumbCaptionBuilder.add(thumbSecretBox.nonce);
      thumbCaptionBuilder.add(thumbSecretBox.cipherText);
      thumbCaptionBuilder.add(thumbSecretBox.mac.bytes);
      final thumbCaptionBase64 = base64Encode(thumbCaptionBuilder.toBytes());

      // 5. Determine target channel from the file message
      final chatId = fileMessage?['chat_id'] as int?;
      if (chatId == null) {
        AppLogger.warning('_uploadThumbnail: no chat_id in file message');
        await thumbFile.delete();
        return;
      }

      // 6. Upload thumbnail as a document to the same channel
      final readyClients = _telegramManager.readyClients;
      if (readyClients.isEmpty) {
        AppLogger.warning('_uploadThumbnail: no ready Telegram clients');
        await thumbFile.delete();
        return;
      }

      try {
        final thumbMessage = await readyClients.first.uploadDocument(chatId, thumbFile.path, caption: thumbCaptionBase64);
        if (thumbMessage.containsKey('id')) {
          final int thumbMessageId = thumbMessage['id'];
          final int thumbChannelId = thumbMessage['chat_id'];
          await (_db.update(_db.files)..where((f) => f.id.equals(fileId))).write(
            FilesCompanion(
              thumbnailMessageId: drift.Value(thumbMessageId),
              thumbnailChannelId: drift.Value(thumbChannelId),
            ),
          );
          AppLogger.info('_uploadThumbnail SUCCESS for file $fileId (saved msgId=$thumbMessageId, chanId=$thumbChannelId)');
        } else {
          AppLogger.info('_uploadThumbnail SUCCESS for file $fileId (but message metadata not returned)');
        }
      } catch (e) {
        AppLogger.error('_uploadThumbnail: uploadDocument failed for $fileId', e);
      } finally {
        try { await thumbFile.delete(); } catch (_) {}
      }
    } catch (e) {
      // Outer catch: never let thumbnail failure propagate and crash the upload.
      AppLogger.warning('_uploadThumbnail FAILED for $fileId (non-fatal): $e');
    }
  }

  void dispose() {
    _pollingTimer?.cancel();
    _tdlibSub?.cancel();
    _confirmationWatcher?.cancel();
  }
}
