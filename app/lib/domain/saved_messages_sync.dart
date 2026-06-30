import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:drift/drift.dart' as drift;
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/features/telegram/telegram_service.dart';
import 'package:aerodrive/core/logger.dart';

class SavedMessagesSync {
  final Ref _ref;
  final AeroDriveDatabase _db;
  final TelegramService _telegram;

  SavedMessagesSync(this._ref, this._db, this._telegram);

  /// Syncs the wrapped Master Key (MK) and Salt to Saved Messages for multi-device login.
  Future<bool> backupMasterKeyManifest(String wrappedMk, String salt) async {
    try {
      final me = await _telegram.sendRequest({'@type': 'getMe'});
      final myId = me['id'] as int?;
      if (myId == null) return false;

      final manifestPayload = 'AERODRIVE_MK_MANIFEST_V1:$wrappedMk:$salt';
      
      // Look for existing MK manifest and delete it
      final history = await _telegram.sendRequest({
        '@type': 'getChatHistory',
        'chat_id': myId,
        'from_message_id': 0,
        'offset': 0,
        'limit': 100,
      });

      if (history['messages'] != null) {
        final messages = history['messages'] as List;
        for (final msg in messages) {
          final content = msg['content'];
          if (content != null && content['@type'] == 'messageText') {
            final text = content['text']?['text'] as String?;
            if (text != null && text.startsWith('AERODRIVE_MK_MANIFEST_V1:')) {
              await _telegram.sendRequest({
                '@type': 'deleteMessages',
                'chat_id': myId,
                'message_ids': [msg['id']],
                'revoke': true,
              });
            }
          }
        }
      }

      await _telegram.sendRequest({
        '@type': 'sendMessage',
        'chat_id': myId,
        'input_message_content': {
          '@type': 'inputMessageText',
          'text': {
            '@type': 'formattedText',
            'text': manifestPayload,
            'entities': [],
          },
        },
      });

      return true;
    } catch (e) {
      AppLogger.error('Failed to backup MK manifest', e);
      return false;
    }
  }

  /// Fetches the wrapped MK and salt from Saved Messages if it exists
  Future<Map<String, String>?> fetchWrappedMasterKey() async {
    try {
      final me = await _telegram.sendRequest({'@type': 'getMe'});
      final myId = me['id'] as int?;
      if (myId == null) return null;

      final history = await _telegram.sendRequest({
        '@type': 'getChatHistory',
        'chat_id': myId,
        'from_message_id': 0,
        'offset': 0,
        'limit': 100,
      });

      if (history['messages'] != null) {
        final messages = history['messages'] as List;
        for (final msg in messages) {
          final content = msg['content'];
          if (content != null && content['@type'] == 'messageText') {
            final text = content['text']?['text'] as String?;
            if (text != null && text.startsWith('AERODRIVE_MK_MANIFEST_V1:')) {
              final parts = text.split(':');
              if (parts.length >= 3) {
                return {
                  'wrappedMk': parts[1],
                  'salt': parts[2],
                };
              }
            }
          }
        }
      }
      return null;
    } catch (e) {
      AppLogger.error('Failed to fetch MK manifest', e);
      return null;
    }
  }

