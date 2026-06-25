import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:aerodrive/domain/recovery/caption_codec.dart';
import 'package:aerodrive/domain/thumbnail_cache_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return './test_cache'; // Use local directory for testing
      },
    );
  });

  tearDown(() async {
    final dir = Directory('./test_cache');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  test('CaptionSerializer and CaptionDecryptor codec tests', () async {
    final cipher = AesGcm.with256bits();
    final masterKey = await cipher.newSecretKey();

    // 1. Test File Caption serialization/decryption
    final fileId = 'test-file-uuid';
    final name = 'AeroDriveTestDocument.pdf';
    final parentId = 'test-folder-uuid';
    final hash = 'sha256-file-hash-value';
    final size = 123456;
    final mime = 'application/pdf';
    final wrappedDek = 'wrapped-dek-key-base64-string';
    final ctrIv = 'ctr-iv-base64-string';

    final encryptedFileCaption = await CaptionSerializer.serializeFile(
      fileId: fileId,
      name: name,
      parentFolderId: parentId,
      hash: hash,
      size: size,
      mime: mime,
      masterKey: masterKey,
      wrappedDekBase64: wrappedDek,
      ctrIvBase64: ctrIv,
      isChunked: 0,
      version: 1,
    );

    expect(encryptedFileCaption, isNotEmpty);
    expect(encryptedFileCaption.length, lessThan(1024));

    final decryptedFileMap = await CaptionDecryptor.deserialize(encryptedFileCaption, masterKey);
    expect(decryptedFileMap, isNotNull);
    expect(decryptedFileMap!['t'], 'file');
    expect(decryptedFileMap['id'], fileId);
    expect(decryptedFileMap['name'], name);
    expect(decryptedFileMap['pid'], parentId);
    expect(decryptedFileMap['hash'], hash);
    expect(decryptedFileMap['size'], size);
    expect(decryptedFileMap['mime'], mime);
    expect(decryptedFileMap['k'], wrappedDek);
    expect(decryptedFileMap['iv'], ctrIv);

    // 2. Test Folder Caption serialization/decryption
    final folderId = 'test-folder-uuid';
    final folderName = 'AeroDriveWorkFolder';
    final color = '#FF0000';

    final encryptedFolderCaption = await CaptionSerializer.serializeFolder(
      folderId: folderId,
      name: folderName,
      parentFolderId: parentId,
      masterKey: masterKey,
      color: color,
    );

    expect(encryptedFolderCaption, isNotEmpty);
    expect(encryptedFolderCaption.length, lessThan(1024));

    final decryptedFolderMap = await CaptionDecryptor.deserialize(encryptedFolderCaption, masterKey);
    expect(decryptedFolderMap, isNotNull);
    expect(decryptedFolderMap!['t'], 'dir');
    expect(decryptedFolderMap['id'], folderId);
    expect(decryptedFolderMap['name'], folderName);
    expect(decryptedFolderMap['pid'], parentId);
    expect(decryptedFolderMap['col'], color);
  });

  test('ThumbnailCacheManager encrypted caching tests', () async {
    final cipher = AesGcm.with256bits();
    final masterKey = await cipher.newSecretKey();

    final fileId = 'test-thumbnail-file-id';
    final thumbnailData = Uint8List.fromList(List.generate(100, (i) => i % 256));

    // Save encrypted thumbnail
    final savedPath = await ThumbnailCacheManager.saveThumbnail(
      fileId: fileId,
      plaintextBytes: thumbnailData,
      masterKey: masterKey,
    );

    expect(savedPath, isNotEmpty);
    expect(File(savedPath).existsSync(), true);

    // Read and decrypt thumbnail
    final decryptedBytes = await ThumbnailCacheManager.readThumbnail(
      fileId: fileId,
      masterKey: masterKey,
    );

    expect(decryptedBytes, isNotNull);
    expect(decryptedBytes, thumbnailData);

    // Clear cache
    await ThumbnailCacheManager.clearCache();
    final deletedFile = File(savedPath);
    expect(deletedFile.existsSync(), false);
  });
}
