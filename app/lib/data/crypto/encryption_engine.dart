import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:bip39/bip39.dart' as bip39;
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
    final passwordBytes = password.codeUnits;
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
  String generateRecoveryPhrase() {
    return bip39.generateMnemonic(strength: 256); // 256 bits of entropy = 24 words
  }

  /// Verifies if a given string is a valid BIP39 phrase.
  bool isValidRecoveryPhrase(String phrase) {
    return bip39.validateMnemonic(phrase);
  }

  /// Generates a secure random 256-bit Data Encryption Key (DEK).
  Future<List<int>> generateDek() async {
    final key = await _cipher.newSecretKey();
    return key.extractBytes();
  }

  /// Big-endian counter increment helper for AES-CTR nonce block offset calculations.
  static Uint8List incrementNonce(List<int> initialNonce, int increment) {
    final nonce = Uint8List.fromList(initialNonce);
    int carry = increment;
    for (int i = 15; i >= 0; i--) {
      if (carry == 0) break;
      final val = nonce[i] + carry;
      nonce[i] = val & 0xFF;
      carry = val >> 8;
    }
    return nonce;
  }

  /// Encrypts a source file into a temporary encrypted file using Stream-to-Disk architecture.
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
    final int bufferSize = 4 * 1024 * 1024; // EXACT 4 MB RAM Buffer
    final int limit = chunkLimit ?? (1.5 * 1024 * 1024 * 1024).toInt(); // 1.5 GB logical limit

    final file = await sourceFile.open(mode: FileMode.read);
    final fileLength = await file.length();
    
    int currentBytesInLogicalChunk = 0;
    int chunkIndex = 0;
    List<String> chunkPaths = [];
    
    File currentTempFile = File('$outputDirectory/temp_chunk_$chunkIndex.enc');
    IOSink currentSink = currentTempFile.openWrite();
    chunkPaths.add(currentTempFile.path);

    if (ctrIv != null) {
      final ctrAlgorithm = AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty);
      final secretKey = await ctrAlgorithm.newSecretKeyFromBytes(dekBytes);

      int offset = 0;
      while (offset < fileLength) {
        final bytesToRead = (fileLength - offset < bufferSize) ? fileLength - offset : bufferSize;
        final block = await file.read(bytesToRead);

        final int startBlock = currentBytesInLogicalChunk ~/ 16;
        final incrementedNonce = incrementNonce(ctrIv, startBlock);

        final secretBox = await ctrAlgorithm.encrypt(
          block,
          secretKey: secretKey,
          nonce: incrementedNonce,
        );

        // Write ONLY ciphertext to disk (no prepended nonce or MAC)
        currentSink.add(secretBox.cipherText);

        offset += bytesToRead;
        currentBytesInLogicalChunk += block.length;

        // Split at limit
        if (currentBytesInLogicalChunk >= limit && offset < fileLength) {
          await currentSink.flush();
          await currentSink.close();

          chunkIndex++;
          currentBytesInLogicalChunk = 0;
          
          currentTempFile = File('$outputDirectory/temp_chunk_$chunkIndex.enc');
          currentSink = currentTempFile.openWrite();
          chunkPaths.add(currentTempFile.path);
        }
      }
    } else {
      final secretKey = await _cipher.newSecretKeyFromBytes(dekBytes);

      int offset = 0;
      while (offset < fileLength) {
        final bytesToRead = (fileLength - offset < bufferSize) ? fileLength - offset : bufferSize;
        final block = await file.read(bytesToRead);

        final nonce = _cipher.newNonce();
        final secretBox = await _cipher.encrypt(
          block,
          secretKey: secretKey,
          nonce: nonce,
        );

        // Write: [Nonce (12)] + [MAC (16)] + [Ciphertext (up to 4MB)]
        currentSink.add(secretBox.nonce);
        currentSink.add(secretBox.mac.bytes);
        currentSink.add(secretBox.cipherText);

        offset += bytesToRead;
        currentBytesInLogicalChunk += block.length;

        // Split at limit
        if (currentBytesInLogicalChunk >= limit && offset < fileLength) {
          await currentSink.flush();
          await currentSink.close();

          chunkIndex++;
          currentBytesInLogicalChunk = 0;
          
          currentTempFile = File('$outputDirectory/temp_chunk_$chunkIndex.enc');
          currentSink = currentTempFile.openWrite();
          chunkPaths.add(currentTempFile.path);
        }
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
  }) async {
    final file = await encryptedChunkFile.open(mode: FileMode.read);
    final fileLength = await file.length();
    
    final outputSink = outputFile.openWrite(mode: append ? FileMode.writeOnlyAppend : FileMode.write);

    if (ctrIv != null) {
      final ctrAlgorithm = AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty);
      final secretKey = await ctrAlgorithm.newSecretKeyFromBytes(dekBytes);
      final int bufferSize = 4 * 1024 * 1024;
      int offset = 0;

      while (offset < fileLength) {
        final bytesToRead = (fileLength - offset < bufferSize) ? fileLength - offset : bufferSize;
        final block = await file.read(bytesToRead);

        final int startBlock = offset ~/ 16;
        final incrementedNonce = incrementNonce(ctrIv, startBlock);

        final decryptedData = await ctrAlgorithm.decrypt(
          SecretBox(block, nonce: incrementedNonce, mac: Mac.empty),
          secretKey: secretKey,
        );

        outputSink.add(decryptedData);
        offset += bytesToRead;
      }
    } else {
      final secretKey = await _cipher.newSecretKeyFromBytes(dekBytes);
      final int encryptedBlockSize = (4 * 1024 * 1024) + 12 + 16;
      int offset = 0;

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

}
