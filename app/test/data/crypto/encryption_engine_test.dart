import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:aerodrive/data/crypto/encryption_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late EncryptionEngine engine;
  late Directory tempDir;

  setUp(() async {
    engine = EncryptionEngine();
    // Use system temp directory for testing
    tempDir = await Directory.systemTemp.createTemp('aerodrive_crypto_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('Argon2id Master Key Derivation matches length', () async {
    final key = await engine.deriveMasterKey('SuperSecretPassword123!', 'salt123');
    expect(key.length, 32); // 256-bit
  });

  test('BIP39 Recovery Phrase Validation', () {
    final phrase = engine.generateRecoveryPhrase();
    expect(phrase.split(' ').length, 24); // 256 bits = 24 words
    expect(engine.isValidRecoveryPhrase(phrase), true);
    expect(engine.isValidRecoveryPhrase('invalid phrase here'), false);
  });

  test('Stream-to-Disk Encryption exactly reconstructs a 10MB file', () async {
    final sourceFile = File(p.join(tempDir.path, 'source.bin'));
    final outputFile = File(p.join(tempDir.path, 'decrypted.bin'));
    
    // Generate 10MB of random data
    final random = Random.secure();
    final data = Uint8List(10 * 1024 * 1024);
    for (var i = 0; i < data.length; i++) {
      data[i] = random.nextInt(256);
    }
    await sourceFile.writeAsBytes(data);

    // Generate DEK
    final dek = await engine.generateDek();

    // 1. Encrypt
    final chunkPaths = await engine.encryptStreamToDisk(
      sourceFile: sourceFile,
      outputDirectory: tempDir.path,
      dekBytes: dek,
    );

    // Should only be 1 logical chunk since 10MB < 1.5GB
    expect(chunkPaths.length, 1);
    final encryptedChunkFile = File(chunkPaths.first);

    // The ciphertext size should be 10MB + (3 blocks * 28 bytes metadata)
    // 10MB = 2.5 blocks of 4MB. That's 3 blocks total.
    // 3 * (12 nonce + 16 MAC) = 84 bytes.
    // Total size = 10485760 + 84 = 10485844.
    expect(encryptedChunkFile.lengthSync(), 10485844);

    // 2. Decrypt
    await engine.decryptDiskToStream(
      encryptedChunkFile: encryptedChunkFile,
      outputFile: outputFile,
      dekBytes: dek,
    );

    // 3. Verify
    final decryptedData = await outputFile.readAsBytes();
    
    // Check lengths
    expect(decryptedData.length, data.length);
    
    // Check byte-for-byte equality
    var isIdentical = true;
    for (var i = 0; i < data.length; i++) {
      if (data[i] != decryptedData[i]) {
        isIdentical = false;
        break;
      }
    }
    expect(isIdentical, true);
  });

  test('Multi-chunk encryptSingleChunkToDisk reassembles byte-for-byte in AES-GCM mode', () async {
    final sourceFile = File(p.join(tempDir.path, 'source_chunks.bin'));
    final outputFile = File(p.join(tempDir.path, 'decrypted_chunks.bin'));

    // Generate 15MB random data (3 chunks of 5MB each)
    final random = Random.secure();
    final data = Uint8List(15 * 1024 * 1024);
    for (var i = 0; i < data.length; i++) {
      data[i] = random.nextInt(256);
    }
    await sourceFile.writeAsBytes(data);

    final dek = await engine.generateDek();
    const chunkSize = 5 * 1024 * 1024;
    final totalChunks = (data.length / chunkSize).ceil();
    final chunkFiles = <File>[];

    // Encrypt chunk-by-chunk on demand
    for (var i = 0; i < totalChunks; i++) {
      final startOffset = i * chunkSize;
      final length = min(chunkSize, data.length - startOffset);
      final chunkPath = p.join(tempDir.path, 'chunk_$i.enc');
      await engine.encryptSingleChunkToDisk(
        sourceFile: sourceFile,
        outputFilePath: chunkPath,
        startOffset: startOffset,
        chunkLength: length,
        dekBytes: dek,
      );
      chunkFiles.add(File(chunkPath));
    }

    // Decrypt sequentially appending
    for (var i = 0; i < chunkFiles.length; i++) {
      await engine.decryptDiskToStream(
        encryptedChunkFile: chunkFiles[i],
        outputFile: outputFile,
        dekBytes: dek,
        append: i > 0,
      );
    }

    final decryptedData = await outputFile.readAsBytes();
    expect(decryptedData.length, data.length);
    expect(decryptedData, equals(data));
  });

  test('Multi-chunk encryptSingleChunkToDisk reassembles byte-for-byte in AES-CTR mode (video)', () async {
    final sourceFile = File(p.join(tempDir.path, 'source_ctr.bin'));
    final outputFile = File(p.join(tempDir.path, 'decrypted_ctr.bin'));

    final random = Random.secure();
    final data = Uint8List(12 * 1024 * 1024);
    for (var i = 0; i < data.length; i++) {
      data[i] = random.nextInt(256);
    }
    await sourceFile.writeAsBytes(data);

    final dek = await engine.generateDek();
    final ctrIv = List<int>.generate(16, (_) => random.nextInt(256));
    const chunkSize = 4 * 1024 * 1024;
    final totalChunks = (data.length / chunkSize).ceil();
    final chunkFiles = <File>[];

    for (var i = 0; i < totalChunks; i++) {
      final startOffset = i * chunkSize;
      final length = min(chunkSize, data.length - startOffset);
      final chunkPath = p.join(tempDir.path, 'chunk_ctr_$i.enc');
      await engine.encryptSingleChunkToDisk(
        sourceFile: sourceFile,
        outputFilePath: chunkPath,
        startOffset: startOffset,
        chunkLength: length,
        dekBytes: dek,
        ctrIv: ctrIv,
      );
      chunkFiles.add(File(chunkPath));
    }

    var globalByteOffset = 0;
    for (var i = 0; i < chunkFiles.length; i++) {
      await engine.decryptDiskToStream(
        encryptedChunkFile: chunkFiles[i],
        outputFile: outputFile,
        dekBytes: dek,
        append: i > 0,
        ctrIv: ctrIv,
        globalByteOffset: globalByteOffset,
      );
      globalByteOffset += await chunkFiles[i].length();
    }

    final decryptedData = await outputFile.readAsBytes();
    expect(decryptedData.length, data.length);
    expect(decryptedData, equals(data));
  });
}

