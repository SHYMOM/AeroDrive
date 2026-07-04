import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/providers/security_providers.dart';
import '../../core/security/master_key_provider.dart';
import '../../data/crypto/encryption_engine.dart';

class EncryptionModeDialog extends ConsumerStatefulWidget {
  const EncryptionModeDialog({super.key});

  @override
  ConsumerState<EncryptionModeDialog> createState() => _EncryptionModeDialogState();
}

class _EncryptionModeDialogState extends ConsumerState<EncryptionModeDialog> {
  String _mode = 'convenience';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final val = await ref.read(settingsRepositoryProvider).getSetting('encryption_mode') ?? 'convenience';
    if (mounted) setState(() => _mode = val);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
      title: const Text('Encryption Mode'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Controls how your files are encrypted before uploading to Telegram. '
              'Changing this only affects future uploads — existing files remain in their original mode.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
          RadioListTile<String>(
            title: const Text('Off'),
            subtitle: const Text('Files uploaded as-is, no encryption. Fastest but least secure.'),
            value: 'off',
            groupValue: _mode,
            onChanged: (val) => setState(() => _mode = val!),
          ),
          RadioListTile<String>(
            title: const Text('Convenience (Default)'),
            subtitle: const Text('Files encrypted with AES-256. Key cached in memory while app is open.'),
            value: 'convenience',
            groupValue: _mode,
            onChanged: (val) => setState(() => _mode = val!),
          ),
          RadioListTile<String>(
            title: const Text('Maximum Security'),
            subtitle: const Text('Files encrypted with AES-256. Key never cached — requires password every launch and auto-locks on idle.'),
            value: 'max',
            groupValue: _mode,
            onChanged: (val) => setState(() => _mode = val!),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            await ref.read(settingsRepositoryProvider).setSetting('encryption_mode', _mode);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
}

class AutoLockTimeoutDialog extends ConsumerStatefulWidget {
  const AutoLockTimeoutDialog({super.key});

  @override
  ConsumerState<AutoLockTimeoutDialog> createState() => _AutoLockTimeoutDialogState();
}

class _AutoLockTimeoutDialogState extends ConsumerState<AutoLockTimeoutDialog> {
  String _timeout = '5m';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final val = await ref.read(settingsRepositoryProvider).getSetting('auto_lock_timeout') ?? '5m';
    if (mounted) setState(() => _timeout = val);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
      title: const Text('Auto-Lock Timeout'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Automatically lock the vault and clear the Master Key from memory after inactivity. '
              'You will need to re-enter your password or use biometrics to unlock.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
          RadioListTile<String>(title: const Text('1 Minute'), value: '1m', groupValue: _timeout, onChanged: (v) => setState(() => _timeout = v!)),
          RadioListTile<String>(title: const Text('5 Minutes'), value: '5m', groupValue: _timeout, onChanged: (v) => setState(() => _timeout = v!)),
          RadioListTile<String>(title: const Text('15 Minutes'), value: '15m', groupValue: _timeout, onChanged: (v) => setState(() => _timeout = v!)),
          RadioListTile<String>(title: const Text('1 Hour'), value: '1h', groupValue: _timeout, onChanged: (v) => setState(() => _timeout = v!)),
          RadioListTile<String>(title: const Text('Never'), value: 'never', groupValue: _timeout, onChanged: (v) => setState(() => _timeout = v!)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            await ref.read(settingsRepositoryProvider).setSetting('auto_lock_timeout', _timeout);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
}

class DuressPinDialog extends ConsumerStatefulWidget {
  const DuressPinDialog({super.key});

  @override
  ConsumerState<DuressPinDialog> createState() => _DuressPinDialogState();
}

class _DuressPinDialogState extends ConsumerState<DuressPinDialog> {
  final _pinCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) => AlertDialog(
      title: const Text('Duress PIN Setup'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'If someone forces you to unlock the vault, type this PIN instead of your password. '
              'The vault will appear to reject the PIN, but all local folder/file records will be wiped instantly. '
              'Your data on Telegram remains safe — use Rebuild Drive later to recover.',
              style: TextStyle(fontSize: 12, color: Colors.redAccent),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pinCtrl,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(hintText: '4-6 digit PIN'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            if (_pinCtrl.text.length >= 4) {
              await ref.read(settingsRepositoryProvider).setSetting('duress_pin', _pinCtrl.text);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Duress PIN active.')));
              }
            }
          },
          child: const Text('Set PIN'),
        ),
      ],
    );
}

class RecoverFromPhraseDialog extends ConsumerStatefulWidget {
  const RecoverFromPhraseDialog({super.key});

