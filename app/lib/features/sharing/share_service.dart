import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random;

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/logger.dart';
import '../../core/providers.dart';
import '../../core/providers/security_providers.dart';
import '../../data/db/database.dart';
import '../../core/providers/repository_providers.dart';
import '../../data/crypto/encryption_engine.dart';
import '../../domain/recovery/manifest_encoder.dart';
import '../../domain/sync/config_sync_service.dart';
import '../../features/telegram/telegram_service.dart';

class SharePasswordRequiredException implements Exception {
  final String message;
  SharePasswordRequiredException(this.message);
  @override
  String toString() => message;
}

class ShareRegistryEntry {
  final String id;
  final String name;
  final bool isFolder;
  final int channelId;
  final int manifestMessageId;
  final List<int> messageIds; // Includes chunk messages and manifest message ID for revocation
  final DateTime createdAt;
  final bool revoked;

  ShareRegistryEntry({
    required this.id,
    required this.name,
    required this.isFolder,
    required this.channelId,
    required this.manifestMessageId,
    required this.messageIds,
    required this.createdAt,
    required this.revoked,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'is_folder': isFolder,
    'channel_id': channelId,
    'manifest_message_id': manifestMessageId,
    'message_ids': messageIds,
    'created_at': createdAt.millisecondsSinceEpoch,
    'revoked': revoked,
  };

  factory ShareRegistryEntry.fromJson(Map<String, dynamic> json) => ShareRegistryEntry(
    id: json['id'] as String,
    name: json['name'] as String,
    isFolder: json['is_folder'] as bool? ?? false,
    channelId: json['channel_id'] as int,
    manifestMessageId: json['manifest_message_id'] as int,
    messageIds: (json['message_ids'] as List).cast<int>(),
    createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int),
    revoked: json['revoked'] as bool? ?? false,
  );
}

class ShareService {
  ShareService(this._ref);
  final Ref _ref;
  final Uuid _uuid = const Uuid();

  // Helper encryption methods using AesGcm
  Future<String> _encryptData(String plaintext, List<int> keyBytes) async {
    final cipher = AesGcm.with256bits();
    final secretKey = await cipher.newSecretKeyFromBytes(keyBytes);
    final secretBox = await cipher.encrypt(utf8.encode(plaintext), secretKey: secretKey);
    return base64Encode(secretBox.concatenation());
  }

  Future<String> _decryptData(String ciphertextBase64, List<int> keyBytes) async {
    final cipher = AesGcm.with256bits();
    final secretKey = await cipher.newSecretKeyFromBytes(keyBytes);
    final concatenationBytes = base64Decode(ciphertextBase64);
    final secretBox = SecretBox.fromConcatenation(concatenationBytes, nonceLength: 12, macLength: 16);
    final decryptedBytes = await cipher.decrypt(secretBox, secretKey: secretKey);
    return utf8.decode(decryptedBytes);
  }

  Future<List<int>> _deriveKeyFromPassword(String password) async {
    final bytes = utf8.encode(password);
    final hash = await Sha256().hash(bytes);
    return hash.bytes;
  }

  // --- SHARE REGISTRY READ/WRITE METHODS (Config Channel) ---

  Future<int?> _resolveConfigChannel() async {
    final configSync = _ref.read(configSyncServiceProvider);
    return await configSync.findConfigChannel();
  }

  Future<List<ShareRegistryEntry>> getShareRegistry() async {
    final telegram = _ref.read(telegramServiceProvider.notifier);
    final masterKeyBytes = _ref.read(masterKeyProvider);
    if (masterKeyBytes == null) {
      AppLogger.warning('ShareService: Vault is locked - cannot read Share Registry');
      return [];
    }

    final configChatId = await _resolveConfigChannel();
    if (configChatId == null) {
      AppLogger.warning('ShareService: Config channel not found - registry is empty');
      return [];
    }

    try {
      var searchRes = await telegram.sendRequest({
        "@type": "searchChatMessages",
        "chat_id": configChatId,
        "query": "SHARE_REGISTRY_v2",
        "limit": 5
      });

      List<dynamic> messages = searchRes['messages'] ?? [];
      if (messages.isEmpty) {
        final history = await telegram.sendRequest({
          "@type": "getChatHistory",
          "chat_id": configChatId,
          "from_message_id": 0,
          "offset": 0,
          "limit": 30,
          "only_local": false,
        });
        messages = history['messages'] ?? [];
      }

      for (final msg in messages) {
        final content = msg['content'];
        if (content == null) continue;

        if (content['@type'] == 'messageText') {
          final text = content['text']?['text'] as String?;
          if (text != null && (text.contains('SHARE_REGISTRY_v2') || text.contains('SHARE_REGISTRY_v1'))) {
            final lines = text.split('\n');
            final payloadLine = lines.lastWhere((l) => l.trim().isNotEmpty);
            final decryptedText = await _decryptData(payloadLine.trim(), masterKeyBytes);
            final List decoded = jsonDecode(decryptedText);
            return decoded.map((e) => ShareRegistryEntry.fromJson(e)).toList();
          }
        }

        if (content['@type'] == 'messageDocument') {
          final captionText = content['caption']?['text'] as String?;
          if (captionText != null && (captionText.contains('SHARE_REGISTRY_v2') || captionText.contains('SHARE_REGISTRY_v1'))) {
            final doc = content['document'];
            if (doc != null && doc['document'] != null) {
              final fileId = doc['document']['id'] as int;
              
              await telegram.downloadFile(fileId);
              String? localPath;
              for (var attempt = 0; attempt < 60; attempt++) {
                final fileInfo = await telegram.sendRequest({'@type': 'getFile', 'file_id': fileId});
                final local = fileInfo['local'] as Map<String, dynamic>?;
                if (local != null && local['is_downloading_completed'] == true && local['path'] != null && (local['path'] as String).isNotEmpty) {
                  localPath = local['path'] as String;
                  break;
                }
                await Future.delayed(const Duration(milliseconds: 250));
              }

              if (localPath != null) {
                final file = File(localPath);
                final encryptedContent = await file.readAsString();
                final decryptedText = await _decryptData(encryptedContent.trim(), masterKeyBytes);
                final List decoded = jsonDecode(decryptedText);
                return decoded.map((e) => ShareRegistryEntry.fromJson(e)).toList();
              }
            }
          }
        }
      }
    } catch (e, s) {
      AppLogger.error('ShareService: Error reading Share Registry', e, s);
    }
    return [];
  }

