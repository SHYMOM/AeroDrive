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
import 'package:aerodrive/domain/upload_orchestrator.dart';
import 'package:aerodrive/core/logger.dart';
import 'package:aerodrive/domain/recovery/manifest_encoder.dart';

class ActiveUploadInfo {
  final String queueId;
  final String fileId;
  ActiveUploadInfo({required this.queueId, required this.fileId});
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

  // Maps temporary encrypted chunk path to active upload info
  final Map<String, ActiveUploadInfo> _activeUploads = {};

  UploadQueueService(this._ref, this._db, this._settings, this._telegramManager, this._orchestrator) {
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
            final localPath = document['document']['local']['path'];
            if (localPath != null && _activeUploads.containsKey(localPath)) {
              await _finalizeUpload(localPath, message);
            }
          }
        }
      } else if (type == 'updateMessageSendFailed') {
        final message = event['message'];
        final content = message['content'];
        if (content != null && content['@type'] == 'messageDocument') {
          final document = content['document'];
          if (document != null && document['document'] != null) {
            final localPath = document['document']['local']['path'];
            if (localPath != null && _activeUploads.containsKey(localPath)) {
              final queueId = _activeUploads[localPath]!.queueId;
              await _db.update(_db.transferQueue)
                ..where((q) => q.id.equals(queueId))
                ..write(const TransferQueueCompanion(
                  status: drift.Value('FAILED'),
                  errorMessage: drift.Value('Telegram rejected the upload.'),
                ));
              _activeUploads.remove(localPath);
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
      ..orderBy([(q) => drift.OrderingTerm.asc(q.createdAt)])
      ..limit(1)
    ).getSingleOrNull();

    if (item == null) return;

    // 2. Check if active channel exists
    final activeChannelStr = await _settings.getSetting('active_channel_id');
    if (activeChannelStr == null) {
      // Mark as failed if no channel is set, user must set it and retry
      await (_db.update(_db.transferQueue)..where((q) => q.id.equals(item.id)))
          .write(const TransferQueueCompanion(status: drift.Value('FAILED'), errorMessage: drift.Value('No Storage Channel selected.')));
      return;
    }
    
    final primaryChannelId = int.parse(activeChannelStr);
    final primaryChannelAccountStr = await _settings.getSetting('active_channel_account_id');
    final primaryAccountId = primaryChannelAccountStr ?? 'primary';

    int activeChannelId = primaryChannelId;
    String accountId = primaryAccountId;

    // Load balancing strategy evaluation
    final strategy = await _settings.getSetting('load_balancing_strategy') ?? 'round_robin';
    final savedChannelsJson = await _settings.getSetting('storage_channels_list');
    
    List<Map<String, dynamic>> storageChannels = [];
    if (savedChannelsJson != null && savedChannelsJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(savedChannelsJson);
        storageChannels = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }

    if (storageChannels.isNotEmpty) {
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
        for (final ch in storageChannels) {
          final id = ch['id'];
          final accId = ch['accountId'] ?? 'primary';
          final chId = id is String ? int.parse(id) : id as int;

          final countQuery = await (_db.selectOnly(_db.chunks)
            ..addColumns([_db.chunks.id.count()])
            ..where(_db.chunks.channelId.equals(chId))
          ).getSingle();
          final count = countQuery.read<int>(_db.chunks.id.count()) ?? 0;

          activeChannelId = chId;
          accountId = accId;
          if (count < 1000) {
            break;
          }
        }
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
      }
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

    // 4. Generate random DEK
    final random = Random.secure();
    final dekBytes = List<int>.generate(32, (_) => random.nextInt(256));

    // 5. Encrypt
    final encryptedChunkPaths = await _orchestrator.processFileForUpload(sourceFile, dekBytes);

    // 6. Generate manifest caption if masterKey is available
    final masterKey = _ref.read(masterKeyProvider);
    String? manifestCaption;
    final fileId = _uuid.v4();
    final fileName = sourceFile.path.split(Platform.pathSeparator).last;
    
    if (masterKey != null) {
      final cipher = AesGcm.with256bits();
      final secretKey = await cipher.newSecretKeyFromBytes(masterKey);
      manifestCaption = await ManifestEncoder.encodeFileManifest(
        fileId: fileId,
        fileName: fileName,
        parentFolderId: targetFolderId == 'null' || targetFolderId.isEmpty ? null : targetFolderId,
        masterKey: secretKey,
        dekBytes: dekBytes,
      );
    }

    // 7. Handoff to Telegram
    for (final path in encryptedChunkPaths) {
      _activeUploads[path] = ActiveUploadInfo(queueId: item.id, fileId: fileId);
      await (_db.update(_db.transferQueue)..where((q) => q.id.equals(item.id)))
          .write(TransferQueueCompanion(
            errorMessage: drift.Value('$targetFolderId|${dekBytes.join(',')}'),
          ));
    }
    
    final telegramClient = _telegramManager.getClient(accountId);

    await _orchestrator.handoffToTelegram(
      telegramClient, 
      activeChannelId, 
      encryptedChunkPaths,
      caption: manifestCaption,
    );
  }

  Future<void> _finalizeUpload(String localEncryptedPath, Map<String, dynamic> message) async {
    final uploadInfo = _activeUploads[localEncryptedPath];
    if (uploadInfo == null) return;
    final queueId = uploadInfo.queueId;
    final fileId = uploadInfo.fileId;

    final item = await (_db.select(_db.transferQueue)..where((q) => q.id.equals(queueId))).getSingleOrNull();
    if (item == null) return;

    final metaParts = item.errorMessage?.split('|');
    if (metaParts == null || metaParts.length < 2) return;
    final folderId = metaParts[0];
    final dekBytesString = metaParts[1];
    
    // Check for Master Key to Wrap DEK
    final masterKey = _ref.read(masterKeyProvider);
    String wrappedDekString = dekBytesString; // Fallback to plaintext array if no password set
    
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
      
      // Store as: base64(nonce) + "|" + base64(mac) + "|" + base64(ciphertext)
      wrappedDekString = '${base64Encode(secretBox.nonce)}|${base64Encode(secretBox.mac.bytes)}|${base64Encode(secretBox.cipherText)}';
    }

    // Create File Record
    final originalPath = item.fileId!.split('|')[0];
    final fileName = originalPath.split(Platform.pathSeparator).last;
    final messageId = message['id'];
    final channelId = message['chat_id'];
    
    await _db.into(_db.files).insert(
      FilesCompanion.insert(
        id: fileId,
        name: fileName,
        folderId: drift.Value(folderId),
        size: drift.Value(item.totalBytes),
        isEncrypted: const drift.Value(true),
        sha256Hash: drift.Value(wrappedDekString),
        createdAt: drift.Value(DateTime.now()),
      )
    );

    // Create Chunk Record
    await _db.into(_db.chunks).insert(
      ChunksCompanion.insert(
        id: _uuid.v4(),
        fileId: drift.Value(fileId),
        chunkIndex: const drift.Value(0),
        channelId: drift.Value(channelId),
        messageId: drift.Value(messageId),
      )
    );

    final fileData = await (_db.select(_db.files)..where((f) => f.id.equals(fileId))).getSingle();
      
    // Trigger Background ML Scanner
    _ref.read(mlServiceProvider).processImage(fileData);

    // Clean up
    await (_db.delete(_db.transferQueue)..where((q) => q.id.equals(queueId))).go();
    _activeUploads.remove(localEncryptedPath);
    
    final tempFile = File(localEncryptedPath);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    
    AppLogger.info('Upload Completed and Finalized for $fileName!');
  }

  void dispose() {
    _pollingTimer?.cancel();
    _tdlibSub?.cancel();
  }
}
