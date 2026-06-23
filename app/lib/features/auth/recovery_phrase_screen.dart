import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:aerodrive/core/theme/app_colors.dart';
// Note: Normally, this would proceed to derive the MK and save it securely via riverpod or a setup service.

class RecoveryPhraseScreen extends StatelessWidget {
  final String recoveryPhrase;
  final String password;

  const RecoveryPhraseScreen({
    super.key,
    required this.recoveryPhrase,
    required this.password,
  });

  @override
  Widget build(BuildContext context) {
    final words = recoveryPhrase.split(' ');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recovery Phrase'),
        automaticallyImplyLeading: false, // Force them to deal with it
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
              
              // Grid of 24 words
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
                      onPressed: () {
                        // TODO: Implement actual MK derivation and secure storage
                        // This would call `EncryptionEngine.deriveMasterKey` and save to KeyStore.
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Setup Complete!')),
                        );
                        // Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DriveScreen()));
                      },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: AppColors.primary,
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
}