  Future<void> _updateShareRegistry(List<ShareRegistryEntry> registry) async {
    final telegram = _ref.read(telegramServiceProvider.notifier);
    final masterKeyBytes = _ref.read(masterKeyProvider);
    if (masterKeyBytes == null) return;

    final configChatId = await _resolveConfigChannel();
    if (configChatId == null) {
      AppLogger.warning('ShareService: Config channel not found - cannot update registry');
      return;
    }

    try {
      final registryJson = jsonEncode(registry.map((e) => e.toJson()).toList());
      final encryptedBase64 = await _encryptData(registryJson, masterKeyBytes);

      final searchRes = await telegram.sendRequest({
        "@type": "searchChatMessages",
        "chat_id": configChatId,
        "query": "SHARE_REGISTRY_v2",
        "limit": 10
      });
      final List<dynamic> oldMessages = searchRes['messages'] ?? [];
      final List<int> oldMessageIds = oldMessages.map((m) => m['id'] as int).toList();

      if (encryptedBase64.length <= 3500) {
        final fullText = '⚠️ AeroDrive Share Registry [SHARE_REGISTRY_v2] ⚠️\n'
            'DO NOT DELETE OR EDIT THIS MESSAGE\n\n'
            '$encryptedBase64';

        if (oldMessageIds.isNotEmpty) {
          await telegram.sendRequest({
            "@type": "deleteMessages",
            "chat_id": configChatId,
            "message_ids": oldMessageIds,
            "revoke": true
          });
        }

        final sent = await telegram.sendRequest({
          "@type": "sendMessage",
          "chat_id": configChatId,
          "input_message_content": {
            "@type": "inputMessageText",
            "text": {
              "@type": "formattedText",
              "text": fullText,
              "entities": []
            },
            "disable_web_page_preview": true,
            "clear_draft": true
          }
        });
        
        if (sent['@type'] != 'error') {
          try {
            await telegram.sendRequest({
              "@type": "pinChatMessage",
              "chat_id": configChatId,
              "message_id": sent['id'],
              "disable_notification": true,
              "only_for_self": false
            });
          } catch (pinError) {
            AppLogger.warning('ShareService: Could not pin registry message (non-fatal): $pinError');
          }
        }
      } else {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/shares_registry.reg');
        await tempFile.writeAsString(encryptedBase64);

        if (oldMessageIds.isNotEmpty) {
          await telegram.sendRequest({
            "@type": "deleteMessages",
            "chat_id": configChatId,
            "message_ids": oldMessageIds,
            "revoke": true
          });
        }

        final sent = await telegram.uploadDocument(
          configChatId,
          tempFile.path,
          caption: 'AeroDrive Share Registry [SHARE_REGISTRY_v2]',
        );

        if (sent['@type'] != 'error') {
          try {
            await telegram.sendRequest({
              "@type": "pinChatMessage",
              "chat_id": configChatId,
              "message_id": sent['id'],
              "disable_notification": true,
              "only_for_self": false
            });
          } catch (pinError) {
            AppLogger.warning('ShareService: Could not pin registry message (non-fatal): $pinError');
          }
        }

        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
      AppLogger.info('ShareService: Registry successfully updated.');
    } catch (e, s) {
      AppLogger.error('ShareService: Error updating Share Registry', e, s);
    }
  }

  // --- PUBLIC SHARE CHANNEL SETUP ---

  Future<void> _archiveAndMute(TelegramService telegramService, int chatId) async {
    await telegramService.sendRequest({
      "@type": "addChatToList",
      "chat_id": chatId,
      "chat_list": {"@type": "chatListArchive"}
    });

    await telegramService.sendRequest({
      "@type": "setChatNotificationSettings",
      "chat_id": chatId,
      "notification_settings": {
        "@type": "chatNotificationSettings",
        "use_default_mute_for": false,
        "mute_for": 2147483647,
        "use_default_sound": false,
        "sound_id": 0,
        "use_default_show_preview": false,
        "show_preview": false,
        "use_default_disable_pinned_message_notifications": false,
        "disable_pinned_message_notifications": true,
        "use_default_disable_mention_notifications": false,
        "disable_mention_notifications": true
      }
    });
  }

  Future<void> _setChannelIcon(TelegramService telegramService, int chatId) async {
    try {
      final byteData = await rootBundle.load('assets/icon.png');
      final buffer = byteData.buffer;

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/aerodrive_icon.png');
      await tempFile.writeAsBytes(buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));

      await telegramService.sendRequest({
        "@type": "setChatPhoto",
        "chat_id": chatId,
        "photo": {
          "@type": "inputChatPhotoStatic",
          "photo": {
            "@type": "inputFileLocal",
            "path": tempFile.path
          }
        }
      });
      AppLogger.info('ShareService: Set channel icon successfully.');
    } catch (e, s) {
      AppLogger.error('ShareService: Error setting channel icon', e, s);
    }
  }

