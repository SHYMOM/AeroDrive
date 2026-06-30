import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:aerodrive/domain/notification_service.dart';

import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:aerodrive/core/providers/security_providers.dart';
import 'package:aerodrive/features/telegram/telegram_manager.dart';
import 'package:aerodrive/features/telegram/telegram_service.dart';
import 'package:aerodrive/domain/download_orchestrator.dart';
import 'package:aerodrive/core/logger.dart';

class ActiveDownloadInfo {
  final String queueId;
  final String fileId;
  final int chunkIndex;
  final int totalChunks;
  final String fileName;
  final DateTime startedAt;
  ActiveDownloadInfo({
    required this.queueId,
    required this.fileId,
    required this.chunkIndex,
    required this.totalChunks,
    required this.fileName,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();
}

class DownloadCompletionEvent {
  final String fileId;
  final String fileName;
  final String filePath;
  final String mimeType;
  DownloadCompletionEvent({
    required this.fileId,
    required this.fileName,
    required this.filePath,
    required this.mimeType,
  });
}

class DownloadQueueService {
  final ProviderRef _ref;
  final AeroDriveDatabase _db;
  final TelegramManager _telegramManager;
  final DownloadOrchestrator _orchestrator;

  final _completionController = StreamController<DownloadCompletionEvent>.broadcast();
  Stream<DownloadCompletionEvent> get onDownloadComplete => _completionController.stream;
  
  Timer? _pollingTimer;
  Timer? _timeoutTimer;
  StreamSubscription? _tdlibSub;
  bool _isProcessing = false;

  final Map<int, ActiveDownloadInfo> _activeDownloads = {};
  final Map<String, Map<int, String>> _downloadedChunkPaths = {};
  final Map<String, Map<int, int>> _downloadProgress = {};
  final Map<String, int> _fileTotalBytes = {};
  
  static const Duration _chunkTimeout = Duration(minutes: 10);
  
  DownloadQueueService(this._ref, this._db, this._telegramManager, this._orchestrator) {
    NotificationService.instance.initialize();
    _startPolling();
    _listenToTdlibEvents();
    _startTimeoutChecker();
  }

  void _startTimeoutChecker() {
    _timeoutTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final now = DateTime.now();
      final timedOut = <int>[];
      for (final entry in _activeDownloads.entries) {
        if (now.difference(entry.value.startedAt) > _chunkTimeout) {
          timedOut.add(entry.key);
        }
      }
      for (final fileId in timedOut) {
        final info = _activeDownloads[fileId]!;
        AppLogger.error('Download chunk timed out for file ${info.fileId}, chunk ${info.chunkIndex}');
        await _markQueueFailed(info.queueId, 'Download timed out after ${_chunkTimeout.inMinutes} minutes');
        _activeDownloads.remove(fileId);
      }
    });
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_isProcessing) return;
      
