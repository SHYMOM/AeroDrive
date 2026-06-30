import 'dart:convert';
import 'package:cryptography/cryptography.dart';

class KeyHierarchy {
  static const int _argon2Iterations = 2; // Matches existing app defaults
  static const int _argon2Memory = 19456;
  static const int _argon2Parallelism = 1;

  /// Derives a 256-bit Key Encryption Key (KEK) from a password using Argon2id.
  static Future<List<int>> deriveKEK(String password, List<int> salt) async {
    final argon2 = Argon2id(
      memory: _argon2Memory,
      iterations: _argon2Iterations,
      parallelism: _argon2Parallelism,
      hashLength: 32,
    );
    final secretKey = await argon2.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    return await secretKey.extractBytes();
  }

  /// Wraps (encrypts) the Master Key (MK) with the Key Encryption Key (KEK) using AES-GCM.
  /// Returns a base64 encoded string: "nonce|mac|ciphertext".
  static Future<String> wrapMasterKey(List<int> masterKey, List<int> kek) async {
    final cipher = AesGcm.with256bits();
    final secretKey = await cipher.newSecretKeyFromBytes(kek);
    final nonce = cipher.newNonce();
    
    final secretBox = await cipher.encrypt(
      masterKey,
      secretKey: secretKey,
      nonce: nonce,
    );

    return [
      base64Encode(secretBox.nonce),
      base64Encode(secretBox.mac.bytes),
      base64Encode(secretBox.cipherText),
    ].join('|');
  }

  /// Unwraps (decrypts) the Master Key (MK) using the Key Encryption Key (KEK).
  /// Throws if decryption fails (e.g., wrong KEK).
  static Future<List<int>> unwrapMasterKey(String wrappedPayload, List<int> kek) async {
    final parts = wrappedPayload.split('|');
    if (parts.length != 3) {
      throw Exception('Invalid wrapped Master Key payload format.');
    }

    final nonce = base64Decode(parts[0]);
    final mac = Mac(base64Decode(parts[1]));
    final cipherText = base64Decode(parts[2]);

    final cipher = AesGcm.with256bits();
    final secretKey = await cipher.newSecretKeyFromBytes(kek);

    final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
    final masterKey = await cipher.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    return masterKey;
  }
}
