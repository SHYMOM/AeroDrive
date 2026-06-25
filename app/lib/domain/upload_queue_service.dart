import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';

import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:aerodrive/core/providers/security_providers.dart';
import 'package:aerodrive/features/ml/ml_service.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/data/repositories/settings_repository.dart';
import 'package:aerodrive/features/telegram/telegram_manager.dart';
import 'package:aerodrive/features/telegram/telegram_service.dart';
import 'package:aerodrive/domain/upload_orchestrator.dart';
import 'package:aerodrive/core/logger.dart';
import 'package:aerodrive/domain/recovery/manifest_encoder.dart';

class ActiveUploadInfo {
  final String queueId;
  final String fileId;
  final int chunkIndex;
  final int totalChunks;
  ActiveUploadInfo({
    required this.queueId,
    required this.fileId,
    required this.chunkIndex,
    required this.totalChunks,
  });
}

class UploadQueueService {
  final ProviderRef _ref;
  final AeroDriveDatabase _db;
  final SettingsRepository _settings;
  final TelegramManager _telegramManager;
  final UploadOrchestrator _orchestrator;
  
  Timer? _pollingTimer;
  StreamSubscription? _tdlibSub;
  bool _isProcessing = false;
  final _uuid = const Uuid();

  // Maps temporary encrypted chunk path (normalized) to active upload info
  final Map<String, ActiveUploadInfo> _activeUploads = {};

  // Track chunk upload progress: fileId -> {chunkIndex: bytesUploaded}
  final Map<String, Map<int, int>> _uploadProgress = {};

  UploadQueueService(this._ref, this._db, this._settings, this._telegramManager, this._orchestrator) {
    _startPolling();
    _listenToTdlibEvents();
  }

  String _normalizePath(String path) {
    return path.replaceAll('\\', '/').toLowerCase();
  }

