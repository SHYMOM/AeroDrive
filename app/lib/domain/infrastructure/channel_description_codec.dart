import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../core/constants.dart';

/// Encrypts and decrypts AeroDrive infrastructure metadata stored in
/// Telegram channel descriptions.
///
/// Format: `AERODRIVE_INFRA_v1:<base64(nonce + cipherText + mac)>`
///
/// This serves as the cross-device source of truth for channel discovery.
/// When a user reinstalls the app, they log into Telegram and the discovery
/// service reads the descriptions of every admin channel it finds. If it can
/// decrypt a description with the Master Key, it knows the channel's purpose
/// (storage/config/shared) and restores the local configuration.
class ChannelDescriptionCodec {
  static final AesGcm _cipher = AesGcm.with256bits();

  /// Encrypts infrastructure metadata into a channel description string.
  ///
  /// [purpose] — one of 'storage', 'config', 'shared'
  /// [appVersion] — current app version string for compatibility checks
  /// [keySalt] — BIP39-derived salt (or Argon2id salt) for cross-device KDF
  /// [channelIndex] — 0-based index (only meaningful for storage channels)
  /// [totalStorageChannels] — total number of storage channels provisioned
  static Future<String> encode({
    required String purpose,
    required String appVersion,
    required String keySalt,
    required int channelIndex,
    required int totalStorageChannels,
    required SecretKey masterKey,
  }) async {
    final Map<String, dynamic> payload = {
      'v': ChannelConstants.descriptionVersion,
      'p': purpose,
      'av': appVersion,
      'ks': keySalt,
      'ci': channelIndex,
      'tc': totalStorageChannels,
    };

    final jsonStr = jsonEncode(payload);
    final plaintext = utf8.encode(jsonStr);

    final nonce = _cipher.newNonce();
    final secretBox = await _cipher.encrypt(
      plaintext,
      secretKey: masterKey,
      nonce: nonce,
    );

    final builder = BytesBuilder();
    builder.add(secretBox.nonce);
    builder.add(secretBox.cipherText);
    builder.add(secretBox.mac.bytes);

    final encoded = base64Encode(builder.toBytes());
    return '${ChannelConstants.infraDescriptionPrefix}$encoded';
  }

  /// Decrypts and parses an AeroDrive infrastructure channel description.
  ///
  /// Returns null if the description is not a valid AeroDrive description,
  /// or if it was encrypted with a different Master Key (wrong key → GCM
  /// authentication failure → null).
  static Future<Map<String, dynamic>?> decode({
    required String description,
    required SecretKey masterKey,
  }) async {
    // Check prefix
    if (!description.startsWith(ChannelConstants.infraDescriptionPrefix)) {
      return null;
    }

    final encoded = description.substring(
      ChannelConstants.infraDescriptionPrefix.length,
    );

    Uint8List encryptedBytes;
    try {
      encryptedBytes = base64Decode(encoded);
    } catch (e) {
      return null;
    }

    // Minimum: 12 (nonce) + 1 (cipherText) + 16 (mac) = 29
    if (encryptedBytes.length < 29) return null;

    final nonce = encryptedBytes.sublist(0, 12);
    final macBytes = encryptedBytes.sublist(encryptedBytes.length - 16);
    final cipherText = encryptedBytes.sublist(12, encryptedBytes.length - 16);

    try {
      final secretBox = SecretBox(
        cipherText,
        nonce: nonce,
        mac: Mac(macBytes),
      );

      final plaintext = await _cipher.decrypt(
        secretBox,
        secretKey: masterKey,
      );

      final jsonStr = utf8.decode(plaintext);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      // Decryption failed — wrong key or corrupted data
      return null;
    }
  }

  /// Convenience wrapper: returns the purpose field of a decoded description,
  /// or null if the description isn't a valid AeroDrive infra description.
  static Future<String?> readPurpose({
    required String description,
    required SecretKey masterKey,
  }) async {
    final decoded = await decode(
      description: description,
      masterKey: masterKey,
    );
    return decoded?['p'] as String?;
  }
}
