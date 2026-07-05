import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class CaptionSerializer {
  static final _cipher = AesGcm.with256bits();

  /// Encrypts and encodes a JSON manifest string using the Master Key.
  /// Format: [12-byte Nonce] + [Ciphertext] + [16-byte MAC]
  static Future<String> _encryptAndEncode(String jsonStr, SecretKey masterKey) async {
    final bytes = utf8.encode(jsonStr);
    final nonce = _cipher.newNonce();
    
    final secretBox = await _cipher.encrypt(
      bytes,
      secretKey: masterKey,
      nonce: nonce,
    );

    final builder = BytesBuilder();
    builder.add(secretBox.nonce);
    builder.add(secretBox.cipherText);
    builder.add(secretBox.mac.bytes);

    return base64Encode(builder.toBytes());
  }

  /// Serializes and encrypts a File Caption.
  static Future<String> serializeFile({
    required String fileId,
    required String name,
    required String? parentFolderId,
    required String hash,
    required int size,
    required String mime,
    required SecretKey masterKey,
    String? wrappedDekBase64,
    String? ctrIvBase64,
    int? chunkIndex,
    int? totalChunks,
    int? duration,
    int version = 1,
    int isEncrypted = 1,
    int isChunked = 0,
  }) async {
    final safeName = name.length > 200 ? name.substring(0, 200) : name;
    
    final Map<String, dynamic> jsonMap = {
      "t": "file",
      "id": fileId,
      "name": safeName,
      if (parentFolderId != null && parentFolderId.isNotEmpty) "pid": parentFolderId,
      "hash": hash,
      "size": size,
      "mime": mime,
      "ts": DateTime.now().millisecondsSinceEpoch ~/ 1000,
      "ver": version,
      "enc": isEncrypted,
      "chk": isChunked,
      if (chunkIndex != null) "c": chunkIndex,
      if (totalChunks != null) "tc": totalChunks,
      if (wrappedDekBase64 != null) "k": wrappedDekBase64,
      if (ctrIvBase64 != null) "iv": ctrIvBase64,
      if (duration != null) "dur": duration,
    };

    final jsonStr = jsonEncode(jsonMap);
    return _encryptAndEncode(jsonStr, masterKey);
  }

  /// Serializes and encrypts a Thumbnail Caption.
  static Future<String> serializeThumbnail({
    required String fileId,
    required SecretKey masterKey,
  }) async {
    final jsonMap = {
      "t": "thumb",
      "fid": fileId,
    };

    final jsonStr = jsonEncode(jsonMap);
    return _encryptAndEncode(jsonStr, masterKey);
  }

  /// Serializes and encrypts a Folder Caption.
  static Future<String> serializeFolder({
    required String folderId,
    required String name,
    required String? parentFolderId,
    required SecretKey masterKey,
    String? color,
  }) async {
    final safeName = name.length > 200 ? name.substring(0, 200) : name;

    final Map<String, dynamic> jsonMap = {
      "t": "dir",
      "id": folderId,
      "name": safeName,
      if (parentFolderId != null && parentFolderId.isNotEmpty) "pid": parentFolderId,
      "ts": DateTime.now().millisecondsSinceEpoch ~/ 1000,
      "col": color,
    };

    final jsonStr = jsonEncode(jsonMap);
    return _encryptAndEncode(jsonStr, masterKey);
  }
}

class CaptionDecryptor {
  static final _cipher = AesGcm.with256bits();

  /// Decrypts and decodes a Base64 caption back to a JSON map using the Master Key.
  static Future<Map<String, dynamic>?> deserialize(String base64Caption, SecretKey masterKey) async {
    try {
      final decodedBytes = base64Decode(base64Caption);
      if (decodedBytes.length < 28) return null; // 12 (nonce) + 16 (mac) = 28 minimum

      final nonce = decodedBytes.sublist(0, 12);
      final cipherTextAndMac = decodedBytes.sublist(12);

      // MAC is the last 16 bytes of the decrypted stream structure
      final macBytes = cipherTextAndMac.sublist(cipherTextAndMac.length - 16);
      final cipherText = cipherTextAndMac.sublist(0, cipherTextAndMac.length - 16);

      final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));
      
      final plainText = await _cipher.decrypt(
        secretBox,
        secretKey: masterKey,
      );

      final jsonStr = utf8.decode(plainText);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      // Not a valid manifest or wrong master key
      return null;
    }
  }
}