  /// Reads all DB tables into a JSON manifest and sends it to Saved Messages.
  /// The caption contains an encrypted marker prefix for reliable identification.
  Future<bool> backupToSavedMessages(SecretKey masterKey) async {
    try {
      final me = await _telegram.sendRequest({'@type': 'getMe'});
      final myId = me['id'] as int?;
      if (myId == null) {
        AppLogger.warning('SavedMessagesSync: getMe returned no id');
        return false;
      }

      final folders = await _db.select(_db.folders).get();
      final files = await _db.select(_db.files).get();
      final chunks = await _db.select(_db.chunks).get();
      final accounts = await _db.select(_db.accounts).get();
      final channels = await _db.select(_db.channels).get();

      final settings = _ref.read(settingsRepositoryProvider);
      final localSalt = await settings.getSetting('master_password_salt') ?? '';
      final manifest = {
        'v': 3,
        'ts': DateTime.now().toUtc().toIso8601String(),
        'device': await _deviceId(),
        'salt': localSalt,
        'tables': {
          'folders': folders.map((f) => {'id': f.id, 'name': f.name, 'pid': f.parentId, 'col': f.color, 'c': f.createdAt?.toIso8601String(), 'u': f.updatedAt?.toIso8601String()}).toList(),
          'files': files.map((f) => {'id': f.id, 'name': f.name, 'fid': f.folderId, 'sz': f.size, 'mime': f.mimeType, 'enc': f.isEncrypted ? 1 : 0, 'chk': f.isChunked ? 1 : 0, 'hash': f.sha256Hash, 'algo': f.encryptionAlgo, 'c': f.createdAt?.toIso8601String()}).toList(),
          'chunks': chunks.map((c) => {'id': c.id, 'fid': c.fileId, 'idx': c.chunkIndex, 'ch': c.channelId, 'msg': c.messageId, 'sz': c.size}).toList(),
          'accounts': accounts.map((a) => {'id': a.id, 'phone': a.phoneNumber, 'def': a.isDefault ? 1 : 0}).toList(),
          'channels': channels.map((c) => {'id': c.id, 'name': c.name, 'accountId': c.accountId, 'active': c.isActive ? 1 : 0}).toList(),
        },
      };

      final manifestJson = jsonEncode(manifest);

      // Prepend a known marker to the plaintext so we can identify backup
      // messages without decrypting (marker is encrypted too, but after
      // decryption we check it).
      final markedPayload = 'AERODRIVE_BACKUP_V2:' + manifestJson;

      final cipher = AesGcm.with256bits();
      final nonce = cipher.newNonce();
      final secretBox = await cipher.encrypt(
        utf8.encode(markedPayload),
        secretKey: masterKey,
        nonce: nonce,
      );

      final builder = BytesBuilder();
      builder.add(secretBox.nonce);
      builder.add(secretBox.cipherText);
      builder.add(secretBox.mac.bytes);
      final caption = base64Encode(builder.toBytes());

      final tempDir = await getApplicationDocumentsDirectory();
      final manifestFile = File('${tempDir.path}/AeroDrive/sync_manifest.json.enc');
      await manifestFile.writeAsBytes(builder.toBytes());

      // Don't delete previous backups from other devices — keep the latest
      // from each device so cross-device merge picks up all.
      final existingMsgId = await _getExistingBackupMessageId(myId);
      if (existingMsgId != null) {
        await _telegram.sendRequest({
          '@type': 'deleteMessages',
          'chat_id': myId,
          'message_ids': [existingMsgId],
          'revoke': true,
        });
      }

      final uploadResult = await _telegram.sendRequest({
        '@type': 'sendMessage',
        'chat_id': myId,
        'input_message_content': {
          '@type': 'inputMessageDocument',
          'document': {
            '@type': 'inputFileLocal',
            'path': manifestFile.path,
          },
          'caption': {
            '@type': 'formattedText',
            'text': caption,
            'entities': [],
          },
        },
      });

      await manifestFile.delete();

      final messageId = uploadResult['id'] as int?;
      if (messageId != null) {
        await settings.setSetting('saved_messages_backup_msg_id', messageId.toString());
        await settings.setSetting('saved_messages_backup_ts', (manifest["ts"] as String?) ?? '');
        AppLogger.info('SavedMessagesSync: backup sent, msgId=$messageId');
        return true;
      }
      return false;
    } catch (e, s) {
      AppLogger.error('SavedMessagesSync: backup failed', e, s);
      return false;
    }
  }

  /// Fetches ALL backup manifests from Saved Messages and merges into local DB.
  /// Finds the latest backup from each device.
  Future<bool> restoreFromSavedMessages(SecretKey masterKey) async {
    try {
      final me = await _telegram.sendRequest({'@type': 'getMe'});
      final myId = me['id'] as int?;
      if (myId == null) return false;

      final backupMessages = await _findAllBackupMessages(myId);
      if (backupMessages.isEmpty) {
        AppLogger.info('SavedMessagesSync: no backup messages found');
        return false;
      }

      bool anyMerged = false;
      final Set<String> seenDevices = {};

      for (final msg in backupMessages) {
        final deviceId = await _downloadAndMerge(msg, masterKey);
        if (deviceId != null && !seenDevices.contains(deviceId)) {
          seenDevices.add(deviceId);
          anyMerged = true;
          AppLogger.info('SavedMessagesSync: merged from device=$deviceId');
        }
      }

      return anyMerged;
    } catch (e, s) {
      AppLogger.error('SavedMessagesSync: restore failed', e, s);
      return false;
    }
  }

