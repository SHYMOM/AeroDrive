import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

class EncryptionEngine {
  final _argon2 = Argon2id(
    memory: kIsWeb ? 32768 : 65536, // 32MB web, 64MB native
    iterations: 3,
    parallelism: kIsWeb ? 1 : 2,
    hashLength: 32, // 256 bits for Master Key
  );

  final _argon2LowEnd = Argon2id(
    memory: 32768, // 32MB
    iterations: 4,
    parallelism: 2,
    hashLength: 32,
  );

  final Cipher _cipher = AesGcm.with256bits();

  /// Derives the 256-bit Master Key using Argon2id.
  /// Falls back to low-end parameters if OutOfMemory occurs.
  Future<List<int>> deriveMasterKey(String password, String saltString) async {
    final salt = saltString.codeUnits;

    try {
      final secretKey = await _argon2.deriveKeyFromPassword(
        password: password,
        nonce: salt,
      );
      return secretKey.extractBytes();
    } catch (e) {
      // Fallback for lower-end devices that might crash with 64MB memory limit
      final secretKey = await _argon2LowEnd.deriveKeyFromPassword(
        password: password,
        nonce: salt,
      );
      return secretKey.extractBytes();
    }
  }

  /// Generates a new 24-word BIP39 recovery phrase.
  String generateRecoveryPhrase() => bip39.generateMnemonic(strength: 256);

  /// Verifies if a given string is a valid BIP39 phrase.
  bool isValidRecoveryPhrase(String phrase) => bip39.validateMnemonic(phrase);

  /// Derives deterministic salt bytes from the BIP39 mnemonic seed.
  /// The same phrase always produces the same salt, enabling deterministic
  /// cross-device recovery without storing the salt separately.
  List<int> saltFromPhrase(String phrase) {
    final seed = bip39.mnemonicToSeed(phrase);
    return seed.take(32).toList();
  }

  /// Derives the Master Key deterministically from a BIP39 recovery phrase.
  /// Uses the phrase's BIP39 seed as the Argon2id salt so the same phrase
  /// always produces the same key — essential for cross-device sync.
  Future<List<int>> deriveMasterKeyFromPhrase(String phrase) async {
    final salt = saltFromPhrase(phrase);
    final saltStr = base64Encode(salt);
    return deriveMasterKey(phrase, saltStr);
  }

  /// Generates a secure random 256-bit Data Encryption Key (DEK).
  Future<List<int>> generateDek() async {
    final key = await _cipher.newSecretKey();
    return key.extractBytes();
  }

  /// Big-endian counter increment helper for AES-CTR nonce block offset calculations.
  static Uint8List incrementNonce(List<int> initialNonce, int increment) {
    final nonce = Uint8List.fromList(initialNonce);
    var carry = increment;
    for (var i = 15; i >= 0; i--) {
      if (carry == 0) break;
      final val = nonce[i] + carry;
      nonce[i] = val & 0xFF;
      carry = val >> 8;
    }
    return nonce;
  }

