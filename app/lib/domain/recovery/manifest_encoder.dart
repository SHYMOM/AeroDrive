import 'package:cryptography/cryptography.dart';
import 'caption_codec.dart';

class ManifestEncoder {
  /// Encodes and encrypts a File Manifest for Telegram captions.
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
    int isChunked = 0,
    int version = 1,
  }) async => CaptionSerializer.serializeFile(
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
      isChunked: isChunked,
      version: version,
    );

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
  }) async => CaptionSerializer.serializeFolder(
      folderId: folderId,
      name: folderName,
      parentFolderId: parentFolderId,
      masterKey: masterKey,
      color: color,
    );

  /// Decodes a Base64 caption back to a JSON map.
  static Future<Map<String, dynamic>?> decodeManifest(String base64Caption, SecretKey masterKey) async => CaptionDecryptor.deserialize(base64Caption, masterKey);
}

