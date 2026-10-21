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
    DateTime? photoTakenAt,
    double? latitude,
    double? longitude,
    String? locality,
    String? country,
    List<String>? tags,
    List<Map<String, dynamic>>? faces,
    int version = 1,
    int isEncrypted = 1,
    int isChunked = 0,
    DateTime? createdAt,
  }) async {
    final safeName = name.length > 200 ? name.substring(0, 200) : name;
    final ts = (createdAt ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    
    final safeLat = (latitude != null && latitude.isFinite) ? latitude : null;
    final safeLng = (longitude != null && longitude.isFinite) ? longitude : null;
    final safeDuration = (duration != null && duration > 0) ? duration : null;

    List<Map<String, dynamic>>? safeFaces;
    if (faces != null && faces.isNotEmpty) {
      safeFaces = [];
      for (final f in faces) {
        final safeF = <String, dynamic>{};
        f.forEach((key, val) {
          if (val is num) {
            if (val is double && !val.isFinite) return;
            safeF[key] = val;
          } else if (val != null) {
            safeF[key] = val;
          }
        });
        if (safeF.isNotEmpty) safeFaces.add(safeF);
      }
      if (safeFaces.isEmpty) safeFaces = null;
    }

    final Map<String, dynamic> jsonMap = {
      "t": "file",
      "id": fileId,
      "name": safeName,
      if (parentFolderId != null && parentFolderId.isNotEmpty) "pid": parentFolderId,
      "hash": hash,
      "size": size,
      "mime": mime,
      "ts": ts,
      "ver": version,
      "enc": isEncrypted,
      "chk": isChunked,
      if (chunkIndex != null) "c": chunkIndex,
      if (totalChunks != null) "tc": totalChunks,
      if (wrappedDekBase64 != null) "k": wrappedDekBase64,
      if (ctrIvBase64 != null) "iv": ctrIvBase64,
      if (safeDuration != null) "dur": safeDuration,
      if (photoTakenAt != null) "pt": photoTakenAt.millisecondsSinceEpoch ~/ 1000,
      if (safeLat != null) "lat": safeLat,
      if (safeLng != null) "lng": safeLng,
      if (locality != null && locality.isNotEmpty) "loc": locality,
      if (country != null && country.isNotEmpty) "cnt": country,
      if (tags != null && tags.isNotEmpty) "tags": tags,
      if (safeFaces != null && safeFaces.isNotEmpty) "faces": safeFaces,
    };

    final sanitized = _sanitizeForJson(jsonMap) as Map<String, dynamic>;
    final jsonStr = jsonEncode(sanitized);
    return _encryptAndEncode(jsonStr, masterKey);
  }

  /// Recursively strips out non-finite double values (NaN, Infinity, -Infinity)
  /// and null map entries to ensure jsonEncode never fails.
  static dynamic _sanitizeForJson(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      if (value is double && !value.isFinite) return null;
      return value;
    }
    if (value is String || value is bool) return value;
    if (value is List) {
      return value
          .map(_sanitizeForJson)
          .where((v) => v != null)
          .toList();
    }
    if (value is Map) {
      final clean = <String, dynamic>{};
      value.forEach((k, v) {
        final cleanV = _sanitizeForJson(v);
        if (cleanV != null) {
          clean[k.toString()] = cleanV;
        }
      });
      return clean;
    }
    return value;
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

    final sanitized = _sanitizeForJson(jsonMap) as Map<String, dynamic>;
    final jsonStr = jsonEncode(sanitized);
    return _encryptAndEncode(jsonStr, masterKey);
  }

  /// Serializes and encrypts a Folder Caption.
  static Future<String> serializeFolder({
    required String folderId,
    required String name,
    required String? parentFolderId,
    required SecretKey masterKey,
    String? color,
    DateTime? createdAt,
  }) async {
    final safeName = name.length > 200 ? name.substring(0, 200) : name;
    final ts = (createdAt ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;

    final Map<String, dynamic> jsonMap = {
      "t": "dir",
      "id": folderId,
      "name": safeName,
      if (parentFolderId != null && parentFolderId.isNotEmpty) "pid": parentFolderId,
      "ts": ts,
      "col": color,
    };

    final sanitized = _sanitizeForJson(jsonMap) as Map<String, dynamic>;
    final jsonStr = jsonEncode(sanitized);
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
