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
import 'notification_service.dart';
import 'recovery/manifest_encoder.dart';
import 'smart_analyzer.dart';
import 'thumbnail_cache_manager.dart';
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
  });
  final String queueId;
  final String fileId;
  final int chunkIndex;
  final int totalChunks;
  final int chatId;
  final int messageId;
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
    _startPolling();
    _listenToTdlibEvents();
  }
  final ProviderRef _ref;
  final AeroDriveDatabase _db;
  final SettingsRepository _settings;
  final TelegramManager _telegramManager;
  final UploadOrchestrator _orchestrator;

  Timer? _pollingTimer;
  StreamSubscription? _tdlibSub;

  // Bug 4 fix: replace single bool with a set of active queue IDs so we can
  // process multiple uploads concurrently instead of blocking on a global flag.
  final Set<String> _processingIds = {};
  static const int _maxConcurrent = 4; // respects parallel_threads setting

  final _uuid = const Uuid();

  // Maps TDLib file_id -> ActiveUploadInfo for progress tracking
  final Map<int, ActiveUploadInfo> _uploadFileIdMap = {};

  // Maps "messageId:chatId" -> ActiveUploadInfo for completion tracking
  final Map<String, ActiveUploadInfo> _uploadMessageMap = {};

  // Track chunk upload progress: fileId -> {chunkIndex: bytesUploaded}
  final Map<String, Map<int, int>> _uploadProgress = {};

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
    final algorithm = Sha256();
    final sink = algorithm.newHashSink();
    final openFile = await file.open();
    try {
      const int bufferSize = 4 * 1024 * 1024;
      final length = await openFile.length();
      var offset = 0;
      while (offset < length) {
        final toRead = (length - offset < bufferSize) ? length - offset : bufferSize;
        final block = await openFile.read(toRead);
        sink.add(block);
        offset += toRead;
      }
    } finally {
      await openFile.close();
    }
    sink.close();
    final hash = await sink.hash();
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
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

      // Dispatch each item concurrently (fire-and-forget, tracked by ID)
      for (final item in pendingItems) {
        if (_processingIds.contains(item.id)) continue;
        _processingIds.add(item.id);
        _processQueueItem(item).catchError((e) {
          AppLogger.error('UploadQueue Error for ${item.id}', e);
        }).whenComplete(() {
          _processingIds.remove(item.id);
        });
      }
    });
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
            await (_db.update(_db.transferQueue)
              ..where((q) => q.id.equals(info.queueId)))
              .write(const TransferQueueCompanion(
                status: drift.Value('FAILED'),
                errorMessage: drift.Value('Telegram rejected the upload.'),
              ));
              
            NotificationService.instance.showUploadFailed(
              int.parse(info.queueId.hashCode.toString().substring(0, 8)),
              'File Upload',
              'Telegram rejected the upload.',
            );
            _uploadMessageMap.remove(matchKey);
            _uploadFileIdMap.removeWhere((_, v) => v.queueId == info.queueId);
            _uploadProgress.remove(info.fileId);
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
                int.parse(info.queueId.hashCode.toString().substring(0, 8)),
                'File Upload',
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

              // Do NOT remove from maps here - wait for updateMessageSendSucceeded
              // to finalize with the real message ID. The file upload completes
              // before the message is sent.
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
    final savedChannelsJson = await _settings.getSetting('storage_channels_list');
    List<Map<String, dynamic>> storageChannels = [];
    if (savedChannelsJson != null && savedChannelsJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(savedChannelsJson);
        storageChannels = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (e) {
        AppLogger.error('UploadQueue: failed to parse storage channels', e);
      }
    }

    int activeChannelId;

    if (storageChannels.isNotEmpty) {
      final strategy = await _settings.getSetting('load_balancing_strategy') ?? 'round_robin';

      if (strategy == 'round_robin') {
        final int index = int.tryParse(await _settings.getSetting('load_balancing_round_robin_index') ?? '0') ?? 0;
        final ch = storageChannels[index % storageChannels.length];
        activeChannelId = ch['id'] is String ? int.parse(ch['id']) : ch['id'] as int;
        await _settings.setSetting('load_balancing_round_robin_index', ((index + 1) % storageChannels.length).toString());
      } else if (strategy == 'random') {
        final ch = storageChannels[Random().nextInt(storageChannels.length)];
        activeChannelId = ch['id'] is String ? int.parse(ch['id']) : ch['id'] as int;
      } else if (strategy == 'fill_first') {
        Map<String, dynamic>? selectedCh;
        for (final ch in storageChannels) {
          final id = ch['id'];
          final chId = id is String ? int.parse(id) : id as int;

          final countQuery = await (_db.selectOnly(_db.chunks)
            ..addColumns([_db.chunks.id.count()])
            ..where(_db.chunks.channelId.equals(chId))
          ).getSingle();
          final count = countQuery.read<int>(_db.chunks.id.count()) ?? 0;

          if (count < 1000) {
            selectedCh = ch;
            break;
          }
        }
        selectedCh ??= storageChannels.first;
        activeChannelId = selectedCh['id'] is String ? int.parse(selectedCh['id']) : selectedCh['id'] as int;
      } else if (strategy == 'size_based') {
        final fileSize = item.totalBytes ?? 0;
        if (fileSize < 10 * 1024 * 1024 || storageChannels.length == 1) {
          final ch = storageChannels[0];
          activeChannelId = ch['id'] is String ? int.parse(ch['id']) : ch['id'] as int;
        } else {
          final otherChannels = storageChannels.sublist(1);
          final ch = otherChannels[Random().nextInt(otherChannels.length)];
          activeChannelId = ch['id'] is String ? int.parse(ch['id']) : ch['id'] as int;
        }
      } else {
        final ch = storageChannels.first;
        activeChannelId = ch['id'] is String ? int.parse(ch['id']) : ch['id'] as int;
      }
    } else {
      var activeChannelStr = await _settings.getSetting('active_channel_id');
      if (activeChannelStr == null || activeChannelStr.isEmpty) {
        final savedChannelsJson = await _settings.getSetting('storage_channels_list');
        if (savedChannelsJson != null && savedChannelsJson.isNotEmpty) {
          try {
            final List<dynamic> decoded = jsonDecode(savedChannelsJson);
            if (decoded.isNotEmpty) {
              activeChannelStr = decoded.first['id'].toString();
              await _settings.setSetting('active_channel_id', activeChannelStr);
            }
          } catch (_) {}
        }
      }

      if (activeChannelStr == null || activeChannelStr.isEmpty) {
        await (_db.update(_db.transferQueue)..where((q) => q.id.equals(item.id)))
          .write(const TransferQueueCompanion(status: drift.Value('FAILED'), errorMessage: drift.Value('No Storage Channels available.')));
        return;
      }
      activeChannelId = int.parse(activeChannelStr);
    }

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
    final isVideo = mimeType.startsWith('video/');

    final random = Random.secure();
    final dekBytes = List<int>.generate(32, (_) => random.nextInt(256));
    final encryptionNonce = List<int>.generate(12, (_) => random.nextInt(256));
    final encryptionAlgo = isVideo ? 'AES-256-CTR' : 'AES-256-GCM';

    List<int>? ctrIv;
    if (isVideo) {
      ctrIv = List<int>.generate(16, (_) => random.nextInt(256));
    }

    final encryptedChunkPaths = await _orchestrator.processFileForUpload(
      sourceFile,
      dekBytes,
      ctrIv: ctrIv,
    );

    final hashStr = await _calculateFileHash(sourceFile);

    final masterKey = _ref.read(masterKeyProvider);
    final fileId = _uuid.v4();
    final totalChunks = encryptedChunkPaths.length;

    DateTime? photoTakenAt;
    if (mimeType.startsWith('image/')) {
      try {
        final bytes = await sourceFile.readAsBytes();
        final data = await readExifFromBytes(bytes);
        final dateTag = data['Image DateTime'] ?? data['EXIF DateTimeOriginal'];
        if (dateTag != null) {
          final dateStr = dateTag.toString();
          // EXIF format: "YYYY:MM:DD HH:MM:SS"
          if (dateStr.length >= 19) {
            final formattedStr = '${dateStr.substring(0, 4)}-${dateStr.substring(5, 7)}-${dateStr.substring(8, 10)} ${dateStr.substring(11)}';
            photoTakenAt = DateTime.tryParse(formattedStr);
          }
        }
      } catch (e) {
        AppLogger.error('Failed to parse EXIF for $fileName', e);
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
        createdAt: drift.Value(DateTime.now()),
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

        // Upload the generated thumbnail as a 'thumb' manifest message so it syncs across devices
        _uploadThumbnailManifest(
          fileId: fileId,
          encryptedThumbBytes: await File(encryptedPath).readAsBytes(),
          masterKey: masterKey,
          channelId: activeChannelId,
        );

      } catch (e) {
        AppLogger.error('Failed to save thumbnail during upload for $fileId', e);
      }
    }

    if (mimeType.startsWith('image/')) {
      final analyzer = SmartAnalyzer(_db);
      // Run analysis concurrently so it doesn't block upload setup
      analyzer.analyzeAndStore(sourceFile, fileId).then((_) {
        // Invalidate explore data so the UI updates
        _ref.invalidate(exploreDataProvider);
      });
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

    _uploadProgress[fileId] = {};

    final List<Future<void>> uploadFutures = [];

    for (var i = 0; i < totalChunks; i++) {
      final path = encryptedChunkPaths[i];

      final ch = storageChannels.isNotEmpty ? storageChannels[i % storageChannels.length] : null;
      final chunkChannelId = ch != null ? (ch['id'] is String ? int.parse(ch['id']) : ch['id'] as int) : activeChannelId;
      final telegramClient = readyClients[i % readyClients.length];

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
          duration: videoDuration?.inSeconds,
        );
      }

      final future = _uploadChunkWithTracking(
        telegramClient,
        chunkChannelId,
        path,
        queueId: item.id,
        fileId: fileId,
        chunkIndex: i,
        totalChunks: totalChunks,
        caption: chunkCaption,
      );
      uploadFutures.add(future);
    }

    await Future.wait(uploadFutures);
  }

  Future<void> _uploadChunkWithTracking(
    TelegramService client,
    int channelId,
    String chunkPath, {
    required String queueId,
    required String fileId,
    required int chunkIndex,
    required int totalChunks,
    String? caption,
  }) async {
    AppLogger.info('_uploadChunkWithTracking: chunk=$chunkIndex/$totalChunks fileId=$fileId captionPresent=${caption != null} captionLen=${caption?.length ?? 0}');
    
    const maxRetries = 3;
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final response = await _orchestrator.handoffToTelegram(
          client, channelId, [chunkPath], caption: caption,
        );

        if (response.isNotEmpty) {
          final msg = response.first;
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
          );

          _uploadMessageMap[key] = info;

          if (tdlibFileId != null) {
            _uploadFileIdMap[tdlibFileId] = info;
          }

          final chunkFile = File(chunkPath);
          int? chunkSize;
          if (await chunkFile.exists()) {
            chunkSize = await chunkFile.length();
          }

          await _db.into(_db.chunks).insert(
            ChunksCompanion.insert(
              id: _uuid.v4(),
              fileId: drift.Value(fileId),
              chunkIndex: drift.Value(chunkIndex),
              channelId: drift.Value(channelId),
              messageId: drift.Value(messageId),
              size: drift.Value(chunkSize),
            )
          );

          AppLogger.info('Upload chunk $chunkIndex/$totalChunks sent (msg $messageId)');
          return; // Success - exit retry loop
        }
      } catch (e, s) {
        AppLogger.error('Upload chunk $chunkIndex attempt ${attempt + 1}/$maxRetries failed', e, s);
        
        if (attempt < maxRetries - 1) {
          final backoff = Duration(seconds: 2 * (attempt + 1));
          AppLogger.info('Retrying chunk $chunkIndex in ${backoff.inSeconds}s...');
          await Future.delayed(backoff);
        } else {
          await (_db.update(_db.transferQueue)..where((q) => q.id.equals(queueId)))
            .write(TransferQueueCompanion(
              status: const drift.Value('FAILED'),
              errorMessage: drift.Value('Chunk $chunkIndex upload failed after $maxRetries attempts: $e'),
            ));
          // Clean up stale tracking entries
          _uploadMessageMap.removeWhere((_, v) => v.queueId == queueId);
          _uploadFileIdMap.removeWhere((_, v) => v.queueId == queueId);
          _uploadProgress.remove(fileId);
        }
      }
    }
  }

  Future<void> _finalizeUpload(String messageKey, Map<String, dynamic> message) async {
    final uploadInfo = _uploadMessageMap[messageKey];
    if (uploadInfo == null) return;
    final queueId = uploadInfo.queueId;
    final fileId = uploadInfo.fileId;
    final totalChunks = uploadInfo.totalChunks;

    final item = await (_db.select(_db.transferQueue)..where((q) => q.id.equals(queueId))).getSingleOrNull();
    if (item == null) return;

    final metaParts = item.errorMessage?.split('|');
    if (metaParts == null || metaParts.length < 2) return;
    final folderId = metaParts[0];
    final dekBytesString = metaParts[1];
    final ctrIvBase64 = metaParts.length >= 3 ? metaParts[2] : '';
    final encryptionNonceBase64 = metaParts.length >= 4 ? metaParts[3] : '';
    final encryptionAlgoStr = metaParts.length >= 5 ? metaParts[4] : 'AES-256-GCM';

    // Check if all chunks for this upload are complete
    final completedChunks = await (_db.select(_db.chunks)..where((c) => c.fileId.equals(fileId))).get();
    if (completedChunks.length >= totalChunks) {
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
            createdAt: drift.Value(DateTime.now()),
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
      _uploadFileIdMap.removeWhere((_, v) => v.queueId == queueId);
      _uploadMessageMap.removeWhere((_, v) => v.queueId == queueId);

      AppLogger.info('Upload Completed and Finalized for $fileName!');
      
      NotificationService.instance.showUploadComplete(
        int.parse(queueId.hashCode.toString().substring(0, 8)),
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

    _uploadMessageMap.remove(messageKey);
  }

  /// Uploads an encrypted thumbnail for a completed file upload.
  /// Uses safe type-specific extraction:
  ///   - Images: downsampled to 512px max in background isolate
  ///   - Videos:  skipped (media_kit frame extraction to be added in Phase D)
  /// A strict 5-second timeout + catch-all ensures the upload never crashes.
  Future<void> _uploadThumbnail(String fileId, String originalPath,
      Map<String, dynamic> fileMessage, List<int> masterKey) async {
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
      final chatId = fileMessage['chat_id'] as int?;
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
        await readyClients.first.uploadDocument(chatId, thumbFile.path, caption: thumbCaptionBase64);
        AppLogger.info('_uploadThumbnail SUCCESS for file $fileId');
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
  }
}
