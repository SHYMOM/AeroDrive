import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cryptography/cryptography.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:aerodrive/core/providers/security_providers.dart';
import 'package:aerodrive/core/security/master_key_provider.dart';
import 'package:aerodrive/data/crypto/encryption_engine.dart';
import 'package:aerodrive/data/crypto/key_hierarchy.dart';
import 'package:aerodrive/domain/saved_messages_sync.dart';
import 'package:aerodrive/features/security/biometric_service.dart';
import 'package:aerodrive/core/widgets/premium_button.dart';
import 'package:aerodrive/core/theme/app_colors.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _passwordCtrl = TextEditingController();
  bool _isLoading = false;
  bool _isBiometricAvailable = false;
  bool _hasDuressPin = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
    _checkDuressPin();
  }

  Future<void> _checkBiometrics() async {
    final biometric = ref.read(biometricServiceProvider);
    final kekBytes = await biometric.retrieveKek();
    if (kekBytes != null) {
      if (mounted) setState(() => _isBiometricAvailable = true);
      _unlockWithBiometrics(kekBytes);
    }
  }

  Future<void> _checkDuressPin() async {
    final settings = ref.read(settingsRepositoryProvider);
    final pin = await settings.getSetting('duress_pin');
    if (mounted) setState(() => _hasDuressPin = pin != null);
  }

  Future<void> _unlockWithBiometrics(List<int> kekBytes) async {
    final biometric = ref.read(biometricServiceProvider);
    final authenticated = await biometric.authenticate('Unlock AeroDrive');
    if (authenticated) {
      MasterKeyProvider.instance.setKey(kekBytes);
      ref.read(masterKeyProvider.notifier).state = kekBytes;
      if (mounted) {
        context.go('/');
      }
    }
  }

  Future<void> _unlock() async {
    final password = _passwordCtrl.text;
    if (password.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final settings = ref.read(settingsRepositoryProvider);

      // Check duress PIN
      final duressPin = await settings.getSetting('duress_pin');
      if (duressPin != null && password == duressPin) {
        // Duress triggered — wipe local DB
        final db = ref.read(databaseProvider);
        await db.transaction(() async {
          await db.delete(db.folders).go();
          await db.delete(db.files).go();
          await db.delete(db.chunks).go();
          await db.delete(db.transferQueue).go();
        });
        if (mounted) {
          setState(() {
            _error = 'Invalid password.';
            _passwordCtrl.clear();
          });
        }
        return;
      }

      final engine = ref.read(encryptionEngineProvider);
      final saltStr = await settings.getSetting('master_password_salt');
      final nonceStr = await settings.getSetting('verification_nonce');
      final macStr = await settings.getSetting('verification_mac');
      final cipherStr = await settings.getSetting('verification_ciphertext');

      if (saltStr == null ||
          nonceStr == null ||
          macStr == null ||
          cipherStr == null) {
        throw Exception("Security configuration corrupted.");
      }

      final kekBytes = await KeyHierarchy.deriveKEK(
        password,
        base64Decode(saltStr),
      );

      final cipher = AesGcm.with256bits();
      final secretKey = await cipher.newSecretKeyFromBytes(kekBytes);
      final nonce = base64Decode(nonceStr);
      final mac = Mac(base64Decode(macStr));
      final cipherText = base64Decode(cipherStr);

      try {
        final payload = await cipher.decrypt(
          SecretBox(cipherText, nonce: nonce, mac: mac),
          secretKey: secretKey,
        );

        if (utf8.decode(payload) == 'AERODRIVE_VALID') {
          // Password is correct! Now get the Master Key (MK).
          List<int> mkBytes;

          final wrappedMkStr = await settings.getSetting('wrapped_master_key');
          if (wrappedMkStr != null && wrappedMkStr.isNotEmpty) {
            // Unwrap from local storage
            mkBytes = await KeyHierarchy.unwrapMasterKey(
              wrappedMkStr,
              kekBytes,
            );
          } else {
            // First time login on new device, scan Telegram Saved Messages for MK Manifest
            final syncService = ref.read(savedMessagesSyncProvider);
            final fetchedManifest = await syncService.fetchWrappedMasterKey();
            if (fetchedManifest != null &&
                fetchedManifest['wrappedMk'] != null) {
              final fetchedWrappedMk = fetchedManifest['wrappedMk']!;
              mkBytes = await KeyHierarchy.unwrapMasterKey(
                fetchedWrappedMk,
                kekBytes,
              );
              // Save it locally for next time
              await settings.setSetting('wrapped_master_key', fetchedWrappedMk);

              if (fetchedManifest['salt'] != null) {
                await settings.setSetting(
                  'master_password_salt',
                  fetchedManifest['salt']!,
                );
              }
            } else {
              // Legacy fallback (User had KEK = MK previously, before this update)
              mkBytes = kekBytes;
              // Upgrade them!
              final newWrappedMk = await KeyHierarchy.wrapMasterKey(
                mkBytes,
                kekBytes,
              );
              await settings.setSetting('wrapped_master_key', newWrappedMk);
              final salt =
                  await settings.getSetting('master_password_salt') ?? '';
              await syncService.backupMasterKeyManifest(newWrappedMk, salt);
            }
          }

          MasterKeyProvider.instance.setKey(mkBytes);
          ref.read(masterKeyProvider.notifier).state = mkBytes;
          if (mounted) {
            context.go('/');
          }
        } else {
          throw Exception("Invalid password.");
        }
      } catch (e) {
        throw Exception("Invalid password.");
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _passwordCtrl.clear();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showRecoverFromPhrase() {
    showDialog(context: context, builder: (ctx) => _RecoverFromPhraseDialog());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.0, -0.3),
            radius: 1.8,
            colors: [
              Color(0xFF7C3AED), // neonViolet glow
              Color(0xFF0D0E23), // deepSpace
              Color(0xFF0D0E23), // deepSpace
            ],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28.0),
              child: RepaintBoundary(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: AppColors.glassBgDark,
                        border: Border.all(
                          color: AppColors.glassBorder,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary.withOpacity(0.15),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.2),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.lock_rounded,
                              size: 48,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Vault Locked',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Enter your Master Password to unlock your vault.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 14,
                            ),
                          ),
                          if (_hasDuressPin)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                'Duress PIN is active. If forced, enter your duress PIN instead.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.error.withOpacity(0.9),
                                ),
                              ),
                            ),
                          const SizedBox(height: 32),
                          TextField(
                            controller: _passwordCtrl,
                            obscureText: true,
                            autofocus: true,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Master Password',
                              labelStyle: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                              ),
                              prefixIcon: Icon(
                                Icons.password,
                                color: Colors.white.withOpacity(0.5),
                              ),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.05),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.white.withOpacity(0.1),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.white.withOpacity(0.1),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: AppColors.primary,
                                  width: 2,
                                ),
                              ),
                            ),
                            onSubmitted: (_) => _unlock(),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              style: const TextStyle(
                                color: AppColors.error,
                                fontSize: 13,
                              ),
                            ),
                          ],
                          const SizedBox(height: 32),
                          if (_isLoading)
                            const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.primary,
                              ),
                            )
                          else
                            Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: PremiumButton(
                                        label: 'Unlock',
                                        onPressed: _unlock,
                                        icon: Icons.vpn_key,
                                        gradient: const [
                                          AppColors.primary,
                                          AppColors.secondary,
                                        ],
                                      ),
                                    ),
                                    if (_isBiometricAvailable) ...[
                                      const SizedBox(width: 16),
                                      Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          color: AppColors.primary.withOpacity(
                                            0.1,
                                          ),
                                          border: Border.all(
                                            color: AppColors.primary
                                                .withOpacity(0.3),
                                          ),
                                        ),
                                        child: IconButton(
                                          onPressed: () async {
                                            final kekBytes = await ref
                                                .read(biometricServiceProvider)
                                                .retrieveKek();
                                            if (kekBytes != null) {
                                              _unlockWithBiometrics(kekBytes);
                                            }
                                          },
                                          icon: const Icon(
                                            Icons.fingerprint,
                                            color: AppColors.primary,
                                          ),
                                          iconSize: 28,
                                          padding: const EdgeInsets.all(14),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 24),
                                TextButton.icon(
                                  onPressed: _showRecoverFromPhrase,
                                  icon: Icon(
                                    Icons.vpn_key_outlined,
                                    size: 16,
                                    color: Colors.white.withOpacity(0.5),
                                  ),
                                  label: Text(
                                    'Recover with recovery phrase',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ), // Closes inner Column
                        ], // Closes outer Column children
                      ), // Closes outer Column
                    ), // Closes Container
                  ), // Closes BackdropFilter
                ), // Closes ClipRRect
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecoverFromPhraseDialog extends ConsumerStatefulWidget {
  @override
  ConsumerState<_RecoverFromPhraseDialog> createState() =>
      _RecoverFromPhraseDialogState();
}

