import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cryptography/cryptography.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:aerodrive/core/providers/security_providers.dart';
import 'package:aerodrive/features/security/biometric_service.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _passwordCtrl = TextEditingController();
  bool _isLoading = false;
  bool _isBiometricAvailable = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    final biometric = ref.read(biometricServiceProvider);
    final kekBytes = await biometric.retrieveKek();
    if (kekBytes != null) {
      if (mounted) setState(() => _isBiometricAvailable = true);
      _unlockWithBiometrics(kekBytes);
    }
  }

  Future<void> _unlockWithBiometrics(List<int> kekBytes) async {
    final biometric = ref.read(biometricServiceProvider);
    final authenticated = await biometric.authenticate('Unlock AeroDrive');
    if (authenticated) {
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
      final engine = ref.read(encryptionEngineProvider);
      final settings = ref.read(settingsRepositoryProvider);

      final saltStr = await settings.getSetting('master_password_salt');
      final nonceStr = await settings.getSetting('verification_nonce');
      final macStr = await settings.getSetting('verification_mac');
      final cipherStr = await settings.getSetting('verification_ciphertext');

      if (saltStr == null || nonceStr == null || macStr == null || cipherStr == null) {
        throw Exception("Security configuration corrupted.");
      }

      // 1. Derive KEK
      final kekBytes = await engine.deriveMasterKey(password, saltStr);

      // 2. Decrypt verification payload
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
          // Success! Load to memory
          ref.read(masterKeyProvider.notifier).state = kekBytes;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.lock, size: 64, color: Colors.blueAccent),
                const SizedBox(height: 24),
                const Text(
                  'Vault Locked',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter your Master Password to decrypt your keys.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Master Password',
                    prefixIcon: Icon(Icons.password),
                  ),
                  onSubmitted: (_) => _unlock(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ],
                const SizedBox(height: 32),
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: _unlock,
                              child: const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text('Unlock'),
                              ),
                            ),
                          ),
                          if (_isBiometricAvailable) ...[
                            const SizedBox(width: 16),
                            IconButton.filled(
                              onPressed: () async {
                                final kekBytes = await ref.read(biometricServiceProvider).retrieveKek();
                                if (kekBytes != null) {
                                  _unlockWithBiometrics(kekBytes);
                                }
                              },
                              icon: const Icon(Icons.fingerprint),
                              iconSize: 32,
                              padding: const EdgeInsets.all(12),
                            ),
                          ]
                        ],
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
