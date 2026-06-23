import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';

import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:aerodrive/core/providers/security_providers.dart';
import 'package:aerodrive/features/telegram/telegram_manager.dart';
import 'package:aerodrive/domain/download_orchestrator.dart';
import 'package:aerodrive/core/logger.dart';

class DownloadQueueService {
  final ProviderRef _ref;
  final AeroDriveDatabase _db;
  final TelegramManager _telegramManager;
  final DownloadOrchestrator _orchestrator;
  
  Timer? _pollingTimer;
  StreamSubscription? _tdlibSub;
  bool _isProcessing = false;

  // Maps remote TDLib file_id to the transferQueue ID
  final Map<int, String> _activeDownloads = {};

  DownloadQueueService(this._ref, this._db, this._telegramManager, this._orchestrator) {
    _startPolling();
    _listenToTdlibEvents();
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

  void _listenToTdlibEvents() {
    _tdlibSub = _telegramManager.allEvents.listen((event) async {
      final type = event['@type'];
      
      if (type == 'updateFile') {
        final file = event['file'];
        final fileId = file['id'];
        
        if (_activeDownloads.containsKey(fileId)) {
          final local = file['local'];
          if (local != null && local['is_downloading_completed'] == true) {
            final localPath = local['path'];
            await _finalizeDownload(fileId, localPath);
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

    final dbChunk = await (_db.select(_db.chunks)..where((c) => c.fileId.equals(item.fileId!))).getSingleOrNull();
    if (dbChunk == null || dbChunk.messageId == null || dbChunk.channelId == null) {
      await (_db.update(_db.transferQueue)..where((q) => q.id.equals(item.id)))
          .write(const TransferQueueCompanion(status: drift.Value('FAILED'), errorMessage: drift.Value('Chunk metadata missing.')));
      return;
    }

    // 4. Ask Telegram for the message to get the remote file ID
    try {
      final settingsStr = await _ref.read(settingsRepositoryProvider).getSetting('storage_channels_list');
      String targetAccountId = 'primary';
      if (settingsStr != null) {
        try {
          final List<dynamic> channels = jsonDecode(settingsStr);
          final channelInfo = channels.cast<Map<String,dynamic>>().firstWhere((c) => c['id'] == dbChunk.channelId, orElse: () => {});
          targetAccountId = channelInfo['accountId'] ?? 'primary';
        } catch (_) {}
      }
      final telegramClient = _telegramManager.getClient(targetAccountId);

      final message = await telegramClient.getMessage(dbChunk.channelId!, dbChunk.messageId!);
      
      final content = message['content'];
      if (content != null && content['@type'] == 'messageDocument') {
        final document = content['document'];
        if (document != null && document['document'] != null) {
          final remoteFileId = document['document']['id'];
          
          _activeDownloads[remoteFileId] = item.id;
          
          // 5. Trigger download
          await telegramClient.downloadFile(remoteFileId);
        } else {
          throw Exception("No document found in message");
        }
      } else {
        throw Exception("Message is not a document");
      }
    } catch (e) {
      await (_db.update(_db.transferQueue)..where((q) => q.id.equals(item.id)))
          .write(TransferQueueCompanion(status: const drift.Value('FAILED'), errorMessage: drift.Value(e.toString())));
    }
  }

  Future<void> _finalizeDownload(int remoteFileId, String localEncryptedPath) async {
    final queueId = _activeDownloads[remoteFileId];
    if (queueId == null) return;

    final item = await (_db.select(_db.transferQueue)..where((q) => q.id.equals(queueId))).getSingleOrNull();
    if (item == null || item.fileId == null) return;

    final dbFile = await (_db.select(_db.files)..where((f) => f.id.equals(item.fileId!))).getSingleOrNull();
    if (dbFile == null || dbFile.sha256Hash == null) return; // DEK is in sha256Hash for Phase 2/3

    try {
      final dekBytesStr = dbFile.sha256Hash!;
      List<int> dekBytes;
      
      final masterKey = _ref.read(masterKeyProvider);
      
      if (dekBytesStr.contains('|') && masterKey != null) {
        // Unwrapping
        final parts = dekBytesStr.split('|');
        if (parts.length == 3) {
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
      } else {
        // Fallback or Legacy Plaintext Array
        dekBytes = dekBytesStr.split(',').map((s) => int.parse(s)).toList();
      }

      // Decrypt!
      final decryptedFile = await _orchestrator.processFileForDownload(
        File(localEncryptedPath),
        dbFile.name,
        dekBytes
      );

      // Clean up queue
      await (_db.delete(_db.transferQueue)..where((q) => q.id.equals(queueId))).go();
      _activeDownloads.remove(remoteFileId);
      
      AppLogger.info('Download Completed and Decrypted: ${decryptedFile.path}');

    } catch (e) {
      AppLogger.error('Decryption failed for $remoteFileId', e);
      await (_db.update(_db.transferQueue)..where((q) => q.id.equals(queueId)))
          .write(TransferQueueCompanion(status: const drift.Value('FAILED'), errorMessage: drift.Value('Decryption failed: $e')));
    }
  }

  void dispose() {
    _pollingTimer?.cancel();
    _tdlibSub?.cancel();
  }
}
