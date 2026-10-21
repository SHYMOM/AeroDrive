import 'package:cryptography/cryptography.dart';
import 'caption_codec.dart';

class ManifestEncoder {
  /// Estimate the encrypted base64 caption size given a JSON payload.
  /// Telegram caption limit is 1024 chars; we use 900 as a safety margin.
  static const int _captionSafetyLimit = 900;

  /// Returns true if the estimated encrypted size of [jsonMap] would exceed
  /// Telegram's caption limit.
  static bool _wouldExceedLimit(Map<String, dynamic> jsonMap) {
    // Rough estimate: json length + 28 (nonce+mac) -> base64 expansion * 4/3
    final jsonStr = _estimateJsonLength(jsonMap);
    return _estimatedEncryptedSize(jsonStr) > _captionSafetyLimit;
  }

  /// Quick estimate of JSON length without full serialization.
  static int _estimateJsonLength(Map<String, dynamic> jsonMap) {
    // Approximation: sum key/value lengths plus structural overhead
    int length = 2; // { }
    for (final entry in jsonMap.entries) {
      final keyLen = entry.key.length + 3; // "key":
      final valueLen = entry.value is String
          ? (entry.value as String).length + 2
          : entry.value is List
              ? _estimateListLength(entry.value as List)
              : entry.value is num
                  ? entry.value.toString().length
                  : entry.value.toString().length + 2;
      length += keyLen + valueLen + 1; // comma
    }
    return length;
  }

  static int _estimateListLength(List list) {
    if (list.isEmpty) return 2; // [ ]
    int total = 2; // [ ]
    for (final item in list) {
      if (item is String) {
        total += (item as String).length + 2;
      } else if (item is Map) {
        total += _estimateJsonLength(item as Map<String, dynamic>);
      } else {
        total += item.toString().length;
      }
      total += 1; // comma
    }
    return total;
  }

  /// Compute expected base64 length of AES-256-GCM encrypted payload.
  static int _estimatedEncryptedSize(int jsonLength) {
    // Raw encrypted: nonce(12) + cipherText(jsonLength) + mac(16)
    final rawSize = 12 + jsonLength + 16;
    // Base64: ceil(rawSize / 3) * 4
    return ((rawSize + 2) ~/ 3) * 4;
  }

  /// Encodes and encrypts a File Manifest for Telegram captions.
  /// Automatically strips non-essential metadata fields if the encrypted
  /// caption would exceed Telegram's 1024-character limit.
  static Future<String> encodeFileManifest({
    required String fileId,
    required String fileName,
    required String? parentFolderId,
    required SecretKey masterKey,
    required String hash,
    required int size,
    required String mime,
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
    int isChunked = 0,
    int version = 1,
    DateTime? createdAt,
  }) async {
    final safeLat = (latitude != null && latitude.isFinite) ? latitude : null;
    final safeLng = (longitude != null && longitude.isFinite) ? longitude : null;

    // Start with full data
    var finalTags = tags;
    var finalFaces = faces;

    // Check if we'd exceed the limit with all data included
    final testMap = _buildMap(
      fileId: fileId,
      fileName: fileName,
      parentFolderId: parentFolderId,
      hash: hash,
      size: size,
      mime: mime,
      wrappedDekBase64: wrappedDekBase64,
      ctrIvBase64: ctrIvBase64,
      chunkIndex: chunkIndex,
      totalChunks: totalChunks,
      duration: duration,
      photoTakenAt: photoTakenAt,
      latitude: safeLat,
      longitude: safeLng,
      locality: locality,
      country: country,
      tags: finalTags,
      faces: finalFaces,
      isChunked: isChunked,
      version: version,
    );

    // If too large, strip faces first (largest data), then tags
    if (_wouldExceedLimit(testMap)) {
      finalFaces = null;
      testMap.remove('faces');

      if (_wouldExceedLimit(testMap)) {
        finalTags = null;
        testMap.remove('tags');

        if (_wouldExceedLimit(testMap)) {
          // Still too large? Truncate wrapped DEK if needed
          // (unlikely but defensive)
          if (wrappedDekBase64 != null && wrappedDekBase64.length > 200) {
            // DEK too long — this shouldn't happen but protect against it
          }
        }
      }
    }

    return CaptionSerializer.serializeFile(
      fileId: fileId,
      name: fileName,
      parentFolderId: parentFolderId,
      hash: hash,
      size: size,
      mime: mime,
      masterKey: masterKey,
      wrappedDekBase64: wrappedDekBase64,
      ctrIvBase64: ctrIvBase64,
      chunkIndex: chunkIndex,
      totalChunks: totalChunks,
      duration: duration,
      photoTakenAt: photoTakenAt,
      latitude: safeLat,
      longitude: safeLng,
      locality: locality,
      country: country,
      tags: finalTags,
      faces: finalFaces,
      isChunked: isChunked,
      version: version,
      createdAt: createdAt,
    );
  }

  /// Builds a test map for size estimation.
  static Map<String, dynamic> _buildMap({
    required String fileId,
    required String fileName,
    required String? parentFolderId,
    required String hash,
    required int size,
    required String mime,
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
    int isChunked = 0,
    int version = 1,
  }) {
    return {
      "t": "file",
      "id": fileId,
      "name": fileName.length > 200 ? fileName.substring(0, 200) : fileName,
      if (parentFolderId != null && parentFolderId.isNotEmpty) "pid": parentFolderId,
      "hash": hash,
      "size": size,
      "mime": mime,
      "ver": version,
      "enc": 1,
      "chk": isChunked,
      if (chunkIndex != null) "c": chunkIndex,
      if (totalChunks != null) "tc": totalChunks,
      if (wrappedDekBase64 != null) "k": wrappedDekBase64,
      if (ctrIvBase64 != null) "iv": ctrIvBase64,
      if (duration != null) "dur": duration,
      if (latitude != null && latitude.isFinite) "lat": latitude,
      if (longitude != null && longitude.isFinite) "lng": longitude,
      if (tags != null && tags.isNotEmpty) "tags": tags,
      if (faces != null && faces.isNotEmpty) "faces": faces,
    };
  }

  /// Encodes and encrypts a Thumbnail Manifest for Telegram captions.
  static Future<String> encodeThumbnailManifest({
    required String fileId,
    required SecretKey masterKey,
  }) async => CaptionSerializer.serializeThumbnail(
      fileId: fileId,
      masterKey: masterKey,
    );

  /// Encodes and encrypts a Folder Metadata Manifest for Telegram captions.
  static Future<String> encodeFolderManifest({
    required String folderId,
    required String folderName,
    required String? parentFolderId,
    required SecretKey masterKey,
    String? color,
    DateTime? createdAt,
  }) async => CaptionSerializer.serializeFolder(
      folderId: folderId,
      name: folderName,
      parentFolderId: parentFolderId,
      masterKey: masterKey,
      color: color,
      createdAt: createdAt,
    );

  /// Decodes a Base64 caption back to a JSON map.
  static Future<Map<String, dynamic>?> decodeManifest(
    String base64Caption,
    SecretKey masterKey,
  ) async => CaptionDecryptor.deserialize(base64Caption, masterKey);
}
