import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;
import 'package:cryptography/cryptography.dart';

import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/core/providers/security_providers.dart';
import 'package:aerodrive/core/providers.dart';

class ShareService {
  final Ref _ref;

  ShareService(this._ref);

  Future<String> generateShareLink(FileData file) async {
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
    final nameEncoded = Uri.encodeComponent(file.name);
    
    // aerodrive://share?channelId=123&msgId=456&name=foo.mp4&size=1024&dek=BASE64
    final uri = Uri(
      scheme: 'aerodrive',
      host: 'share',
      queryParameters: {
        'channelId': channelId.toString(),
        'msgId': file.manifestMessageId.toString(),
        'name': file.name,
        'size': file.size?.toString() ?? '0',
        'mimeType': file.mimeType ?? 'application/octet-stream',
        'dek': dekBase64,
      },
    );

    // Save to Shares table for local tracking
    // Save to Shares table for local tracking
    await db.into(db.shares).insert(
      SharesCompanion.insert(
        id: const Uuid().v4(),
        fileId: drift.Value(file.id),
        createdAt: drift.Value(DateTime.now()),
        isActive: const drift.Value(true),
      )
    );

    return uri.toString();
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
    
    // We create a new file entry in our database pointing to the shared remote message!
    final newFileId = const Uuid().v4();
    
    await db.into(db.files).insert(
      FilesCompanion.insert(
        id: newFileId,
        name: name,
        size: drift.Value(size),
        mimeType: drift.Value(mimeType),
        sha256Hash: drift.Value(newHash), // Store our wrapped DEK
        manifestMessageId: drift.Value(msgId),
        isEncrypted: const drift.Value(true),
        createdAt: drift.Value(DateTime.now()),
        updatedAt: drift.Value(DateTime.now()),
        // Place it in the root or a special "Shared" folder. We'll leave folderId null for root.
      )
    );

    // Create the chunk mapping so download queue can find it
    await db.into(db.chunks).insert(
      ChunksCompanion.insert(
        id: const Uuid().v4(),
        fileId: drift.Value(newFileId),
        chunkIndex: const drift.Value(0),
        channelId: drift.Value(channelId),
        messageId: drift.Value(msgId),
        size: drift.Value(size),
      )
    );
  }
}

final shareServiceProvider = Provider<ShareService>((ref) {
  return ShareService(ref);
});