  Future<Map<String, dynamic>> _getOrCreatePublicShareChannel() async {
    final telegram = _ref.read(telegramServiceProvider.notifier);
    final settingsRepo = _ref.read(settingsRepositoryProvider);

    final storedId = await settingsRepo.getSetting('public_share_channel_id');
    final storedUser = await settingsRepo.getSetting('public_share_channel_username');
    final storedInvite = await settingsRepo.getSetting('public_share_channel_invite');

    if (storedId != null && storedId.isNotEmpty) {
      return {
        'id': int.parse(storedId),
        'username': storedUser,
        'invite': storedInvite,
      };
    }

    final response = await telegram.createNewChannel(
      "AeroDrive Public Shares",
      "AeroDrive Public Share Storage [AERODRIVE_PUBLIC_SHARES_v1]"
    );

    if (response['@type'] == 'error') {
      throw Exception('Failed to create sharing channel: ${response['message']}');
    }

    final int chatId = response['id'];
    int? supergroupId;
    if (response['type'] != null && response['type']['@type'] == 'chatTypeSupergroup') {
      supergroupId = response['type']['supergroup_id'] as int?;
    }

    if (supergroupId == null) {
      try {
        final chat = await telegram.sendRequest({'@type': 'getChat', 'chat_id': chatId});
        if (chat['type'] != null && chat['type']['@type'] == 'chatTypeSupergroup') {
          supergroupId = chat['type']['supergroup_id'] as int?;
        }
      } catch (e) {
        AppLogger.error('Failed to resolve supergroup_id for chat $chatId', e);
      }
    }

    await Future.delayed(const Duration(seconds: 1));

    await _archiveAndMute(telegram, chatId);
    await _setChannelIcon(telegram, chatId);

    var finalUsername = '';
    if (supergroupId != null) {
      for (var attempt = 0; attempt < 5; attempt++) {
        final randSuffix = const Uuid().v4().replaceAll('-', '').substring(0, 10);
        final testUsername = 'aerodrive_shares_$randSuffix';
        
        final res = await telegram.sendRequest({
          "@type": "setSupergroupUsername",
          "supergroup_id": supergroupId,
          "username": testUsername,
        });

        if (res['@type'] != 'error') {
          finalUsername = testUsername;
          break;
        }
      }
    } else {
      AppLogger.error('Cannot set username: supergroup_id is null for chat $chatId');
    }

    final inviteRes = await telegram.sendRequest({
      "@type": "createChatInviteLink",
      "chat_id": chatId,
      "name": "AeroDrive Public Share",
      "creates_join_request": false,
    });
    final inviteLink = inviteRes['invite_link'] as String?;

    await settingsRepo.setSetting('public_share_channel_id', chatId.toString());
    if (finalUsername.isNotEmpty) {
      await settingsRepo.setSetting('public_share_channel_username', finalUsername);
    }
    if (inviteLink != null) {
      await settingsRepo.setSetting('public_share_channel_invite', inviteLink);
    }

    try {
      final configSync = _ref.read(configSyncServiceProvider);
      await configSync.syncConfigToChannel();
    } catch (e) {
      AppLogger.error('ShareService: Failed to sync configuration to channel', e);
    }

    return {
      'id': chatId,
      'username': finalUsername.isNotEmpty ? finalUsername : null,
      'invite': inviteLink,
    };
  }

  // --- RECURSIVE DEK AND FILE METADATA GATHERING ---

