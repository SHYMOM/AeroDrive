import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../core/providers/security_providers.dart';
import '../../data/db/database.dart';

class ShareService {

  ShareService(this._ref);
  final Ref _ref;

  /// Generate a share link with optional [password] protection,
  /// [expiresAt] date, [maxDownloads] limit, or [burnAfterReading].
  Future<ShareLinkData> generateShareLink(
    FileData file, {
    String? password,
    DateTime? expiresAt,
    int? maxDownloads,
    bool burnAfterReading = false,
  }) async {
    final masterKey = _ref.read(masterKeyProvider);
    if (masterKey == null) throw Exception("Vault is locked");

    if (file.sha256Hash == null) throw Exception("File DEK not found");
    if (file.manifestMessageId == null) throw Exception("File is not uploaded yet");

    final db = _ref.read(databaseProvider);

    // Fetch channel ID from chunk mapping
    final dbChunk = await (db.select(db.chunks)..where((c) => c.fileId.equals(file.id))).getSingleOrNull();
    if (dbChunk == null || dbChunk.channelId == null) {
      throw Exception("Chunk metadata missing");
    }
    final channelId = dbChunk.channelId!;

    // Unwrap the DEK
    final parts = file.sha256Hash!.split(':');
    List<int> dekBytes;

    if (parts.length == 3) {
      final nonce = base64Decode(parts[0]);
      final mac = base64Decode(parts[1]);
      final cipherText = base64Decode(parts[2]);

      final cipher = AesGcm.with256bits();
      final secretKey = await cipher.newSecretKeyFromBytes(masterKey);

      dekBytes = await cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: secretKey,
      );
    } else {
      throw Exception("Invalid DEK format");
    }

    final dekBase64 = base64Encode(dekBytes);

    final shareId = const Uuid().v4();
    final token = const Uuid().v4().replaceAll('-', '').substring(0, 16);

    // If password is set, hash it with SHA-256 for storage
    String? passwordHash;
    if (password != null && password.isNotEmpty) {
      final pwBytes = utf8.encode(password);
      final hashBytes = await Sha256().hash(pwBytes);
      passwordHash = base64Encode(hashBytes.bytes);
    }

    // Build URI
    final uriParams = <String, String>{
      'shareId': shareId,
      'channelId': channelId.toString(),
      'msgId': file.manifestMessageId.toString(),
      'name': file.name,
      'size': file.size?.toString() ?? '0',
      'mimeType': file.mimeType ?? 'application/octet-stream',
      'dek': dekBase64,
      'token': token,
    };

    if (password != null && password.isNotEmpty) {
      uriParams['hasPassword'] = '1';
    }
    if (expiresAt != null) {
      uriParams['expires'] = expiresAt.millisecondsSinceEpoch.toString();
    }

    // Insert into DB
    final now = DateTime.now();
    await db.into(db.shareLinks).insert(
      ShareLinksCompanion.insert(
        id: shareId,
        fileId: drift.Value(file.id),
        token: drift.Value(token),
        passwordHash: drift.Value(passwordHash),
        expiresAt: drift.Value(expiresAt),
        maxDownloads: drift.Value(maxDownloads),
        downloadCount: const drift.Value(0),
        burnAfterReading: drift.Value(burnAfterReading),
        createdAt: drift.Value(now),
      ),
    );

    return (db.select(db.shareLinks)..where((s) => s.id.equals(shareId))).getSingle();
  }

  /// Validate a password against the stored hash.
  Future<bool> validatePassword(ShareLinkData link, String password) async {
    if (link.passwordHash == null) return true;
    final pwBytes = utf8.encode(password);
    final hashBytes = await Sha256().hash(pwBytes);
    final computed = base64Encode(hashBytes.bytes);
    return computed == link.passwordHash;
  }

  /// Increment download count; returns true if still valid.
  Future<bool> recordDownload(ShareLinkData link) async {
    final db = _ref.read(databaseProvider);
    final now = DateTime.now();

    // Check expiration
    if (link.expiresAt != null && now.isAfter(link.expiresAt!)) {
      return false;
    }
    // Check max downloads
    if (link.maxDownloads != null && link.downloadCount >= link.maxDownloads!) {
      return false;
    }

    await (db.update(db.shareLinks)..where((s) => s.id.equals(link.id)))
      .write(const ShareLinksCompanion(downloadCount: drift.Value(0)));

    // Increment download_count via raw SQL
    await db.customStatement(
      'UPDATE share_links SET download_count = download_count + 1 WHERE id = ?',
      [link.id],
    );

    // Burn after reading
    if (link.burnAfterReading) {
      await (db.update(db.shareLinks)..where((s) => s.id.equals(link.id)))
        .write(ShareLinksCompanion(
          expiresAt: drift.Value(now),
          maxDownloads: const drift.Value(0),
        ));
    }

    return true;
  }

  Future<void> importShareLink(String url) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'aerodrive' || uri.host != 'share') {
      throw Exception("Invalid share link format");
    }

    final channelIdStr = uri.queryParameters['channelId'];
    final msgIdStr = uri.queryParameters['msgId'];
    final name = uri.queryParameters['name'];
    final sizeStr = uri.queryParameters['size'];
    final mimeType = uri.queryParameters['mimeType'];
    final dekBase64 = uri.queryParameters['dek'];

    if (channelIdStr == null || msgIdStr == null || name == null || dekBase64 == null) {
      throw Exception("Share link is missing required parameters");
    }

    final channelId = int.parse(channelIdStr);
    final msgId = int.parse(msgIdStr);
    final size = int.parse(sizeStr ?? '0');
    final dekBytes = base64Decode(dekBase64);

    final masterKey = _ref.read(masterKeyProvider);
    if (masterKey == null) throw Exception("Vault is locked");

    // Rewrap the DEK with OUR master key
    final cipher = AesGcm.with256bits();
    final secretKey = await cipher.newSecretKeyFromBytes(masterKey);
    final encryptedDek = await cipher.encrypt(dekBytes, secretKey: secretKey);

    final newHash = '${base64Encode(encryptedDek.nonce)}:${base64Encode(encryptedDek.mac.bytes)}:${base64Encode(encryptedDek.cipherText)}';

    final db = _ref.read(databaseProvider);
    final newFileId = const Uuid().v4();

    await db.into(db.files).insert(
      FilesCompanion.insert(
        id: newFileId,
        name: name,
        size: drift.Value(size),
        mimeType: drift.Value(mimeType),
        sha256Hash: drift.Value(newHash),
        manifestMessageId: drift.Value(msgId),
        isEncrypted: const drift.Value(true),
        createdAt: drift.Value(DateTime.now()),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );

    await db.into(db.chunks).insert(
      ChunksCompanion.insert(
        id: const Uuid().v4(),
        fileId: drift.Value(newFileId),
        chunkIndex: const drift.Value(0),
        channelId: drift.Value(channelId),
        messageId: drift.Value(msgId),
        size: drift.Value(size),
      ),
    );
  }
}

final shareServiceProvider = Provider<ShareService>(ShareService.new);