  /// Encrypts a source file into a temporary encrypted file using Stream-to-Disk architecture.
  /// Encrypts a specific byte range [startOffset, startOffset + chunkLength) of [sourceFile]
  /// directly to [outputFilePath] on disk using a 4MB memory buffer.
  Future<String> encryptSingleChunkToDisk({
    required File sourceFile,
    required String outputFilePath,
    required int startOffset,
    required int chunkLength,
    required List<int> dekBytes,
    List<int>? ctrIv,
  }) async {
    const int bufferSize = 4 * 1024 * 1024;

    final openFile = await sourceFile.open();
    final outputFile = File(outputFilePath);
    final sink = outputFile.openWrite();
    try {
      await openFile.setPosition(startOffset);
      var bytesProcessed = 0;
      final buffer = Uint8List(bufferSize);

      if (ctrIv != null) {
        final ctrAlgorithm = AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty);
        final secretKey = await ctrAlgorithm.newSecretKeyFromBytes(dekBytes);

        while (bytesProcessed < chunkLength) {
          final toRead = (chunkLength - bytesProcessed < bufferSize)
              ? chunkLength - bytesProcessed
              : bufferSize;
          final bytesRead = await openFile.readInto(buffer, 0, toRead);
          if (bytesRead == 0) break;

          final int startBlock = (startOffset + bytesProcessed) ~/ 16;
          final incrementedNonce = incrementNonce(ctrIv, startBlock);

          final block = Uint8List.fromList(buffer.sublist(0, bytesRead));
          final secretBox = await ctrAlgorithm.encrypt(
            block,
            secretKey: secretKey,
            nonce: incrementedNonce,
          );

          sink.add(secretBox.cipherText);
          bytesProcessed += bytesRead;
          await Future.delayed(Duration.zero);
        }
      } else {
        final secretKey = await _cipher.newSecretKeyFromBytes(dekBytes);

        while (bytesProcessed < chunkLength) {
          final toRead = (chunkLength - bytesProcessed < bufferSize)
              ? chunkLength - bytesProcessed
              : bufferSize;
          final bytesRead = await openFile.readInto(buffer, 0, toRead);
          if (bytesRead == 0) break;

          final nonce = _cipher.newNonce();
          final block = Uint8List.fromList(buffer.sublist(0, bytesRead));
          final secretBox = await _cipher.encrypt(
            block,
            secretKey: secretKey,
            nonce: nonce,
          );

          sink.add(secretBox.nonce);
          sink.add(secretBox.mac.bytes);
          sink.add(secretBox.cipherText);

          bytesProcessed += bytesRead;
          await Future.delayed(Duration.zero);
        }
      }
    } finally {
      await openFile.close();
      await sink.flush();
      await sink.close();
    }
    return outputFilePath;
  }

  /// Enforces a strict 4MB RAM buffer per the design requirements.
  /// Max logical chunk limit is 1.5GB. If the file exceeds this, it splits into multiple `.enc` files.
  /// If [ctrIv] is provided, uses AES-256-CTR mode (for seekable video streaming).
  /// Otherwise, uses AES-256-GCM mode.
  Future<List<String>> encryptStreamToDisk({
    required File sourceFile,
    required String outputDirectory,
    required List<int> dekBytes,
    int? chunkLimit,
    List<int>? ctrIv,
  }) async {
    const int bufferSize = 4 * 1024 * 1024;
    final int limit = chunkLimit ?? (1.5 * 1024 * 1024 * 1024).toInt();

    final file = await sourceFile.open();
    final fileLength = await file.length();

    var totalBytesProcessed = 0;
    var currentChunkBytes = 0;
    var chunkIndex = 0;
    final List<String> chunkPaths = [];

    var currentTempFile = File('$outputDirectory${Platform.pathSeparator}temp_chunk_$chunkIndex.enc');
    IOSink currentSink = currentTempFile.openWrite();
    chunkPaths.add(currentTempFile.path);

    if (ctrIv != null) {
      final ctrAlgorithm = AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty);
      final secretKey = await ctrAlgorithm.newSecretKeyFromBytes(dekBytes);
      final buffer = Uint8List(bufferSize);

      while (totalBytesProcessed < fileLength) {
        final bytesToRead = (fileLength - totalBytesProcessed < bufferSize)
            ? fileLength - totalBytesProcessed
            : bufferSize;
        final bytesRead = await file.readInto(buffer, 0, bytesToRead);
        if (bytesRead == 0) break;

        final int startBlock = totalBytesProcessed ~/ 16;
        final incrementedNonce = incrementNonce(ctrIv, startBlock);

        // CRITICAL: Copy, not a view — buffer.buffer is shared backing store
        // that would be overwritten on the next iteration before the async
        // encrypt completes. This was causing file corruption.
        final block = Uint8List.fromList(buffer.sublist(0, bytesRead));
        final secretBox = await ctrAlgorithm.encrypt(
          block,
          secretKey: secretKey,
          nonce: incrementedNonce,
        );

        currentSink.add(secretBox.cipherText);

        totalBytesProcessed += bytesRead;
        currentChunkBytes += bytesRead;

        if (currentChunkBytes >= limit && totalBytesProcessed < fileLength) {
          await currentSink.flush();
          await currentSink.close();

          chunkIndex++;
          currentChunkBytes = 0;

          currentTempFile = File('$outputDirectory${Platform.pathSeparator}temp_chunk_$chunkIndex.enc');
          currentSink = currentTempFile.openWrite();
          chunkPaths.add(currentTempFile.path);
        }
        await Future.delayed(Duration.zero);
      }
    } else {
      final secretKey = await _cipher.newSecretKeyFromBytes(dekBytes);
      final buffer = Uint8List(bufferSize);

      while (totalBytesProcessed < fileLength) {
        final bytesToRead = (fileLength - totalBytesProcessed < bufferSize)
            ? fileLength - totalBytesProcessed
            : bufferSize;
        final bytesRead = await file.readInto(buffer, 0, bytesToRead);
        if (bytesRead == 0) break;

        final nonce = _cipher.newNonce();
        // CRITICAL: Copy, not a view — same corruption bug as above.
        final block = Uint8List.fromList(buffer.sublist(0, bytesRead));
        final secretBox = await _cipher.encrypt(
          block,
          secretKey: secretKey,
          nonce: nonce,
        );

        currentSink.add(secretBox.nonce);
        currentSink.add(secretBox.mac.bytes);
        currentSink.add(secretBox.cipherText);

        totalBytesProcessed += bytesRead;
        currentChunkBytes += bytesRead;

        if (currentChunkBytes >= limit && totalBytesProcessed < fileLength) {
          await currentSink.flush();
          await currentSink.close();

          chunkIndex++;
          currentChunkBytes = 0;

          currentTempFile = File('$outputDirectory${Platform.pathSeparator}temp_chunk_$chunkIndex.enc');
          currentSink = currentTempFile.openWrite();
          chunkPaths.add(currentTempFile.path);
        }
        await Future.delayed(Duration.zero);
      }
    }

    await file.close();
    await currentSink.flush();
    await currentSink.close();

    return chunkPaths;
  }
  
  /// Decrypts an encrypted Stream-to-Disk chunk file back into a standard file.
  /// Supports both AES-CTR mode (if [ctrIv] is provided) and AES-GCM mode.
  Future<void> decryptDiskToStream({
    required File encryptedChunkFile,
    required File outputFile,
    required List<int> dekBytes,
    bool append = false,
    List<int>? ctrIv,
    int globalByteOffset = 0,
  }) async {
    final file = await encryptedChunkFile.open();
    final fileLength = await file.length();
    
    final outputSink = outputFile.openWrite(mode: append ? FileMode.writeOnlyAppend : FileMode.write);

    if (ctrIv != null) {
      final ctrAlgorithm = AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty);
      final secretKey = await ctrAlgorithm.newSecretKeyFromBytes(dekBytes);
      const int bufferSize = 4 * 1024 * 1024;
      var localOffset = 0;

      while (localOffset < fileLength) {
        final bytesToRead = (fileLength - localOffset < bufferSize) ? fileLength - localOffset : bufferSize;
        final block = await file.read(bytesToRead);

        final int globalBlock = (globalByteOffset + localOffset) ~/ 16;
        final incrementedNonce = incrementNonce(ctrIv, globalBlock);

        final decryptedData = await ctrAlgorithm.decrypt(
          SecretBox(block, nonce: incrementedNonce, mac: Mac.empty),
          secretKey: secretKey,
        );

        outputSink.add(decryptedData);
        localOffset += bytesToRead;
      }
    } else {
      final secretKey = await _cipher.newSecretKeyFromBytes(dekBytes);
      const int encryptedBlockSize = (4 * 1024 * 1024) + 12 + 16;
      var offset = 0;

      while (offset < fileLength) {
        final bytesToRead = (fileLength - offset < encryptedBlockSize) ? fileLength - offset : encryptedBlockSize;
        final block = await file.read(bytesToRead);

        final nonce = block.sublist(0, 12);
        final macBytes = block.sublist(12, 28);
        final cipherText = block.sublist(28);

        final decryptedData = await _cipher.decrypt(
          SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
          secretKey: secretKey,
        );

        outputSink.add(decryptedData);
        offset += bytesToRead;
      }
    }

    await file.close();
    await outputSink.flush();
    await outputSink.close();
  }

  /// Decrypts a complete encrypted byte array (single chunk or merged chunks).
  /// Handles both AES-GCM (with prepended nonce+mac) and AES-CTR formats.
  /// For GCM, iterates over each 4MB encrypted block (nonce+mac+ciphertext).
  Future<List<int>> decryptBytes({
    required List<int> data,
    required List<int> dekBytes,
    List<int>? ctrIv,
    int globalByteOffset = 0,
  }) async {
    if (ctrIv != null) {
      final ctrAlgorithm = AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty);
      final secretKey = await ctrAlgorithm.newSecretKeyFromBytes(dekBytes);
      final int startBlock = globalByteOffset ~/ 16;
      final incrementedNonce = incrementNonce(ctrIv, startBlock);
      final decrypted = await ctrAlgorithm.decrypt(
        SecretBox(Uint8List.fromList(data), nonce: incrementedNonce, mac: Mac.empty),
        secretKey: secretKey,
      );
      return decrypted;
    } else {
      final gcmCipher = AesGcm.with256bits();
      final secretKey = await gcmCipher.newSecretKeyFromBytes(dekBytes);
      const encryptedBlockSize = (4 * 1024 * 1024) + 12 + 16;
      final builder = BytesBuilder();
      var offset = 0;

      while (offset < data.length) {
        final blockEnd = (offset + encryptedBlockSize < data.length) ? offset + encryptedBlockSize : data.length;
        final block = data.sublist(offset, blockEnd);
        final nonce = block.sublist(0, 12);
        final macBytes = block.sublist(12, 28);
        final cipherText = block.sublist(28);

        final decrypted = await gcmCipher.decrypt(
          SecretBox(Uint8List.fromList(cipherText), nonce: nonce, mac: Mac(macBytes)),
          secretKey: secretKey,
        );
        builder.add(decrypted);
        offset = blockEnd;
      }

      return builder.toBytes();
    }
  }

  /// Unwraps a DEK (Data Encryption Key) from the sha256Hash field format.
  /// The wrapped key format is: base64(nonce)|base64(mac)|base64(cipherText)[|base64(ctrIv)]
  /// Returns [dekBytes, ctrIv] where ctrIv may be null.
  Future<List<List<int>?>> unwrapDek(String sha256Hash, List<int> masterKeyBytes) async {
    final parts = sha256Hash.contains('|')
        ? sha256Hash.split('|')
        : sha256Hash.split(':');
    if (parts.length < 3) throw Exception('Invalid wrapped DEK format');

    final nonce = base64Decode(parts[0]);
    final mac = Mac(base64Decode(parts[1]));
    final cipherText = base64Decode(parts[2]);

    final cipher = AesGcm.with256bits();
    final secretKey = await cipher.newSecretKeyFromBytes(masterKeyBytes);
    final dekBytes = await cipher.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: secretKey,
    );

    List<int>? ctrIv;
    if (parts.length >= 4) {
      ctrIv = base64Decode(parts[3]);
    }

    return [dekBytes, ctrIv];
  }
}