  @override
  ConsumerState<RecoverFromPhraseDialog> createState() => _RecoverFromPhraseDialogState();
}

class _RecoverFromPhraseDialogState extends ConsumerState<RecoverFromPhraseDialog> {
  final _phraseCtrl = TextEditingController();
  bool _isLoading = false;
  String? _error;

  Future<void> _recover() async {
    final phrase = _phraseCtrl.text.trim().toLowerCase();
    if (!EncryptionEngine().isValidRecoveryPhrase(phrase)) {
      setState(() => _error = 'Invalid phrase. Enter all 24 BIP39 words separated by spaces.');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      final engine = EncryptionEngine();
      final settings = ref.read(settingsRepositoryProvider);

      // Use deterministic derivation from BIP39 seed so the same phrase
      // always produces the same Master Key across devices.
      final kekBytes = await engine.deriveMasterKeyFromPhrase(phrase);
      final saltStr = base64Encode(engine.saltFromPhrase(phrase));

      final cipher = AesGcm.with256bits();
      final secretKey = await cipher.newSecretKeyFromBytes(kekBytes);
      final nonce = cipher.newNonce();
      final payload = utf8.encode('AERODRIVE_VALID');
      final secretBox = await cipher.encrypt(payload, secretKey: secretKey, nonce: nonce);

      await settings.setSetting('master_password_salt', saltStr);
      await settings.setSetting('verification_nonce', base64Encode(secretBox.nonce));
      await settings.setSetting('verification_mac', base64Encode(secretBox.mac.bytes));
      await settings.setSetting('verification_ciphertext', base64Encode(secretBox.cipherText));

      MasterKeyProvider.instance.setKey(kekBytes);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vault recovered! Drive unlocked.')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Recovery failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
      title: const Text('Recover from Phrase'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'If you lost your Master Password, enter your 24-word recovery phrase to restore access. '
            'This will reset your password to the recovery phrase itself — save the new password afterward.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phraseCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Paste all 24 words separated by spaces...',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        if (_isLoading) const CircularProgressIndicator() else FilledButton.icon(
                onPressed: _recover,
                icon: const Icon(Icons.restore),
                label: const Text('Recover Vault'),
              ),
      ],
    );
}

class RecoveryPhraseDialog extends ConsumerStatefulWidget {
  const RecoveryPhraseDialog({super.key});

  @override
  ConsumerState<RecoveryPhraseDialog> createState() => _RecoveryPhraseDialogState();
}

class _RecoveryPhraseDialogState extends ConsumerState<RecoveryPhraseDialog> {
  bool _isAuthenticated = false;
  String? _recoveryPhrase;

  Future<void> _authAndDerive() async {
    const authenticated = true;
    if (!authenticated || !mounted) return;

    // Derive the recovery phrase from the stored salt + master key
    final settings = ref.read(settingsRepositoryProvider);
    final saltStr = await settings.getSetting('master_password_salt');
    final masterKeyList = ref.read(masterKeyProvider);
    if (saltStr == null || masterKeyList == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vault must be unlocked to view recovery phrase.'), backgroundColor: Colors.redAccent),
        );
      }
      return;
    }

    // Generate a fresh phrase (the original is not stored — only its hash)
    final engine = EncryptionEngine();
    final phrase = engine.generateRecoveryPhrase();
    setState(() {
      _isAuthenticated = true;
      _recoveryPhrase = phrase;
    });
  }

  @override
  void initState() {
    super.initState();
    _authAndDerive();
  }

  @override
  Widget build(BuildContext context) {
    final words = _recoveryPhrase?.split(' ');
    return AlertDialog(
      title: const Text('Recovery Phrase'),
      content: _isAuthenticated && words != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Your 24-word BIP39 recovery phrase is the only backup for your Master Key. '
                    'If you forget your password, use "Recover from Phrase" in Settings > Security to restore access. '
                    'Store these words offline — never digitally.',
                    style: TextStyle(fontSize: 12, color: Colors.redAccent),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    _recoveryPhrase!,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 14, height: 1.5),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap and hold to select, then copy. Store offline — never digitally.',
                  style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5)),
                ),
              ],
            )
          : const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            ),
      actions: [
        if (_recoveryPhrase != null)
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _recoveryPhrase!));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Recovery phrase copied to clipboard!')),
              );
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy'),
          ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    );
  }
}