  Future<Map<String, dynamic>> _gatherFolderMetadata(String folderId, AeroDriveDatabase db) async {
    final files = await (db.select(db.files)
      ..where((f) => f.folderId.equals(folderId) & f.deletedAt.isNull())
    ).get();

    final subfolders = await (db.select(db.folders)
      ..where((f) => f.parentId.equals(folderId) & f.deletedAt.isNull())
    ).get();

    final List<Map<String, dynamic>> filesJson = [];
    for (final file in files) {
      final chunks = await (db.select(db.chunks)..where((c) => c.fileId.equals(file.id))).get();
      final keyAndIv = await _decryptFileDekAndIv(file);
      final dekBytes = keyAndIv[0];
      final ctrIvBytes = keyAndIv[1];
      
      filesJson.add({
        'id': file.id,
        'name': file.name,
        'size': file.size,
        'mime_type': file.mimeType,
        'dek': base64Encode(dekBytes!),
        'ctr_iv': ctrIvBytes != null ? base64Encode(ctrIvBytes) : null,
        'chunks': chunks.map((c) => {
          'index': c.chunkIndex,
          'size': c.size,
          'message_id': c.messageId,
          'channel_id': c.channelId,
        }).toList(),
      });
    }

    final List<Map<String, dynamic>> subfoldersJson = [];
    for (final sub in subfolders) {
      final metadata = await _gatherFolderMetadata(sub.id, db);
      subfoldersJson.add(metadata);
    }

    final folder = await (db.select(db.folders)..where((f) => f.id.equals(folderId))).getSingle();

    return {
      'id': folder.id,
      'name': folder.name,
      'files': filesJson,
      'subfolders': subfoldersJson,
    };
  }

  Future<List<List<int>?>> _decryptFileDekAndIv(FileData file) async {
    final masterKey = _ref.read(masterKeyProvider);
    if (masterKey == null) throw Exception("Vault is locked");
    if (file.sha256Hash == null) throw Exception("File key is empty");

    final parts = file.sha256Hash!.contains('|') 
        ? file.sha256Hash!.split('|') 
        : file.sha256Hash!.split(':');

    if (parts.length >= 3) {
      final nonce = base64Decode(parts[0]);
      final mac = Mac(base64Decode(parts[1]));
      final cipherText = base64Decode(parts[2]);
      
      final cipher = AesGcm.with256bits();
      final secretKey = await cipher.newSecretKeyFromBytes(masterKey);
      final dekBytes = await cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: mac),
        secretKey: secretKey,
      );