class _RecoverFromPhraseDialogState
    extends ConsumerState<_RecoverFromPhraseDialog> {
  final _phraseCtrl = TextEditingController();
  bool _isLoading = false;
  String? _error;

  Future<void> _recover() async {
    final phrase = _phraseCtrl.text.trim().toLowerCase();
    if (!EncryptionEngine().isValidRecoveryPhrase(phrase)) {
      setState(
        () => _error =
            'Invalid recovery phrase. Enter all 24 words separated by spaces.',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Deterministic derivation from BIP39 seed — same phrase = same key across devices
      final engine = EncryptionEngine();
      final kekBytes = await engine.deriveMasterKeyFromPhrase(phrase);
      final saltStr = base64Encode(engine.saltFromPhrase(phrase));

      final settings = ref.read(settingsRepositoryProvider);
      final cipher = AesGcm.with256bits();
      final secretKey = await cipher.newSecretKeyFromBytes(kekBytes);
      final nonce = cipher.newNonce();
      final payload = utf8.encode('AERODRIVE_VALID');
      final secretBox = await cipher.encrypt(
        payload,
        secretKey: secretKey,
        nonce: nonce,
      );

      await settings.setSetting('master_password_salt', saltStr);
      await settings.setSetting(
        'verification_nonce',
        base64Encode(secretBox.nonce),
      );
      await settings.setSetting(
        'verification_mac',
        base64Encode(secretBox.mac.bytes),
      );
      await settings.setSetting(
        'verification_ciphertext',
        base64Encode(secretBox.cipherText),
      );

      MasterKeyProvider.instance.setKey(kekBytes);
      ref.read(masterKeyProvider.notifier).state = kekBytes;

      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        context.go('/');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recovery successful! Vault re-keyed.')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Recovery failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Recover from Phrase'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Enter your 24-word recovery phrase to restore your Master Key.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phraseCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Paste all 24 words here...',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        _isLoading
            ? const CircularProgressIndicator()
            : FilledButton.icon(
                onPressed: _recover,
                icon: const Icon(Icons.restore),
                label: const Text('Recover'),
              ),
      ],
    );
  }
}