  /// Downloads a backup message, decrypts it, and merges into local DB.
  /// Returns the device ID from the manifest on success, or null on failure.
  Future<String?> _downloadAndMerge(
    Map<String, dynamic> msg,
    SecretKey masterKey,
  ) async {
    try {
      final document = msg['content']?['document']?['document'];
      if (document == null) return null;

      final fileId = document['id'] as int?;
      if (fileId == null) return null;
      await _telegram.downloadFile(fileId);

      // Bug 8 fix: extend poll from 6s (30×200ms) to 60s (120×500ms)
      for (int i = 0; i < 120; i++) {
        final fileInfo = await _telegram.sendRequest({'@type': 'getFile', 'file_id': fileId});
        if (fileInfo['local']?['is_downloading_completed'] == true) {
          // Bug 8 fix: decrypt the DOCUMENT FILE CONTENTS, not the caption text.
          // Telegram truncates captions to 1024 characters — the manifest payload
          // (which can be several KB) is stored in the document file, not the caption.
          final localPath = fileInfo['local']?['path'] as String?;
          if (localPath == null || localPath.isEmpty) return null;

          final encryptedBytes = await File(localPath).readAsBytes();
          if (encryptedBytes.length < 28) return null; // too short to be valid

          return await _mergeManifest(encryptedBytes, masterKey);
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
      AppLogger.warning('SavedMessagesSync: download timed out after 60s for fileId=$fileId');
      return null;
    } catch (e) {
      AppLogger.error('SavedMessagesSync: download/merge failed for msg', e);
      return null;
    }
  }

  /// Scans Saved Messages for all backup messages (up to 200).
  Future<List<Map<String, dynamic>>> _findAllBackupMessages(int chatId) async {
    final List<Map<String, dynamic>> found = [];
    int fromMessageId = 0;

    for (int page = 0; page < 4; page++) {
      final history = await _telegram.sendRequest({
        '@type': 'getChatHistory',
        'chat_id': chatId,
        'from_message_id': fromMessageId,
        // Bug 7 fix: offset=0 fetches messages starting FROM from_message_id
        // going back in time. offset=-1 skips messages and causes gaps in pagination.
        'offset': 0,
        'limit': 50,
        'only_local': false,
      });

      final messages = history['messages'] as List<dynamic>? ?? [];
      if (messages.isEmpty) break;

      for (final msg in messages) {
        final caption = msg['content']?['caption']?['text'] as String?;
        // Caption is used only as an identifier (must be valid base64, length >= 100)
        if (caption != null && _isBackupCaption(caption) && msg is Map) {
          found.add(Map<String, dynamic>.from(msg));
        }
      }

      // Move anchor to the oldest message in this page for next page fetch
      fromMessageId = (messages.last['id'] as int?) ?? 0;
      if (fromMessageId <= 1) break;
    }

    // Sort newest first
    found.sort((a, b) => ((b['id'] as int?) ?? 0).compareTo((a['id'] as int?) ?? 0));
    return found;
  }

  /// Checks if a caption looks like an AeroDrive backup (valid base64, right length).
  bool _isBackupCaption(String caption) {
    if (caption.length < 100) return false;
    try {
      final bytes = base64Decode(caption);
      // AES-GCM encrypted blob: 12 nonce + ciphertext + 16 MAC
      return bytes.length >= 28;
    } catch (_) {
      return false;
    }
  }

  Future<int?> _getExistingBackupMessageId(int chatId) async {
    final settings = _ref.read(settingsRepositoryProvider);
    final savedId = await settings.getSetting('saved_messages_backup_msg_id');
    if (savedId != null) {
      final id = int.tryParse(savedId);
      if (id != null) return id;
    }

    // Search through recent messages (up to 200)
    int fromMessageId = 0;
    for (int page = 0; page < 4; page++) {
      final history = await _telegram.sendRequest({
        '@type': 'getChatHistory',
        'chat_id': chatId,
        'from_message_id': fromMessageId,
        'offset': 0,
        'limit': 50,
        'only_local': false,
      });

      final messages = history['messages'] as List<dynamic>? ?? [];
      for (final msg in messages) {
        final caption = msg['content']?['caption']?['text'] as String?;
        if (caption != null && _isBackupCaption(caption)) {
          return msg['id'] as int?;
        }
      }

      fromMessageId = messages.isNotEmpty ? messages.last['id'] as int : 0;
      if (fromMessageId <= 1) break;
    }
    return null;
  }

  /// Decrypts raw encrypted bytes from the downloaded backup document file
  /// and merges its contents into the local DB.
  ///
  /// Bug 8 fix: the manifest payload is stored in the DOCUMENT FILE, not the
  /// caption (which Telegram truncates to 1024 chars). The caption is only used
  /// as a quick identity check to detect backup messages without downloading.
  Future<String?> _mergeManifest(List<int> encryptedBytes, SecretKey masterKey) async {
    try {
      if (encryptedBytes.length < 28) return null;

      final nonce = encryptedBytes.sublist(0, 12);
      final cipherText = encryptedBytes.sublist(12, encryptedBytes.length - 16);
      final macBytes = encryptedBytes.sublist(encryptedBytes.length - 16);

      final cipher = AesGcm.with256bits();
      final plainText = await cipher.decrypt(
        SecretBox(Uint8List.fromList(cipherText), nonce: nonce, mac: Mac(macBytes)),
        secretKey: masterKey,
      );

      final decoded = utf8.decode(plainText);

      // Strip marker prefix if present (v2+ format)
      final jsonStr = decoded.startsWith('AERODRIVE_BACKUP_V2:')
          ? decoded.substring('AERODRIVE_BACKUP_V2:'.length)
          : decoded;

      final parsed = jsonDecode(jsonStr);
      if (parsed is! Map<String, dynamic>) return null;
      final manifest = parsed;
      final tables = manifest['tables'] as Map<String, dynamic>?;
      if (tables == null) return null;

      final manifestDevice = manifest['device'] as String?;
      final myDevice = await _cachedDeviceId();

      if (manifestDevice == myDevice) {
        AppLogger.info('SavedMessagesSync: skipping own backup from $myDevice');
        return null;
      }

      // Adopt the remote device's salt so both devices derive the same key from the same password
      final remoteSalt = manifest['salt'] as String?;
      if (remoteSalt != null && remoteSalt.isNotEmpty) {
        final settings = _ref.read(settingsRepositoryProvider);
        final localSalt = await settings.getSetting('master_password_salt');
        if (remoteSalt != localSalt) {
          await settings.setSetting('master_password_salt', remoteSalt);
          AppLogger.info('SavedMessagesSync: adopted salt from device=$manifestDevice — re-lock & unlock to unify keys');
        }
      }

      await _db.transaction(() async {
        // Merge folders — skip existing
        final remoteFolders = tables['folders'] as List<dynamic>? ?? [];
        for (final f in remoteFolders) {
          if (f is! Map) continue;
          final id = f['id'];
          if (id is! String) continue;
          final existing = await (_db.select(_db.folders)..where((t) => t.id.equals(id))).getSingleOrNull();
          if (existing == null) {
            await _db.into(_db.folders).insert(FoldersCompanion.insert(
              id: id,
              name: (f['name'] as String?) ?? '',
              parentId: drift.Value(f['pid'] as String?),
              color: drift.Value(f['col'] as String?),
            ));
          }
        }

        // Merge files — skip existing
        final remoteFiles = tables['files'] as List<dynamic>? ?? [];
        for (final f in remoteFiles) {
          if (f is! Map) continue;
          final id = f['id'];
          if (id is! String) continue;
          final existing = await (_db.select(_db.files)..where((t) => t.id.equals(id))).getSingleOrNull();
          if (existing == null) {
            await _db.into(_db.files).insert(FilesCompanion.insert(
              id: id,
              name: (f['name'] as String?) ?? '',
              folderId: drift.Value(f['fid'] as String?),
              size: drift.Value(f['sz'] as int? ?? 0),
              mimeType: drift.Value(f['mime'] as String?),
              isEncrypted: drift.Value((f['enc'] as int?) == 1),
              isChunked: drift.Value((f['chk'] as int?) == 1),
              sha256Hash: drift.Value(f['hash'] as String?),
              encryptionAlgo: drift.Value(f['algo'] as String?),
            ));
          }
        }

        // Merge chunks — skip existing
        final remoteChunks = tables['chunks'] as List<dynamic>? ?? [];
        for (final c in remoteChunks) {
          if (c is! Map) continue;
          final id = c['id'];
          if (id is! String) continue;
          final existing = await (_db.select(_db.chunks)..where((t) => t.id.equals(id))).getSingleOrNull();
          if (existing == null) {
            await _db.into(_db.chunks).insert(ChunksCompanion.insert(
              id: id,
              fileId: drift.Value(c['fid'] as String?),
              chunkIndex: drift.Value(c['idx'] as int? ?? 0),
              channelId: drift.Value(c['ch'] as int?),
              messageId: drift.Value(c['msg'] as int?),
              size: drift.Value(c['sz'] as int?),
            ));
          }
        }
      });

      AppLogger.info('SavedMessagesSync: merge complete from device=$manifestDevice @ ${manifest["ts"]}');
      return manifestDevice;
    } catch (e, s) {
      AppLogger.error('SavedMessagesSync: merge failed', e, s);
      return null;
    }
  }

  String? _cachedDeviceIdResult;

  Future<String> _deviceId() async {
    if (_cachedDeviceIdResult != null) return _cachedDeviceIdResult!;
    final settings = _ref.read(settingsRepositoryProvider);
    var deviceId = await settings.getSetting('device_id');
    if (deviceId == null) {
      deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}_${(Random().nextInt(99999))}';
      await settings.setSetting('device_id', deviceId);
    }
    _cachedDeviceIdResult = deviceId;
    return deviceId;
  }

  Future<String> _cachedDeviceId() async {
    return _deviceId();
  }
}

final savedMessagesSyncProvider = Provider<SavedMessagesSync>((ref) {
  final db = ref.read(databaseProvider);
  final telegram = ref.read(telegramServiceProvider.notifier);
  return SavedMessagesSync(ref, db, telegram);
});
