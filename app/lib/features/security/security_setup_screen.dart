import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cryptography/cryptography.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:aerodrive/core/providers/security_providers.dart';
import 'package:aerodrive/features/security/biometric_service.dart';
import 'package:aerodrive/features/telegram/telegram_service.dart';
import 'package:aerodrive/core/logger.dart';
import 'package:aerodrive/data/crypto/key_hierarchy.dart';
import 'package:aerodrive/domain/saved_messages_sync.dart';

class SecuritySetupScreen extends ConsumerStatefulWidget {
  const SecuritySetupScreen({super.key});

  @override
  ConsumerState<SecuritySetupScreen> createState() => _SecuritySetupScreenState();
}

class _SecuritySetupScreenState extends ConsumerState<SecuritySetupScreen> {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _isLoading = false;
  bool _useBiometrics = false;
  bool _isBiometricAvailable = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(biometricServiceProvider).isBiometricAvailable().then((value) {
      if (mounted) setState(() => _isBiometricAvailable = value);
    });
  }

  Future<void> _setupSecurity() async {
    final password = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;

    if (password.length < 8) {
      setState(() => _error = "Password must be at least 8 characters.");
      return;
    }
    if (password != confirm) {
      setState(() => _error = "Passwords do not match.");
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final engine = ref.read(encryptionEngineProvider);
      final settings = ref.read(settingsRepositoryProvider);
      final syncService = ref.read(savedMessagesSyncProvider);

      // 1. Scan for existing MK Manifest in Saved Messages FIRST
      final existingManifest = await syncService.fetchWrappedMasterKey();
      
      List<int> saltBytes;
      String saltStr;
      List<int> mkBytes;
      String wrappedMkStr;
      List<int> kekBytes;
      
      if (existingManifest != null && existingManifest['wrappedMk'] != null && existingManifest['salt'] != null) {
        // Attempt to unlock existing Vault
        saltStr = existingManifest['salt']!;
        saltBytes = base64Decode(saltStr);
        kekBytes = await KeyHierarchy.deriveKEK(password, saltBytes);
        wrappedMkStr = existingManifest['wrappedMk']!;
        
        try {
          mkBytes = await KeyHierarchy.unwrapMasterKey(wrappedMkStr, kekBytes);
          AppLogger.info('Successfully unwrapped existing Master Key from Saved Messages sync!');
        } catch (e) {
          setState(() => _error = "Existing vault found, but password was incorrect.");
          return;
        }
      } else {
        // Create NEW Vault
        final random = Random.secure();
        saltBytes = List<int>.generate(32, (_) => random.nextInt(256));
        saltStr = base64Encode(saltBytes);
        kekBytes = await KeyHierarchy.deriveKEK(password, saltBytes);
        mkBytes = List<int>.generate(32, (_) => random.nextInt(256));
        wrappedMkStr = await KeyHierarchy.wrapMasterKey(mkBytes, kekBytes);
      }

      // 5. Encrypt verification payload "AERODRIVE_VALID" using KEK
      final cipher = AesGcm.with256bits();
      final secretKey = await cipher.newSecretKeyFromBytes(kekBytes);
      final nonce = cipher.newNonce();
      final payload = utf8.encode('AERODRIVE_VALID');
      
      final secretBox = await cipher.encrypt(
        payload,
        secretKey: secretKey,
        nonce: nonce,
      );

      // 6. Save to Database
      await settings.setSetting('master_password_salt', saltStr);
      await settings.setSetting('verification_nonce', base64Encode(secretBox.nonce));
      await settings.setSetting('verification_mac', base64Encode(secretBox.mac.bytes));
      await settings.setSetting('verification_ciphertext', base64Encode(secretBox.cipherText));
      await settings.setSetting('wrapped_master_key', wrappedMkStr); // Save the wrapped MK!

      // 7. Save salt to active channel description for cross-device sync
      await _storeSaltInActiveChannel(saltStr);

      // 7b. Backup Master Key Manifest to Telegram Saved Messages
      await syncService.backupMasterKeyManifest(wrappedMkStr, saltStr);

      // 8. Save MK to memory provider
      ref.read(masterKeyProvider.notifier).state = mkBytes;

      // 9. Handle Biometrics (save KEK so we can unwrap MK later, or save MK directly? Save MK directly is easier, but KEK allows password changes. Let's save MK directly for biometrics.)
      final biometric = ref.read(biometricServiceProvider);
      if (_useBiometrics && _isBiometricAvailable) {
        final authenticated = await biometric.authenticate('Enable Biometric Unlock');
        if (authenticated) {
          await biometric.saveKek(mkBytes); // Actually saving MK
        }
      } else {
        await biometric.clearKek();
      }

      if (mounted) {
        context.go('/');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Master Password successfully configured!')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Setup Master Password')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.security, size: 64, color: Colors.blueAccent),
                const SizedBox(height: 24),
                const Text(
                  'Zero-Knowledge Security',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your Master Password mathematically locks your encryption keys. If you forget it, your files are lost forever.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Master Password',
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm Password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                if (_isBiometricAvailable) ...[
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Enable Biometric Unlock'),
                    subtitle: const Text('Store key securely on device for faster access'),
                    value: _useBiometrics,
                    onChanged: (val) => setState(() => _useBiometrics = val),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ],
                const SizedBox(height: 32),
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : FilledButton(
                        onPressed: _setupSecurity,
                        child: const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('Initialize Vault'),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Stores the newly created salt in the active channel description so other
  /// devices discover it and derive the same KEK.
  Future<void> _storeSaltInActiveChannel(String salt) async {
    try {
      final settings = ref.read(settingsRepositoryProvider);
      final channelIdStr = await settings.getSetting('active_channel_id');
      if (channelIdStr == null || channelIdStr.isEmpty) return;

      final existing = await ref.read(telegramServiceProvider.notifier)
          .getChannelDescription(int.parse(channelIdStr));
      if (existing != null && existing.startsWith('AERODRIVE_SALT:')) {
        AppLogger.info('Salt already present in channel — not overwriting');
        return;
      }

      await ref.read(telegramServiceProvider.notifier)
          .setChatDescription(int.parse(channelIdStr), 'AERODRIVE_SALT:$salt');
      AppLogger.info('Stored salt in active channel description');
    } catch (e) {
      AppLogger.error('Failed to store salt in active channel', e);
    }
  }
}
