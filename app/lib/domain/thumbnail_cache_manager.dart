import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'package:aerodrive/core/logger.dart';

class ThumbnailCacheManager {
  static final _cipher = AesGcm.with256bits();

  /// Gets the directory for cached encrypted thumbnails.
  static Future<Directory> _getCacheThumbsDirectory() async {
    Directory baseDir;
    if (Platform.isAndroid) {
      baseDir = await getApplicationDocumentsDirectory();
    } else if (Platform.isIOS) {
      baseDir = await getLibraryDirectory();
    } else {
      baseDir = await getApplicationSupportDirectory();
    }
    final thumbsDir = Directory(p.join(baseDir.path, 'cache', 'thumbs'));
    if (!await thumbsDir.exists()) {
      await thumbsDir.create(recursive: true);
    }
    return thumbsDir;
  }

  /// Encrypts the thumbnail plaintext bytes using the Master Key
  /// and saves it persistently to /cache/thumbs/[fileId].enc.
  static Future<String> saveThumbnail({
    required String fileId,
    required Uint8List plaintextBytes,
    required SecretKey masterKey,
  }) async {
    final dir = await _getCacheThumbsDirectory();
    final file = File(p.join(dir.path, '$fileId.enc'));

    final nonce = _cipher.newNonce();
    final secretBox = await _cipher.encrypt(
      plaintextBytes,
      secretKey: masterKey,
      nonce: nonce,
    );

    final builder = BytesBuilder();
    builder.add(secretBox.nonce);
    builder.add(secretBox.cipherText);
    builder.add(secretBox.mac.bytes);

    await file.writeAsBytes(builder.toBytes());
    return file.path;
  }

  /// Reads and decrypts the encrypted thumbnail from disk.
  static Future<Uint8List?> readThumbnail({
    required String fileId,
    required SecretKey masterKey,
  }) async {
    try {
      final dir = await _getCacheThumbsDirectory();
      final file = File(p.join(dir.path, '$fileId.enc'));

      if (!await file.exists()) {
        return null;
      }

      final encryptedBytes = await file.readAsBytes();
      if (encryptedBytes.length < 28) return null;

      final nonce = encryptedBytes.sublist(0, 12);
      final cipherTextAndMac = encryptedBytes.sublist(12);

      final macBytes = cipherTextAndMac.sublist(cipherTextAndMac.length - 16);
      final cipherText = cipherTextAndMac.sublist(0, cipherTextAndMac.length - 16);

      final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));
      final decrypted = await _cipher.decrypt(secretBox, secretKey: masterKey);
      
      return Uint8List.fromList(decrypted);
    } catch (e) {
      AppLogger.error('ThumbnailCache: failed to read thumbnail', e);
      return null;
    }
  }

  /// Clears all encrypted thumbnails from the cache folder.
  static Future<void> clearCache() async {
    try {
      final dir = await _getCacheThumbsDirectory();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      AppLogger.error('ThumbnailCache: failed to clear cache', e);
    }
  }
}