      _isProcessing = true;
      try {
        await _processNextInQueue();
      } catch (e) {
        AppLogger.error('DownloadQueue Error', e);
      } finally {
        _isProcessing = false;
      }
    });
  }

  Future<void> _markQueueFailed(String queueId, String message) async {
    await (_db.update(_db.transferQueue)..where((q) => q.id.equals(queueId)))
        .write(TransferQueueCompanion(
          status: const drift.Value('FAILED'),
          errorMessage: drift.Value(message),
        ));
  }

  void _listenToTdlibEvents() {
    _tdlibSub = _telegramManager.allEvents.listen((event) async {
      final type = event['@type'];
      
      if (type == 'updateFile') {
        final file = event['file'];
        final fileId = file['id'];
        
        if (_activeDownloads.containsKey(fileId)) {
          final local = file['local'];
          if (local != null) {
            final isCompleted = local['is_downloading_completed'] == true;
            final isActive = local['is_downloading_active'] == true;
            final downloadedSize = local['downloaded_size'] as int? ?? 0;
            final fileSize = file['expected_size'] as int? ?? file['size'] as int? ?? 0;
            final activeInfo = _activeDownloads[fileId]!;
            
            _downloadProgress.putIfAbsent(activeInfo.fileId, () => {})[activeInfo.chunkIndex] = downloadedSize;
            
            final totalDownloaded = _downloadProgress[activeInfo.fileId]!.values.fold<int>(0, (a, b) => a + b);
            final totalFileBytes = _fileTotalBytes[activeInfo.fileId] ?? fileSize;
            
            await (_db.update(_db.transferQueue)..where((q) => q.id.equals(activeInfo.queueId)))
                .write(TransferQueueCompanion(
                  bytesTransferred: drift.Value(totalDownloaded),
                  totalBytes: drift.Value(totalFileBytes),
                ));

            if (isCompleted) {
              final localPath = local['path'] as String?;
              if (localPath == null || localPath.isEmpty) {
                AppLogger.error('Download chunk completed but no local path for file $fileId');
                await _markQueueFailed(activeInfo.queueId, 'Completed chunk has no local path');
                _activeDownloads.remove(fileId);
                return;
              }
              
              _downloadedChunkPaths.putIfAbsent(activeInfo.fileId, () => {})[activeInfo.chunkIndex] = localPath;
              _activeDownloads.remove(fileId);
              
              final completedMap = _downloadedChunkPaths[activeInfo.fileId]!;
              if (completedMap.length == activeInfo.totalChunks) {
                try {
                  final sortedPaths = List<String>.generate(activeInfo.totalChunks, (index) => completedMap[index]!);
                  await _finalizeDownload(activeInfo.queueId, activeInfo.fileId, sortedPaths);
                } catch (e) {
                  AppLogger.error('Failed to finalize download for ${activeInfo.fileId}', e);
                  await _markQueueFailed(activeInfo.queueId, 'Finalization failed: $e');
                }
                
                _downloadedChunkPaths.remove(activeInfo.fileId);
                _downloadProgress.remove(activeInfo.fileId);
                _fileTotalBytes.remove(activeInfo.fileId);
              }
            } else if (!isActive && !isCompleted && downloadedSize > 0) {
              AppLogger.error('Download stalled for file $fileId - download inactive but not completed');
              await _markQueueFailed(activeInfo.queueId, 'Download stalled');
              _activeDownloads.remove(fileId);
            }
          }
        }
      }
    });
  }

  Future<void> _processNextInQueue() async {
    // 1. Get next pending download item
    final item = await (_db.select(_db.transferQueue)
      ..where((q) => q.status.equals('PENDING'))
      ..where((q) => q.type.equals('DOWNLOAD_FILE'))
      ..orderBy([(q) => drift.OrderingTerm.asc(q.createdAt)])
      ..limit(1)
    ).getSingleOrNull();

    if (item == null || item.fileId == null) return;

    // 2. Mark as processing
    await (_db.update(_db.transferQueue)..where((q) => q.id.equals(item.id)))
          .write(const TransferQueueCompanion(status: drift.Value('PROCESSING')));

    // 3. Fetch File and Chunk metadata
    final dbFile = await (_db.select(_db.files)..where((f) => f.id.equals(item.fileId!))).getSingleOrNull();
    if (dbFile == null) {
      await (_db.update(_db.transferQueue)..where((q) => q.id.equals(item.id)))
          .write(const TransferQueueCompanion(status: drift.Value('FAILED'), errorMessage: drift.Value('File not found in DB.')));
      return;
    }

    final dbChunks = await (_db.select(_db.chunks)
      ..where((c) => c.fileId.equals(item.fileId!))
      ..orderBy([(c) => drift.OrderingTerm.asc(c.chunkIndex)])
    ).get();

    if (dbChunks.isEmpty) {
      await (_db.update(_db.transferQueue)..where((q) => q.id.equals(item.id)))
          .write(const TransferQueueCompanion(status: drift.Value('FAILED'), errorMessage: drift.Value('Chunk metadata missing.')));
      return;
    }

    // Count only chunks with valid messageId and channelId
    final validChunks = dbChunks.where((c) => c.messageId != null && c.channelId != null).toList();
    if (validChunks.isEmpty) {
      await (_db.update(_db.transferQueue)..where((q) => q.id.equals(item.id)))
          .write(const TransferQueueCompanion(status: drift.Value('FAILED'), errorMessage: drift.Value('All chunks have missing message or channel IDs.')));
      return;
    }

    final totalChunks = validChunks.length;
    _downloadedChunkPaths[item.fileId!] = {};
    _downloadProgress[item.fileId!] = {};

    final fileSize = dbFile.size ?? 0;
    _fileTotalBytes[item.fileId!] = fileSize;

    await (_db.update(_db.transferQueue)..where((q) => q.id.equals(item.id)))
        .write(TransferQueueCompanion(
          totalBytes: drift.Value(fileSize),
        ));

    final settingsStr = await _ref.read(settingsRepositoryProvider).getSetting('storage_channels_list');
    
    // 4. Request download for each valid chunk in parallel
    for (final dbChunk in validChunks) {
      String targetAccountId = 'primary';
      if (settingsStr != null) {
        try {
          final List<dynamic> channels = jsonDecode(settingsStr);
          final channelInfo = channels.cast<Map<String,dynamic>>().firstWhere((c) => c['id'] == dbChunk.channelId, orElse: () => {});
          targetAccountId = channelInfo['accountId'] ?? 'primary';
        } catch (e) {
          AppLogger.error('DownloadQueue: failed to parse storage channels', e);
        }
      }
      final telegramClient = _telegramManager.getClient(targetAccountId);

      // Check if the client is ready before making requests
      if (telegramClient.authState != TelegramAuthState.ready) {
        await (_db.update(_db.transferQueue)..where((q) => q.id.equals(item.id)))
            .write(TransferQueueCompanion(
              status: const drift.Value('FAILED'),
              errorMessage: drift.Value('Telegram client for $targetAccountId is not ready. Auth state: ${telegramClient.authState.name}'),
            ));
        return;
      }

      try {
        final message = await telegramClient.getMessage(dbChunk.channelId!, dbChunk.messageId!);

        final content = message['content'];
        if (content != null && content['@type'] == 'messageDocument') {
          final document = content['document'];
          if (document != null && document['document'] != null) {
            final remoteFileId = document['document']['id'] as int?;
            if (remoteFileId == null) {
              throw Exception("No file ID in document for chunk ${dbChunk.chunkIndex}");
            }

            _activeDownloads[remoteFileId] = ActiveDownloadInfo(
              queueId: item.id,
              fileId: item.fileId!,
              chunkIndex: dbChunk.chunkIndex ?? 0,
              totalChunks: totalChunks,
              fileName: dbFile.name,
            );

            // 5. Trigger background download
            await telegramClient.downloadFile(remoteFileId);

            // 6. Poll for completion (handles both progress and missing updateFile events)
            String? localPath;
            for (int attempt = 0; attempt < 30; attempt++) {
              await Future.delayed(const Duration(seconds: 1));
              // If event listener already removed this from activeDownloads, skip
              if (!_activeDownloads.containsKey(remoteFileId)) {
                // Check if chunk path was stored by the event listener
                localPath = _downloadedChunkPaths[item.fileId!]?[dbChunk.chunkIndex ?? 0];
                break;
              }
              try {
                final fileInfo = await telegramClient.sendRequest({'@type': 'getFile', 'file_id': remoteFileId});
                final local = fileInfo['local'] as Map<String, dynamic>?;
                if (local != null) {
                  final downloadedSize = local['downloaded_size'] as int? ?? 0;
                  final isCompleted = local['is_downloading_completed'] == true;
                  final totalSize = fileInfo['expected_size'] as int? ?? fileInfo['size'] as int? ?? 0;

                  // Update progress
                  _downloadProgress.putIfAbsent(item.fileId!, () => {})[dbChunk.chunkIndex ?? 0] = downloadedSize;
                  final totalDownloaded = _downloadProgress[item.fileId!]!.values.fold<int>(0, (a, b) => a + b);
                  await (_db.update(_db.transferQueue)..where((q) => q.id.equals(item.id)))
                      .write(TransferQueueCompanion(
                        bytesTransferred: drift.Value(totalDownloaded),
                        totalBytes: drift.Value(_fileTotalBytes[item.fileId!] ?? totalSize),
                      ));

                  if (isCompleted) {
                    localPath = local['path'] as String?;
                    break;
                  }
                }
              } catch (_) {
                // getFile may fail transiently, keep polling
              }
            }

            _activeDownloads.remove(remoteFileId);

            if (localPath != null && localPath.isNotEmpty) {
              _downloadedChunkPaths.putIfAbsent(item.fileId!, () => {})[dbChunk.chunkIndex ?? 0] = localPath;

              final completedMap = _downloadedChunkPaths[item.fileId!]!;
              if (completedMap.length == totalChunks) {
                try {
                  final sortedPaths = List<String>.generate(totalChunks, (index) => completedMap[index]!);
                  await _finalizeDownload(item.id, item.fileId!, sortedPaths);
                } catch (e) {
                  AppLogger.error('Failed to finalize download for ${item.fileId}', e);
                  await _markQueueFailed(item.id, 'Finalization failed: $e');
                }
                _downloadedChunkPaths.remove(item.fileId!);
                _downloadProgress.remove(item.fileId!);
                _fileTotalBytes.remove(item.fileId!);
              }
            } else {
              AppLogger.error('Download chunk ${dbChunk.chunkIndex} failed to download after 30s');
              await _markQueueFailed(item.id, 'Chunk ${dbChunk.chunkIndex} download timed out');
            }
          } else {
            throw Exception("No document found in message for chunk ${dbChunk.chunkIndex}");
          }
        } else {
          throw Exception("Message is not a document for chunk ${dbChunk.chunkIndex}");
        }
      } catch (e) {
        await (_db.update(_db.transferQueue)..where((q) => q.id.equals(item.id)))
            .write(TransferQueueCompanion(status: const drift.Value('FAILED'), errorMessage: drift.Value('Chunk ${dbChunk.chunkIndex} request failed: $e')));
        return;
      }
    }
  }

  Future<void> _finalizeDownload(String queueId, String fileId, List<String> localEncryptedPaths) async {
    final item = await (_db.select(_db.transferQueue)..where((q) => q.id.equals(queueId))).getSingleOrNull();
    if (item == null || item.fileId == null) {
      AppLogger.error('Finalize download failed: queue item not found for $queueId');
      return;
    }

    final dbFile = await (_db.select(_db.files)..where((f) => f.id.equals(item.fileId!))).getSingleOrNull();
    if (dbFile == null) {
      await _markQueueFailed(queueId, 'File not found in database');
      return;
    }
    if (dbFile.sha256Hash == null || dbFile.sha256Hash!.isEmpty) {
      await _markQueueFailed(queueId, 'File has no encryption key (sha256Hash is null/empty)');
      return;
    }

    try {
      final dekBytesStr = dbFile.sha256Hash!;
      List<int> dekBytes;
      
      final masterKey = _ref.read(masterKeyProvider);
      
      if (dekBytesStr.contains('|') && masterKey != null) {
        final parts = dekBytesStr.split('|');
        if (parts.length >= 3) {
          final nonce = base64Decode(parts[0]);
          final mac = Mac(base64Decode(parts[1]));
          final cipherText = base64Decode(parts[2]);
          
          final cipher = AesGcm.with256bits();
          final secretKey = await cipher.newSecretKeyFromBytes(masterKey);
          
          dekBytes = await cipher.decrypt(
            SecretBox(cipherText, nonce: nonce, mac: mac),
            secretKey: secretKey,
          );
        } else {
           throw Exception("Corrupted wrapped DEK payload.");
        }
      } else if (dekBytesStr.contains(',')) {
        dekBytes = dekBytesStr.split(',').map((s) => int.parse(s.trim())).toList();
      } else {
        try {
          dekBytes = base64Decode(dekBytesStr);
        } catch (e) {
          AppLogger.error('DownloadQueue: base64 decode failed for DEK', e);
          throw Exception("Unable to parse DEK from sha256Hash field. Expected base64, comma-separated ints, or wrapped format.");
        }
      }

      final targetDir = await DownloadOrchestrator.ensureDownloadDirectory(dbFile.mimeType);
      final rawOutputPath = '${targetDir.path}${Platform.pathSeparator}${dbFile.name}';
      final outputPath = await DownloadOrchestrator.dedupFilePath(rawOutputPath);

      final decryptedFile = await _orchestrator.processFileForDownload(
        localEncryptedPaths,
        dbFile.name,
        dekBytes,
        outputPath: outputPath,
      );

      await (_db.update(_db.transferQueue)..where((q) => q.id.equals(queueId)))
          .write(TransferQueueCompanion(
            status: const drift.Value('COMPLETED'),
            bytesTransferred: drift.Value(item.totalBytes ?? 0),
          ));

      NotificationService.instance.showDownloadComplete(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        dbFile.name,
        decryptedFile.path,
      );

      _completionController.add(DownloadCompletionEvent(
        fileId: fileId,
        fileName: dbFile.name,
        filePath: decryptedFile.path,
        mimeType: dbFile.mimeType ?? 'application/octet-stream',
      ));
      
      AppLogger.info('Download completed and decrypted: ${decryptedFile.path}');

    } catch (e) {
      AppLogger.error('Decryption failed for file $fileId', e);
      await _markQueueFailed(queueId, 'Decryption failed: $e');
    }
  }

  void dispose() {
    _pollingTimer?.cancel();
    _timeoutTimer?.cancel();
    _tdlibSub?.cancel();
    _completionController.close();
  }
}