  String _getMimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      // Images
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
      // Videos
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
      // Audio
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
        return 'audio/ogg';
      case 'm4a':
        return 'audio/mp4';
      // PDF/Docs
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
    final openFile = await file.open(mode: FileMode.read);
    final int bufferSize = 4 * 1024 * 1024;
    final length = await openFile.length();
    int offset = 0;
    while (offset < length) {
      final toRead = (length - offset < bufferSize) ? length - offset : bufferSize;
      final block = await openFile.read(toRead);
      sink.add(block);
      offset += toRead;
    }
    await openFile.close();
    sink.close();
    final hash = await sink.hash();
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_isProcessing) return;
      
      _isProcessing = true;
      try {
        await _processNextInQueue();
      } catch (e) {
        AppLogger.error('UploadQueue Error', e);
      } finally {
        _isProcessing = false;
      }
    });
  }

  void _listenToTdlibEvents() {
    _tdlibSub = _telegramManager.allEvents.listen((event) async {
      final type = event['@type'];
      
      if (type == 'updateMessageSendSucceeded') {
        final message = event['message'];
        final content = message['content'];
        if (content != null && content['@type'] == 'messageDocument') {
          final document = content['document'];
          if (document != null && document['document'] != null) {
            final localPath = document['document']['local']['path'] as String?;
            if (localPath != null) {
              final normPath = _normalizePath(localPath);
              if (_activeUploads.containsKey(normPath)) {
                await _finalizeUpload(localPath, message);
              }
            }
          }
        }
      } else if (type == 'updateMessageSendFailed') {
        final message = event['message'];
        final content = message['content'];
        if (content != null && content['@type'] == 'messageDocument') {
          final document = content['document'];
          if (document != null && document['document'] != null) {
            final localPath = document['document']['local']['path'] as String?;
            if (localPath != null) {
              final normPath = _normalizePath(localPath);
              if (_activeUploads.containsKey(normPath)) {
                final activeInfo = _activeUploads[normPath]!;
                await _db.update(_db.transferQueue)
                  ..where((q) => q.id.equals(activeInfo.queueId))
                  ..write(const TransferQueueCompanion(
                    status: drift.Value('FAILED'),
                    errorMessage: drift.Value('Telegram rejected the upload.'),
                  ));
                _activeUploads.remove(normPath);
              }
            }
          }
        }
      } else if (type == 'updateFile') {
        final file = event['file'];
        if (file != null) {
          final local = file['local'];
          final remote = file['remote'];
          if (local != null) {
            final localPath = local['path'] as String?;
            if (localPath != null) {
              final normPath = _normalizePath(localPath);
              if (_activeUploads.containsKey(normPath)) {
                final activeInfo = _activeUploads[normPath]!;
                final uploadedSize = (remote != null) ? (remote['uploaded_size'] as int? ?? 0) : 0;
                
                _uploadProgress.putIfAbsent(activeInfo.fileId, () => {})[activeInfo.chunkIndex] = uploadedSize;
                
                // Sum progress of all chunks for this file
                final totalUploaded = _uploadProgress[activeInfo.fileId]!.values.reduce((a, b) => a + b);
                
                await (_db.update(_db.transferQueue)..where((q) => q.id.equals(activeInfo.queueId)))
                    .write(TransferQueueCompanion(
                      bytesTransferred: drift.Value(totalUploaded),
                    ));
              }
            }
          }
        }
      }
    });
  }

  Future<void> _processNextInQueue() async {
    // 1. Get next pending item
    final item = await (_db.select(_db.transferQueue)
      ..where((q) => q.status.equals('PENDING'))
      ..where((q) => q.type.equals('UPLOAD_FILE'))
      ..orderBy([(q) => drift.OrderingTerm.asc(q.createdAt)])
      ..limit(1)
    ).getSingleOrNull();

    if (item == null) return;

    // 2. Resolve channel to upload to
    final savedChannelsJson = await _settings.getSetting('storage_channels_list');
    List<Map<String, dynamic>> storageChannels = [];
    if (savedChannelsJson != null && savedChannelsJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(savedChannelsJson);
        storageChannels = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }

    int activeChannelId;
    String accountId;

    if (storageChannels.isNotEmpty) {
      final strategy = await _settings.getSetting('load_balancing_strategy') ?? 'round_robin';
      
      if (strategy == 'round_robin') {
        int index = int.tryParse(await _settings.getSetting('load_balancing_round_robin_index') ?? '0') ?? 0;
        final ch = storageChannels[index % storageChannels.length];
        activeChannelId = ch['id'] is String ? int.parse(ch['id']) : ch['id'] as int;
        accountId = ch['accountId'] ?? 'primary';
        await _settings.setSetting('load_balancing_round_robin_index', ((index + 1) % storageChannels.length).toString());
      } else if (strategy == 'random') {
        final ch = storageChannels[Random().nextInt(storageChannels.length)];
        activeChannelId = ch['id'] is String ? int.parse(ch['id']) : ch['id'] as int;
        accountId = ch['accountId'] ?? 'primary';
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
        accountId = selectedCh['accountId'] ?? 'primary';
      } else if (strategy == 'size_based') {
        final fileSize = item.totalBytes ?? 0;
        if (fileSize < 10 * 1024 * 1024 || storageChannels.length == 1) {
          final ch = storageChannels[0];
          activeChannelId = ch['id'] is String ? int.parse(ch['id']) : ch['id'] as int;
          accountId = ch['accountId'] ?? 'primary';
        } else {
          final otherChannels = storageChannels.sublist(1);
          final ch = otherChannels[Random().nextInt(otherChannels.length)];
          activeChannelId = ch['id'] is String ? int.parse(ch['id']) : ch['id'] as int;
          accountId = ch['accountId'] ?? 'primary';
        }
      } else {
        final ch = storageChannels.first;
        activeChannelId = ch['id'] is String ? int.parse(ch['id']) : ch['id'] as int;
        accountId = ch['accountId'] ?? 'primary';
      }
    } else {
      // Fallback to active_channel_id if storage_channels_list is empty
      final activeChannelStr = await _settings.getSetting('active_channel_id');
      if (activeChannelStr == null || activeChannelStr.isEmpty) {
        await (_db.update(_db.transferQueue)..where((q) => q.id.equals(item.id)))
            .write(const TransferQueueCompanion(status: drift.Value('FAILED'), errorMessage: drift.Value('No Storage Channels available.')));
        return;
      }
      activeChannelId = int.parse(activeChannelStr);
      final activeChannelAccountStr = await _settings.getSetting('active_channel_account_id');
      accountId = activeChannelAccountStr ?? 'primary';
    }

    // 3. Mark as processing
    await (_db.update(_db.transferQueue)..where((q) => q.id.equals(item.id)))
          .write(const TransferQueueCompanion(status: drift.Value('PROCESSING')));

    // The fileId field was temporarily used to store "LocalPath|ParentFolderId"
    final parts = item.fileId?.split('|');
    if (parts == null || parts.length < 2) {
      await (_db.update(_db.transferQueue)..where((q) => q.id.equals(item.id)))
          .write(const TransferQueueCompanion(status: drift.Value('FAILED'), errorMessage: drift.Value('Invalid path data.')));
      return;
    }

    final localFilePath = parts[0];
    final targetFolderId = parts[1];

    final sourceFile = File(localFilePath);
    if (!await sourceFile.exists()) {
      await (_db.update(_db.transferQueue)..where((q) => q.id.equals(item.id)))
          .write(const TransferQueueCompanion(status: drift.Value('FAILED'), errorMessage: drift.Value('File not found on disk.')));
      return;
    }

    final fileName = sourceFile.path.split(Platform.pathSeparator).last;
    final mimeType = _getMimeType(fileName);
    final isVideo = mimeType.startsWith('video/');

    // 4. Generate random DEK
    final random = Random.secure();
    final dekBytes = List<int>.generate(32, (_) => random.nextInt(256));

    List<int>? ctrIv;
    if (isVideo) {
      ctrIv = List<int>.generate(16, (_) => random.nextInt(256));
    }

    // 5. Encrypt
    final encryptedChunkPaths = await _orchestrator.processFileForUpload(
      sourceFile, 
      dekBytes,
      ctrIv: ctrIv,
    );

    // Calculate plaintext file hash
    final hashStr = await _calculateFileHash(sourceFile);

    // 6. Generate manifest captions & handoff to Telegram in parallel
    final masterKey = _ref.read(masterKeyProvider);
    final fileId = _uuid.v4();
    
    // Store metadata temporarily in queue item's errorMessage: targetFolderId|dekBytes|ctrIv
    final ivPart = ctrIv != null ? base64Encode(ctrIv) : '';
    await (_db.update(_db.transferQueue)..where((q) => q.id.equals(item.id)))
        .write(TransferQueueCompanion(
          errorMessage: drift.Value('$targetFolderId|${dekBytes.join(',')}|$ivPart'),
        ));

    final readyClients = _telegramManager.state.where((c) => c.authState == TelegramAuthState.ready).toList();
    if (readyClients.isEmpty) {
      await (_db.update(_db.transferQueue)..where((q) => q.id.equals(item.id)))
          .write(const TransferQueueCompanion(status: drift.Value('FAILED'), errorMessage: drift.Value('No ready Telegram accounts available.')));
      return;
    }

    final totalChunks = encryptedChunkPaths.length;
    _uploadProgress[fileId] = {};
    
    final List<Future<void>> uploadFutures = [];

    for (int i = 0; i < totalChunks; i++) {
      final path = encryptedChunkPaths[i];
      final normPath = _normalizePath(path);
      
      _activeUploads[normPath] = ActiveUploadInfo(
        queueId: item.id,
        fileId: fileId,
        chunkIndex: i,
        totalChunks: totalChunks,
      );

      final ch = storageChannels.isNotEmpty ? storageChannels[i % storageChannels.length] : null;
      final chunkChannelId = ch != null ? (ch['id'] is String ? int.parse(ch['id']) : ch['id'] as int) : activeChannelId;
      final telegramClient = readyClients[i % readyClients.length];

      String? chunkCaption;
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
          parentFolderId: targetFolderId == 'null' || targetFolderId.isEmpty ? null : targetFolderId,
          masterKey: secretKey,
          hash: hashStr,
          size: item.totalBytes ?? 0,
          mime: mimeType,
          wrappedDekBase64: wrappedDekBase64,
          ctrIvBase64: ctrIv != null ? base64Encode(ctrIv) : null,
          chunkIndex: i,
          isChunked: totalChunks > 1 ? 1 : 0,
        );
      }

      final future = _orchestrator.handoffToTelegram(
        telegramClient, 
        chunkChannelId, 
        [path],
        caption: chunkCaption,
      );
      uploadFutures.add(future);
    }
    
    // Trigger all uploads in parallel
    await Future.wait(uploadFutures);
  }

  Future<void> _finalizeUpload(String localEncryptedPath, Map<String, dynamic> message) async {
    final normPath = _normalizePath(localEncryptedPath);
    final uploadInfo = _activeUploads[normPath];
    if (uploadInfo == null) return;
    final queueId = uploadInfo.queueId;
    final fileId = uploadInfo.fileId;
    final chunkIndex = uploadInfo.chunkIndex;
    final totalChunks = uploadInfo.totalChunks;

    final item = await (_db.select(_db.transferQueue)..where((q) => q.id.equals(queueId))).getSingleOrNull();
    if (item == null) return;

    final metaParts = item.errorMessage?.split('|');
    if (metaParts == null || metaParts.length < 2) return;
    final folderId = metaParts[0];
    final dekBytesString = metaParts[1];
    final ctrIvBase64 = metaParts.length >= 3 ? metaParts[2] : '';
    
    // Insert Chunk Record immediately with actual chunk size
    final messageId = message['id'];
    final channelId = message['chat_id'];
    
    final chunkFile = File(localEncryptedPath);
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

    // Check if all chunks for this upload are complete
    final completedChunks = await (_db.select(_db.chunks)..where((c) => c.fileId.equals(fileId))).get();
    if (completedChunks.length == totalChunks) {
      // Check for Master Key to Wrap DEK
      final masterKey = _ref.read(masterKeyProvider);
      String wrappedDekString = dekBytesString;
      
      if (masterKey != null) {
        final dekBytes = dekBytesString.split(',').map((s) => int.parse(s)).toList();
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

      // Create File Record
      final originalPath = item.fileId!.split('|')[0];
      final fileName = originalPath.split(Platform.pathSeparator).last;
      final mimeType = _getMimeType(fileName);
      
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
          createdAt: drift.Value(DateTime.now()),
        )
      );

      final fileData = await (_db.select(_db.files)..where((f) => f.id.equals(fileId))).getSingle();
        
      // Trigger Background ML Scanner
      _ref.read(mlServiceProvider).processImage(fileData);

      // Mark the queue item as completed
      await (_db.update(_db.transferQueue)..where((q) => q.id.equals(queueId)))
          .write(TransferQueueCompanion(
            status: const drift.Value('COMPLETED'),
            bytesTransferred: drift.Value(item.totalBytes ?? 0),
          ));

      _uploadProgress.remove(fileId);
    }

    // Clean up local temp file
    _activeUploads.remove(normPath);
    
    if (await chunkFile.exists()) {
      await chunkFile.delete();
    }
    
    if (completedChunks.length == totalChunks) {
      final originalPath = item.fileId!.split('|')[0];
      final fileName = originalPath.split(Platform.pathSeparator).last;
      AppLogger.info('Upload Completed and Finalized for $fileName!');
    }
  }

  void dispose() {
    _pollingTimer?.cancel();
    _tdlibSub?.cancel();
  }
}