      List<int>? ctrIv;
      if (parts.length >= 4) {
        ctrIv = base64Decode(parts[3]);
      }
      return [dekBytes, ctrIv];
    }
    
    if (file.sha256Hash!.contains(',')) {
      return [file.sha256Hash!.split(',').map((s) => int.parse(s.trim())).toList(), null];
    }
    return [base64Decode(file.sha256Hash!), null];
  }

  Future<File> _downloadTelegramMessageDocument(int channelId, int messageId) async {
    final telegram = _ref.read(telegramServiceProvider.notifier);
    final message = await telegram.sendRequest({
      "@type": "getMessage",
      "chat_id": channelId,
      "message_id": messageId,
    });

    if (message['@type'] == 'error') {
      throw Exception("Failed to retrieve chunk message. The share link might have been revoked by the owner.");
    }

    final content = message['content'];
    if (content == null || content['@type'] != 'messageDocument') {
      throw Exception("Invalid message format: expected messageDocument.");
    }

    final doc = content['document'];
    if (doc == null || doc['document'] == null) {
      throw Exception("Document object not found in chunk message.");
    }

    final fileId = doc['document']['id'] as int;
    await telegram.downloadFile(fileId);

    String? localPath;
    for (var attempt = 0; attempt < 120; attempt++) {
      final fileInfo = await telegram.sendRequest({'@type': 'getFile', 'file_id': fileId});
      final local = fileInfo['local'] as Map<String, dynamic>?;
      if (local != null && local['is_downloading_completed'] == true && local['path'] != null && (local['path'] as String).isNotEmpty) {
        localPath = local['path'] as String;
        break;
      }
      await Future.delayed(const Duration(milliseconds: 250));
    }

    if (localPath == null) {
      throw Exception("Failed to download chunk file from Telegram.");
    }

    return File(localPath);
  }

  Future<void> _copyAndReEncryptFile(
    Map<String, dynamic> fileJson,
    String? targetFolderId,
    AeroDriveDatabase db,
    List<int> receiverMasterKey,
    int receiverChannelId,
  ) async {
    final fileId = fileJson['id'] as String;
    final fileName = fileJson['name'] as String;
    final fileSize = fileJson['size'] as int?;
    final fileMimeType = fileJson['mime_type'] as String?;
    final senderDekBytes = base64Decode(fileJson['dek'] as String);
    final senderCtrIvBytes = fileJson['ctr_iv'] != null ? base64Decode(fileJson['ctr_iv'] as String) : null;
    final chunks = fileJson['chunks'] as List;

    final random = Random.secure();
    final receiverDekBytes = List<int>.generate(32, (_) => random.nextInt(256));
    final isVideo = fileMimeType != null && fileMimeType.startsWith('video/');
    final List<int>? receiverCtrIvBytes = isVideo ? List<int>.generate(16, (_) => random.nextInt(256)) : null;

    final tempDir = await getTemporaryDirectory();
    final engine = EncryptionEngine();
    final telegram = _ref.read(telegramServiceProvider.notifier);

    final List<Map<String, dynamic>> uploadedChunks = [];
    var globalByteOffset = 0;

    for (var i = 0; i < chunks.length; i++) {
      final chunkJson = chunks[i];
      final senderChannelId = chunkJson['channel_id'] as int;
      final senderMessageId = chunkJson['message_id'] as int;
      final chunkSize = chunkJson['size'] as int?;

      final File senderChunkFile = await _downloadTelegramMessageDocument(senderChannelId, senderMessageId);

      final File tempPlaintextChunkFile = File('${tempDir.path}/temp_plaintext_${fileId}_$i.tmp');
      await engine.decryptDiskToStream(
        encryptedChunkFile: senderChunkFile,
        outputFile: tempPlaintextChunkFile,
        dekBytes: senderDekBytes,
        append: false,
        ctrIv: senderCtrIvBytes,
        globalByteOffset: globalByteOffset,
      );

      final tempEncryptedChunkPaths = await engine.encryptStreamToDisk(
        sourceFile: tempPlaintextChunkFile,
        outputDirectory: tempDir.path,
        dekBytes: receiverDekBytes,
        ctrIv: receiverCtrIvBytes,
      );

      final File receiverChunkFile = File(tempEncryptedChunkPaths.first);

      final cipher = AesGcm.with256bits();
      final secretKey = await cipher.newSecretKeyFromBytes(receiverMasterKey);
      final nonce = cipher.newNonce();
      final secretBox = await cipher.encrypt(
        receiverDekBytes,
        secretKey: secretKey,
        nonce: nonce,
      );
      final wrappedDekBase64 = '${base64Encode(secretBox.nonce)}|${base64Encode(secretBox.mac.bytes)}|${base64Encode(secretBox.cipherText)}';

      final chunkCaption = await ManifestEncoder.encodeFileManifest(
        fileId: fileId,
        fileName: fileName,
        parentFolderId: targetFolderId,
        masterKey: secretKey,
        hash: '',
        size: fileSize ?? 0,
        mime: fileMimeType ?? 'application/octet-stream',
        wrappedDekBase64: wrappedDekBase64,
        ctrIvBase64: receiverCtrIvBytes != null ? base64Encode(receiverCtrIvBytes) : null,
        chunkIndex: i,
        totalChunks: chunks.length,
        isChunked: chunks.length > 1 ? 1 : 0,
      );

      final response = await telegram.uploadDocument(
        receiverChannelId,
        receiverChunkFile.path,
        caption: chunkCaption,
      );

      if (response['@type'] == 'error') {
        throw Exception('Failed to upload chunk to storage: ${response['message']}');
      }

      final int messageId = response['id'];
      final int actualChunkSize = await receiverChunkFile.length();

      uploadedChunks.add({
        'index': i,
        'size': actualChunkSize,
        'message_id': messageId,
        'channel_id': receiverChannelId,
      });

      try {
        if (await senderChunkFile.exists()) await senderChunkFile.delete();
        if (await tempPlaintextChunkFile.exists()) await tempPlaintextChunkFile.delete();
        if (await receiverChunkFile.exists()) await receiverChunkFile.delete();
      } catch (_) {}

      globalByteOffset += chunkSize ?? 0;
    }

    final cipher = AesGcm.with256bits();
    final secretKey = await cipher.newSecretKeyFromBytes(receiverMasterKey);
    final nonce = cipher.newNonce();
    final secretBox = await cipher.encrypt(
      receiverDekBytes,
      secretKey: secretKey,
      nonce: nonce,
    );
    var wrappedDekString = '${base64Encode(secretBox.nonce)}|${base64Encode(secretBox.mac.bytes)}|${base64Encode(secretBox.cipherText)}';
    if (receiverCtrIvBytes != null) {
      wrappedDekString = '$wrappedDekString|${base64Encode(receiverCtrIvBytes)}';
    }

    await db.into(db.files).insert(
      FilesCompanion.insert(
        id: fileId,
        name: fileName,
        folderId: drift.Value(targetFolderId),
        size: drift.Value(fileSize),
        mimeType: drift.Value(fileMimeType),
        sha256Hash: drift.Value(wrappedDekString),
        isEncrypted: const drift.Value(true),
        isChunked: drift.Value(chunks.length > 1),
        totalChunks: drift.Value(chunks.length),
        createdAt: drift.Value(DateTime.now()),
        updatedAt: drift.Value(DateTime.now()),
      ),
      mode: drift.InsertMode.insertOrIgnore,
    );

    for (final chunkInfo in uploadedChunks) {
      await db.into(db.chunks).insert(
        ChunksCompanion.insert(
          id: const Uuid().v4(),
          fileId: drift.Value(fileId),
          chunkIndex: drift.Value(chunkInfo['index'] as int),
          channelId: drift.Value(chunkInfo['channel_id'] as int),
          messageId: drift.Value(chunkInfo['message_id'] as int),
          size: drift.Value(chunkInfo['size'] as int?),
        ),
        mode: drift.InsertMode.insertOrIgnore,
      );
    }
  }

  // --- RECURSIVE METADATA INSERTION ---

  Future<void> _importFolderMetadata(
    Map<String, dynamic> metadata,
    String? parentId,
    AeroDriveDatabase db,
    List<int> receiverMasterKey,
    int receiverChannelId,
  ) async {
    final folderId = metadata['id'] as String;
    final folderName = metadata['name'] as String;

    await db.into(db.folders).insert(
      FoldersCompanion.insert(
        id: folderId,
        name: folderName,
        parentId: drift.Value(parentId),
        createdAt: drift.Value(DateTime.now()),
      ),
      mode: drift.InsertMode.insertOrIgnore,
    );

    final files = metadata['files'] as List;
    for (final fileJson in files) {
      await _copyAndReEncryptFile(
        fileJson as Map<String, dynamic>,
        folderId,
        db,
        receiverMasterKey,
        receiverChannelId,
      );
    }

    final subfolders = metadata['subfolders'] as List;
    for (final subJson in subfolders) {
      await _importFolderMetadata(
        subJson as Map<String, dynamic>,
        folderId,
        db,
        receiverMasterKey,
        receiverChannelId,
      );
    }
  }

  // --- GENERATE AND IMPORT SHARE LINKS (Manifest Pointer Flow) ---

  Future<String> generateShareLink({
    FileData? file,
    FolderData? folder,
    String? password,
  }) async {
    if (file == null && folder == null) {
      throw Exception('Either file or folder must be specified for sharing.');
    }

    final db = _ref.read(databaseProvider);
    final telegram = _ref.read(telegramServiceProvider.notifier);

    // 1. Resolve/Create Public Share Channel
    final shareChanInfo = await _getOrCreatePublicShareChannel();
    final int shareChatId = shareChanInfo['id'];
    final String? inviteLink = shareChanInfo['invite'];

    // 2. Gather source chunks and copy-forward them to the Public Share Channel
    final Map<String, dynamic> manifestPayload;
    final List<int> allForwardedMessageIds = [];
    final String name;

    if (file != null) {
      name = file.name;
      final chunks = await (db.select(db.chunks)..where((c) => c.fileId.equals(file.id))).get();
      if (chunks.isEmpty) throw Exception('No uploaded chunks found for file: ${file.name}');

      final int sourceChatId = chunks.first.channelId!;
      final List<int> sourceMessageIds = chunks.map((c) => c.messageId!).toList();

      // Forward chunks copy
      final forwardedMsgs = await telegram.sendRequest({
        "@type": "forwardMessages",
        "chat_id": shareChatId,
        "from_chat_id": sourceChatId,
        "message_ids": sourceMessageIds,
        "send_copy": true,
      });

      if (forwardedMsgs['@type'] == 'error') {
        throw Exception('Failed to forward file chunks to share channel: ${forwardedMsgs['message']}');
      }

      final List messagesList = forwardedMsgs['messages'] ?? [];
      final List<int> newMsgIds = messagesList.map((m) => m['id'] as int).toList();
      allForwardedMessageIds.addAll(newMsgIds);

      final keyAndIv = await _decryptFileDekAndIv(file);
      final dekBytes = keyAndIv[0];
      final ctrIvBytes = keyAndIv[1];

      manifestPayload = {
        'type': 'file',
        'id': file.id,
        'name': file.name,
        'size': file.size,
        'mime_type': file.mimeType,
        'dek': base64Encode(dekBytes!),
        'ctr_iv': ctrIvBytes != null ? base64Encode(ctrIvBytes) : null,
        'invite_link': inviteLink,
        'channel_id': shareChatId,
        'chunks': List.generate(chunks.length, (idx) => {
          'index': chunks[idx].chunkIndex,
          'size': chunks[idx].size,
          'message_id': newMsgIds[idx],
          'channel_id': shareChatId,
        }),
      };
    } else {
      name = folder!.name;
      
      // Recursively gather all folders and files metadata
      final folderMetadata = await _gatherFolderMetadata(folder.id, db);

      // Collect all source chunk message IDs for forwarding
      final List<Map<String, dynamic>> allChunksToForward = [];
      
      void collectChunks(Map<String, dynamic> node) {
        final List files = node['files'] ?? [];
        for (final fileJson in files) {
          final List chunks = fileJson['chunks'] ?? [];
          for (final chunk in chunks) {
            allChunksToForward.add(chunk);
          }
        }
        final List subs = node['subfolders'] ?? [];
        for (final sub in subs) {
          collectChunks(sub);
        }
      }
      
      collectChunks(folderMetadata);

      if (allChunksToForward.isEmpty) {
        throw Exception('Folder is empty or contains no uploaded files.');
      }

      // Group chunks by source channel to forward in batches (max 100 per call)
      final Map<int, List<int>> channelGroups = {};
      for (final chunk in allChunksToForward) {
        final chanId = chunk['channel_id'] as int;
        final msgId = chunk['message_id'] as int;
        channelGroups.putIfAbsent(chanId, () => []).add(msgId);
      }

      final Map<int, int> forwardedMapping = {};
      for (final entry in channelGroups.entries) {
        final srcChanId = entry.key;
        final srcMsgIds = entry.value;

        for (var i = 0; i < srcMsgIds.length; i += 100) {
          final batch = srcMsgIds.sublist(i, i + 100 > srcMsgIds.length ? srcMsgIds.length : i + 100);
          final res = await telegram.sendRequest({
            "@type": "forwardMessages",
            "chat_id": shareChatId,
            "from_chat_id": srcChanId,
            "message_ids": batch,
            "send_copy": true,
          });

          if (res['@type'] == 'error') {
            throw Exception('Failed to forward folder batch: ${res['message']}');
          }

          final List messagesList = res['messages'] ?? [];
          final List<int> newMsgIds = messagesList.map((m) => m['id'] as int).toList();
          allForwardedMessageIds.addAll(newMsgIds);

          for (var j = 0; j < batch.length; j++) {
            forwardedMapping[batch[j]] = newMsgIds[j];
          }
        }
      }

      // Re-map the message IDs in the metadata JSON
      void remapChunkIds(Map<String, dynamic> node) {
        final List files = node['files'] ?? [];
        for (final fileJson in files) {
          final List chunks = fileJson['chunks'] ?? [];
          for (final chunk in chunks) {
            final oldMsgId = chunk['message_id'] as int;
            chunk['message_id'] = forwardedMapping[oldMsgId];
            chunk['channel_id'] = shareChatId;
          }
        }
        final List subs = node['subfolders'] ?? [];
        for (final sub in subs) {
          remapChunkIds(sub);
        }
      }

      remapChunkIds(folderMetadata);
      manifestPayload = {
        'type': 'folder',
        'invite_link': inviteLink,
        'channel_id': shareChatId,
        'folder': folderMetadata,
      };
    }

    // 3. Derive Encryption Key & Encrypt the Share Manifest
    final List<int> keyBytes;
    final String shareKeyFragment;
    final bool hasPassword = password != null && password.isNotEmpty;

    if (hasPassword) {
      keyBytes = await _deriveKeyFromPassword(password);
      shareKeyFragment = '';
    } else {
      keyBytes = List<int>.generate(32, (_) => Uuid().v4().codeUnitAt(0) % 256);
      shareKeyFragment = base64UrlEncode(keyBytes);
    }

    final encryptedManifestBase64 = await _encryptData(jsonEncode(manifestPayload), keyBytes);
    final String fullManifestText = '⚠️ AeroDrive Share Manifest [SHARE_MANIFEST_v1] ⚠️\n'
        'DO NOT DELETE OR EDIT THIS MESSAGE\n\n'
        '$encryptedManifestBase64';

    // 4. Send Manifest Message to the Public Share Channel
    final sentManifestMsg = await telegram.sendRequest({
      "@type": "sendMessage",
      "chat_id": shareChatId,
      "input_message_content": {
        "@type": "inputMessageText",
        "text": {
          "@type": "formattedText",
          "text": fullManifestText,
          "entities": []
        },
        "disable_web_page_preview": true,
        "clear_draft": true
      }
    });

    if (sentManifestMsg['@type'] == 'error') {
      throw Exception('Failed to post share manifest to Telegram channel: ${sentManifestMsg['message']}');
    }

    final int manifestMessageId = sentManifestMsg['id'];
    
    // Add the manifest message itself to the list of message IDs for revocation
    allForwardedMessageIds.add(manifestMessageId);

    // 5. Generate Zero-Knowledge Share link pointing to this Manifest
    final String shareId = _uuid.v4();
    final String publicUrl;

    final payloadMap = {
      'invite': inviteLink ?? '',
      'channelId': shareChatId,
      'manifest': manifestMessageId,
      'id': shareId,
    };
    final payloadStr = jsonEncode(payloadMap);
    final encryptedPayloadStr = await _encryptData(payloadStr, keyBytes);
    final pParam = Uri.encodeComponent(encryptedPayloadStr);

    if (hasPassword) {
      publicUrl = 'aerodrive://share?p=$pParam&hasPassword=1';
    } else {
      publicUrl = 'aerodrive://share?p=$pParam#$shareKeyFragment';
    }

    // 6. Update the Config Channel Share Registry Pointer
    final registry = await getShareRegistry();
    registry.add(ShareRegistryEntry(
      id: shareId,
      name: name,
      isFolder: folder != null,
      channelId: shareChatId,
      manifestMessageId: manifestMessageId,
      messageIds: allForwardedMessageIds, // Tiny pointer containing chunk & manifest msg IDs
      createdAt: DateTime.now(),
      revoked: false,
    ));
    await _updateShareRegistry(registry);

    return publicUrl;
  }

  Future<void> importShareLink(String url, {String? password, String? targetFolderId}) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'aerodrive' || uri.host != 'share') {
      if (!url.startsWith('aerodrive://share')) {
        throw Exception("Invalid share link format");
      }
    }

    final pParam = uri.queryParameters['p'];
    if (pParam == null) {
      throw Exception("Invalid link: missing encrypted data payload");
    }

    final encryptedPayloadStr = Uri.decodeComponent(pParam);
    final hasPassword = uri.queryParameters['hasPassword'] == '1';

    // 1. Resolve Decryption Key
    final List<int> keyBytes;
    if (hasPassword) {
      if (password == null || password.isEmpty) {
        throw SharePasswordRequiredException("This link is password protected. Enter password to decrypt.");
      }
      keyBytes = await _deriveKeyFromPassword(password);
    } else {
      final fragment = uri.fragment;
      if (fragment.isEmpty) {
        throw Exception("Invalid link: missing share fragment key");
      }
      keyBytes = base64Url.decode(fragment);
    }

    // 2. Decrypt Payload
    final String decryptedPayloadJson;
    try {
      decryptedPayloadJson = await _decryptData(encryptedPayloadStr, keyBytes);
    } catch (_) {
      throw Exception(hasPassword ? "Incorrect password. Please try again." : "Failed to decrypt share link. Key might be invalid.");
    }

    final Map<String, dynamic> payload = jsonDecode(decryptedPayloadJson);
    final inviteLink = payload['invite'] as String?;
    final int shareChannelId = payload['channelId'] as int;
    final int manifestMessageId = payload['manifest'] as int;

    // 3. Auto-Join Telegram Channel
    final telegram = _ref.read(telegramServiceProvider.notifier);
    if (inviteLink != null && inviteLink.isNotEmpty) {
      try {
        await telegram.sendRequest({
          "@type": "joinChatByInviteLink",
          "invite_link": inviteLink,
        });
      } catch (e) {
        AppLogger.warning('ShareService: Join share channel failed (User might already be a member): $e');
      }
    }

    // 4. Fetch the Share Manifest message from the Public Share Channel
    final manifestMsg = await telegram.sendRequest({
      "@type": "getMessage",
      "chat_id": shareChannelId,
      "message_id": manifestMessageId,
    });

    if (manifestMsg['@type'] == 'error') {
      throw Exception("Failed to retrieve share manifest. The share link might have been revoked by the owner.");
    }

    final content = manifestMsg['content'];
    if (content == null || content['@type'] != 'messageText') {
      throw Exception("Invalid manifest message format on Telegram.");
    }

    final text = content['text']?['text'] as String?;
    if (text == null || !text.contains('SHARE_MANIFEST_v1')) {
      throw Exception("The message retrieved is not a valid AeroDrive share manifest.");
    }

    final lines = text.split('\n');
    final manifestPayloadCipher = lines.lastWhere((l) => l.trim().isNotEmpty).trim();

    // 5. Decrypt Manifest using keyBytes
    final String decryptedJson;
    try {
      decryptedJson = await _decryptData(manifestPayloadCipher, keyBytes);
    } catch (_) {
      throw Exception("Failed to decrypt share manifest.");
    }

    final Map<String, dynamic> manifest = jsonDecode(decryptedJson);

    // 6. Reconstruct Database records and download/re-encrypt chunks
    final db = _ref.read(databaseProvider);
    final receiverMasterKey = _ref.read(masterKeyProvider);
    if (receiverMasterKey == null) throw Exception("Vault is locked. Cannot import.");

    final settingsRepo = _ref.read(settingsRepositoryProvider);
    final activeChannelStr = await settingsRepo.getSetting('active_channel_id');
    if (activeChannelStr == null || activeChannelStr.isEmpty) {
      throw Exception("No active storage channel configured. Cannot import file.");
    }
    final int receiverChannelId = int.parse(activeChannelStr);

    final type = manifest['type'] as String;
    if (type == 'file') {
      await _copyAndReEncryptFile(
        manifest,
        targetFolderId,
        db,
        receiverMasterKey,
        receiverChannelId,
      );
    } else {
      final folderMetadata = manifest['folder'] as Map<String, dynamic>;
      await _importFolderMetadata(
        folderMetadata,
        targetFolderId,
        db,
        receiverMasterKey,
        receiverChannelId,
      );
    }
  }

  Future<void> revokeShare(String shareId) async {
    final telegram = _ref.read(telegramServiceProvider.notifier);
    final registry = await getShareRegistry();

    final entryIndex = registry.indexWhere((e) => e.id == shareId);
    if (entryIndex == -1) {
      throw Exception('Share entry not found in Registry.');
    }

    final entry = registry[entryIndex];

    try {
      // Delete chunk messages and manifest message from Public Share Channel
      if (entry.messageIds.isNotEmpty) {
        await telegram.sendRequest({
          "@type": "deleteMessages",
          "chat_id": entry.channelId,
          "message_ids": entry.messageIds,
          "revoke": true,
        });
      }
    } catch (e) {
      AppLogger.warning('ShareService: Failed to delete messages on Telegram during revocation: $e');
    }

    // Remove the tiny pointer from the Config Channel Registry
    registry.removeAt(entryIndex);
    await _updateShareRegistry(registry);
  }
}

final shareServiceProvider = Provider<ShareService>(ShareService.new);
