import 'dart:io';

import 'package:aerodrive/domain/recovery/caption_codec.dart';
import 'package:aerodrive/domain/thumbnail_cache_manager.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (methodCall) async {
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
    const fileId = 'test-file-uuid';
    const name = 'AeroDriveTestDocument.pdf';
    const parentId = 'test-folder-uuid';
    const hash = 'sha256-file-hash-value';
    const size = 123456;
    const mime = 'application/pdf';
    const wrappedDek = 'wrapped-dek-key-base64-string';
    const ctrIv = 'ctr-iv-base64-string';

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
    expect(decryptedFileMap['ts'], isNotNull);

    // Verify custom createdAt is accurately preserved in timestamp 'ts'
    final customDate = DateTime(2025, 5, 15, 14, 30);
    final encryptedFileCaptionWithDate = await CaptionSerializer.serializeFile(
      fileId: fileId,
      name: name,
      parentFolderId: parentId,
      hash: hash,
      size: size,
      mime: mime,
      masterKey: masterKey,
      wrappedDekBase64: wrappedDek,
      ctrIvBase64: ctrIv,
      createdAt: customDate,
    );
    final decryptedWithDate = await CaptionDecryptor.deserialize(encryptedFileCaptionWithDate, masterKey);
    expect(decryptedWithDate!['ts'], customDate.millisecondsSinceEpoch ~/ 1000);

    // 2. Test Folder Caption serialization/decryption
    const folderId = 'test-folder-uuid';
    const folderName = 'AeroDriveWorkFolder';
    const color = '#FF0000';

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

    const fileId = 'test-thumbnail-file-id';
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
