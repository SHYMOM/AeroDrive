import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cryptography/cryptography.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:aerodrive/core/providers/security_providers.dart';
import 'package:aerodrive/features/telegram/telegram_service.dart';
import 'package:aerodrive/core/logger.dart';

class RecoveryPhraseScreen extends ConsumerWidget {
  final String recoveryPhrase;
  final String password;

  const RecoveryPhraseScreen({
    super.key,
    required this.recoveryPhrase,
    required this.password,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = recoveryPhrase.split(' ');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recovery Phrase'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.vpn_key, size: 64, color: Colors.orangeAccent),
              const SizedBox(height: 24),
              Text(
                'Your 24-Word Recovery Phrase',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                ),
                child: const Text(
                  'Write these 24 words down on paper and store them securely. '
                  'If you lose your Master Key, this phrase is the ONLY way to recover your files.',
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: words.length,
                  itemBuilder: (context, index) {
                    return Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${index + 1}. ${words[index]}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: recoveryPhrase));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Recovery phrase copied to clipboard!')),
                        );
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy to Clipboard'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        // Derive and store the Master Key + recovery phrase hash
                        try {
                          final engine = ref.read(encryptionEngineProvider);
                          final settings = ref.read(settingsRepositoryProvider);

                          final random = Random.secure();
                          final saltBytes = List<int>.generate(32, (_) => random.nextInt(256));
                          final saltStr = base64Encode(saltBytes);

                          final kekBytes = await engine.deriveMasterKey(password, saltStr);

                          final cipher = AesGcm.with256bits();
                          final secretKey = await cipher.newSecretKeyFromBytes(kekBytes);
                          final nonce = cipher.newNonce();
                          final payload = utf8.encode('AERODRIVE_VALID');
                          final secretBox = await cipher.encrypt(payload, secretKey: secretKey, nonce: nonce);

                          await settings.setSetting('master_password_salt', saltStr);
                          await settings.setSetting('verification_nonce', base64Encode(secretBox.nonce));
                          await settings.setSetting('verification_mac', base64Encode(secretBox.mac.bytes));
                          await settings.setSetting('verification_ciphertext', base64Encode(secretBox.cipherText));
                          await settings.setSetting('recovery_phrase_hash', _hashPhrase(recoveryPhrase));

                          await _storeSaltInActiveChannel(ref, saltStr);

                          ref.read(masterKeyProvider.notifier).state = kekBytes;

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Vault initialized! You can now use your files.')),
                            );
                            Navigator.of(context).popUntil((route) => route.isFirst);
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
                            );
                          }
                        }
                      },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('I Have Saved It'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _hashPhrase(String phrase) {
    final bytes = utf8.encode(phrase);
    final hashBytes = List<int>.generate(32, (i) => bytes[i % bytes.length] ^ (i * 31 + 7) & 0xFF);
    return base64Encode(hashBytes);
  }

  Future<void> _storeSaltInActiveChannel(WidgetRef ref, String salt) async {
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
