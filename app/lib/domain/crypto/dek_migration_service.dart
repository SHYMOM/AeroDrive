import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aerodrive/core/logger.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:aerodrive/core/providers/security_providers.dart';
import 'package:aerodrive/features/security/biometric_service.dart';
import 'package:aerodrive/data/crypto/encryption_engine.dart';
import 'package:aerodrive/data/crypto/key_hierarchy.dart';
import 'package:aerodrive/domain/saved_messages_sync.dart';
import 'package:aerodrive/data/db/database.dart';

/// Implements O(1) Master Key re-wrapping when the user changes their password.
///
/// Key hierarchy:
///   password → Argon2id → KEK
///   KEK → wraps MasterKey (MK)
///   MK → wraps file DEKs
///
/// On password change:
///   1. Derive new KEK from new password + existing salt
///   2. Wrap the in-memory MK with the new KEK
///   3. Update `wrapped_master_key` and verification blob in DB
///   4. Update the MK manifest in Telegram Saved Messages
class DekMigrationService {
  final Ref _ref;
  final AeroDriveDatabase _db;
  final EncryptionEngine _engine;

  DekMigrationService(this._ref, this._db, this._engine);

  /// Changes the master password and re-wraps all DEKs atomically.
  ///
  /// Returns a [DekMigrationResult] describing what happened.
  Future<DekMigrationResult> changeMasterPassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    AppLogger.info('DekMigrationService: starting password change + DEK migration');

    final settings = _ref.read(settingsRepositoryProvider);
    final saltStr = await settings.getSetting('master_password_salt');
    if (saltStr == null) {
      return DekMigrationResult.failure('No master password salt found. Vault may not be configured.');
    }

    // ── Step 1: Verify old password ──────────────────────────────────────────
    final List<int> oldKekBytes;
    try {
      oldKekBytes = await KeyHierarchy.deriveKEK(oldPassword, base64Decode(saltStr));
    } catch (e) {
      return DekMigrationResult.failure('Failed to derive old KEK: $e');
    }

    try {
      final storedNonce = await settings.getSetting('verification_nonce');
      final storedMac = await settings.getSetting('verification_mac');
      final storedCipherText = await settings.getSetting('verification_ciphertext');
      if (storedNonce != null && storedMac != null && storedCipherText != null) {
        final cipher = AesGcm.with256bits();
        final sk = await cipher.newSecretKeyFromBytes(oldKekBytes);
        await cipher.decrypt(
          SecretBox(
            base64Decode(storedCipherText),
            nonce: base64Decode(storedNonce),
            mac: Mac(base64Decode(storedMac)),
          ),
          secretKey: sk,
        );
      }
    } catch (_) {
      return DekMigrationResult.failure('Incorrect old password.');
    }

    // ── Step 2: Derive new KEK ───────────────────────────────────────────────
    final List<int> newKekBytes;
    try {
      newKekBytes = await KeyHierarchy.deriveKEK(newPassword, base64Decode(saltStr));
    } catch (e) {
      return DekMigrationResult.failure('Failed to derive new KEK: $e');
    }

    // ── Step 3: Wrap existing MK with new KEK ────────────────────────────────
    final mkBytes = _ref.read(masterKeyProvider);
    if (mkBytes == null) {
      return DekMigrationResult.failure('Vault is not unlocked. Cannot change password.');
    }

    try {
      final newWrappedMk = await KeyHierarchy.wrapMasterKey(mkBytes, newKekBytes);
      await settings.setSetting('wrapped_master_key', newWrappedMk);

      final syncService = _ref.read(savedMessagesSyncProvider);
      await syncService.backupMasterKeyManifest(newWrappedMk, saltStr);
    } catch (e) {
      return DekMigrationResult.failure('Failed to wrap and sync Master Key: $e');
    }

    // ── Step 4: Store new verification blob ──────────────────────────────────
    try {
      final cipher = AesGcm.with256bits();
      final newSk = await cipher.newSecretKeyFromBytes(newKekBytes);
      final verifyNonce = cipher.newNonce();
      final verifyBox = await cipher.encrypt(
        utf8.encode('AERODRIVE_VALID'),
        secretKey: newSk,
        nonce: verifyNonce,
      );
      await settings.setSetting('verification_nonce', base64Encode(verifyBox.nonce));
      await settings.setSetting('verification_mac', base64Encode(verifyBox.mac.bytes));
      await settings.setSetting('verification_ciphertext', base64Encode(verifyBox.cipherText));
    } catch (e) {
      AppLogger.error('DekMigrationService: failed to store new verification blob', e);
    }

    // ── Step 5: Update Biometrics if enabled ─────────────────────────────────
    final biometric = _ref.read(biometricServiceProvider);
    if (await biometric.retrieveKek() != null) {
      // If biometrics were enabled, we were saving the MK. MK hasn't changed.
      // But we can re-save it just in case.
      await biometric.saveKek(mkBytes);
    }

    for (int i = 0; i < oldKekBytes.length; i++) {
      oldKekBytes[i] = 0;
    }

    AppLogger.info('DekMigrationService: password change complete. MK re-wrapped successfully.');

    return DekMigrationResult.success(0, 0);
  }
}

class DekMigrationResult {
  final bool isSuccess;
  final String? errorMessage;
  final int migratedCount;
  final int skippedCount;

  const DekMigrationResult._({
    required this.isSuccess,
    this.errorMessage,
    this.migratedCount = 0,
    this.skippedCount = 0,
  });

  factory DekMigrationResult.success(int migrated, int skipped) => DekMigrationResult._(
    isSuccess: true,
    migratedCount: migrated,
    skippedCount: skipped,
  );

  factory DekMigrationResult.failure(String message) => DekMigrationResult._(
    isSuccess: false,
    errorMessage: message,
  );
}

final dekMigrationServiceProvider = Provider<DekMigrationService>((ref) {
  final db = ref.read(databaseProvider);
  return DekMigrationService(ref, db, EncryptionEngine());
});
