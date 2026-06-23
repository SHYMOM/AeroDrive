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

  /// Encrypts a source file into a temporary encrypted file using Stream-to-Disk architecture.
  /// Enforces a strict 4MB RAM buffer per the design requirements.
  /// Max logical chunk limit is 1.5GB. If the file exceeds this, it splits into multiple `.enc` files.
  Future<List<String>> encryptStreamToDisk({
    required File sourceFile,
    required String outputDirectory,
    required List<int> dekBytes,
  }) async {
    final secretKey = await _cipher.newSecretKeyFromBytes(dekBytes);
    
    final int bufferSize = 4 * 1024 * 1024; // EXACT 4 MB RAM Buffer
    final int chunkLimit = (1.5 * 1024 * 1024 * 1024).toInt(); // 1.5 GB logical limit

    final file = await sourceFile.open(mode: FileMode.read);
    final fileLength = await file.length();
    
    int currentBytesInLogicalChunk = 0;
    int chunkIndex = 0;
    
    List<String> chunkPaths = [];
    
    File currentTempFile = File('$outputDirectory/temp_chunk_$chunkIndex.enc');
    IOSink currentSink = currentTempFile.openWrite();
    chunkPaths.add(currentTempFile.path);

    int offset = 0;
    while (offset < fileLength) {
      // Read exactly 4MB or whatever is left
      final bytesToRead = (fileLength - offset < bufferSize) ? fileLength - offset : bufferSize;
      final block = await file.read(bytesToRead);
      offset += bytesToRead;

      final nonce = _cipher.newNonce();
      final secretBox = await _cipher.encrypt(
        block,
        secretKey: secretKey,
        nonce: nonce,
      );

      // Write exactly: [Nonce (12)] + [MAC (16)] + [Ciphertext (up to 4MB)]
      currentSink.add(secretBox.nonce);
      currentSink.add(secretBox.mac.bytes);
      currentSink.add(secretBox.cipherText);

      currentBytesInLogicalChunk += block.length;

      // Split at 1.5GB
      if (currentBytesInLogicalChunk >= chunkLimit && offset < fileLength) {
        await currentSink.flush();
        await currentSink.close();

        chunkIndex++;
        currentBytesInLogicalChunk = 0;
        
        currentTempFile = File('$outputDirectory/temp_chunk_$chunkIndex.enc');
        currentSink = currentTempFile.openWrite();
        chunkPaths.add(currentTempFile.path);
      }
    }

    await file.close();
    await currentSink.flush();
    await currentSink.close();

    return chunkPaths;
  }
  
  /// Decrypts an encrypted Stream-to-Disk chunk file back into a standard file.
  Future<void> decryptDiskToStream({
    required File encryptedChunkFile,
    required File outputFile,
    required List<int> dekBytes,
  }) async {
    final secretKey = await _cipher.newSecretKeyFromBytes(dekBytes);
    final file = await encryptedChunkFile.open(mode: FileMode.read);
    final fileLength = await file.length();
    
    final outputSink = outputFile.openWrite();

    // The encrypted block size on disk is exactly 4MB + 12 (nonce) + 16 (MAC)
    final int encryptedBlockSize = (4 * 1024 * 1024) + 12 + 16;
    int offset = 0;

    while (offset < fileLength) {
      final bytesToRead = (fileLength - offset < encryptedBlockSize) ? fileLength - offset : encryptedBlockSize;
      final block = await file.read(bytesToRead);
      offset += bytesToRead;

      final nonce = block.sublist(0, 12);
      final macBytes = block.sublist(12, 28);
      final cipherText = block.sublist(28);

      final decryptedData = await _cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
        secretKey: secretKey,
      );

      outputSink.add(decryptedData);
    }

    await file.close();
    await outputSink.flush();
    await outputSink.close();
  }
}
