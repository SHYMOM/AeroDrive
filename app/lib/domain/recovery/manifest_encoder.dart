import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class ManifestEncoder {
  static final _cipher = AesGcm.with256bits();

  /// Encodes and encrypts a File Manifest for Telegram captions.
  /// Resulting Base64 string is guaranteed to be under 1024 characters
  /// if the filename is under 200 characters.
  static Future<String> encodeFileManifest({
    required String fileId,
    required String fileName,
    required String? parentFolderId,
    required SecretKey masterKey,
    List<int>? dekBytes,
  }) async {
    // Truncate filename if it somehow bypasses UI validation
    final safeName = fileName.length > 200 ? fileName.substring(0, 200) : fileName;
    
    final jsonStr = jsonEncode({
      "i": fileId,
      "n": safeName,
      if (parentFolderId != null) "f": parentFolderId,
      if (dekBytes != null) "k": base64Encode(dekBytes),
    });

    return _encryptAndEncode(jsonStr, masterKey);
  }

  /// Encodes and encrypts a Folder Metadata Manifest for Telegram captions.
  static Future<String> encodeFolderManifest({
    required String folderId,
    required String folderName,
    required String? parentFolderId,
    required SecretKey masterKey,
  }) async {
    final safeName = folderName.length > 200 ? folderName.substring(0, 200) : folderName;

    final jsonStr = jsonEncode({
      "t": "dir",
      "i": folderId,
      "n": safeName,
      if (parentFolderId != null) "p": parentFolderId,
    });

    return _encryptAndEncode(jsonStr, masterKey);
  }

  /// Decodes a Base64 caption back to a JSON map.
  static Future<Map<String, dynamic>?> decodeManifest(String base64Caption, SecretKey masterKey) async {
    try {
      final decodedBytes = base64Decode(base64Caption);
      if (decodedBytes.length < 28) return null; // 12 (nonce) + 16 (mac) = 28 minimum

      final nonce = decodedBytes.sublist(0, 12);
      final cipherTextAndMac = decodedBytes.sublist(12);

      // In cryptography package, the MAC is the last 16 bytes of the cipherText
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
      // Not a valid manifest, or wrong key
      return null;
    }
  }

  static Future<String> _encryptAndEncode(String plainText, SecretKey masterKey) async {
    final bytes = utf8.encode(plainText);
    final nonce = _cipher.newNonce();
    
    final secretBox = await _cipher.encrypt(
      bytes,
      secretKey: masterKey,
      nonce: nonce,
    );

    // Format: [12-byte Nonce] + [Ciphertext] + [16-byte MAC]
    final builder = BytesBuilder();
    builder.add(secretBox.nonce);
    builder.add(secretBox.cipherText);
    builder.add(secretBox.mac.bytes);

    return base64Encode(builder.toBytes());
  }
}
