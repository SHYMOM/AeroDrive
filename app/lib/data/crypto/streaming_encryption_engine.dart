import 'dart:typed_data';
import 'package:pointycastle/export.dart';

class StreamingEncryptionEngine {
  /// Decrypts a specific byte range of a stream encrypted with AES-256-CTR.
  /// 
  /// AES-CTR turns a block cipher into a stream cipher by encrypting successive
  /// values of a "counter". The AES block size is 16 bytes.
  /// 
  /// [dekBytes]: The 32-byte (256-bit) Data Encryption Key.
  /// [nonce]: The 16-byte IV/Nonce used during encryption.
  /// [cipherTextChunk]: The raw bytes read from the file.
  /// [globalOffset]: The absolute byte offset of `cipherTextChunk` in the full logical file.
  static Uint8List decryptStreamRange({
    required Uint8List dekBytes,
    required Uint8List nonce,
    required Uint8List cipherTextChunk,
    required int globalOffset,
  }) {
    if (cipherTextChunk.isEmpty) return Uint8List(0);

    // Initialize AES in CTR mode
    final cipher = CTRStreamCipher(AESEngine())
      ..init(
        false, // false = decrypt (CTR encrypt/decrypt is the same XOR operation)
        ParametersWithIV(KeyParameter(dekBytes), nonce),
      );

    // Because AES-CTR block size is 16 bytes, we need to know exactly which 
    // 16-byte block the globalOffset starts at.
    final int blockSize = 16;
    
    // The number of full blocks to skip
    final int skipBlocks = globalOffset ~/ blockSize;
    
    // The byte offset within the first block
    final int internalOffset = globalOffset % blockSize;

    // We must manually advance the CTR cipher to the correct block.
    // PointyCastle's CTRStreamCipher doesn't have a public `seek()` method, 
    // but we can just skip the blocks by processing dummy bytes, OR we can
    // instantiate the counter manually if we wrote a custom CTR implementation.
    // However, PointyCastle *does* process bytes linearly. For large offsets (e.g. 1GB),
    // skipping 1GB of dummy bytes takes too long.
    
    // Let's implement true O(1) seeking by manually updating the IV/Counter block!
    
    // A standard AES-CTR nonce/IV is 16 bytes. 
    // Usually, the upper 8-12 bytes are the random nonce, and the lower 4-8 bytes are the counter.
    // PointyCastle's CTR increments the entire 16-byte IV as a big-endian integer.
    
    final seekedIv = _incrementIv(nonce, skipBlocks);
    
    // Re-initialize cipher with the seeked IV
    cipher.init(
      false,
      ParametersWithIV(KeyParameter(dekBytes), seekedIv),
    );

    // If internalOffset > 0, we must process `internalOffset` dummy bytes to align the keystream.
    if (internalOffset > 0) {
      final dummy = Uint8List(internalOffset);
      cipher.processBytes(dummy, 0, internalOffset, dummy, 0);
    }

    // Now decrypt the actual ciphertext chunk
    final out = Uint8List(cipherTextChunk.length);
    cipher.processBytes(cipherTextChunk, 0, cipherTextChunk.length, out, 0);
    
    return out;
  }

  /// Increments a 16-byte big-endian IV by a specific block count.
  static Uint8List _incrementIv(Uint8List iv, int blocksToSkip) {
    final result = Uint8List.fromList(iv);
    int carry = blocksToSkip;
    
    for (int i = 15; i >= 0 && carry > 0; i--) {
      final sum = result[i] + carry;
      result[i] = sum & 0xFF;
      carry = sum >> 8;
    }
    
    return result;
  }
}
