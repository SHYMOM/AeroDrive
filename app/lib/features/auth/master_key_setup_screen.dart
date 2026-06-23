import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zxcvbnm/zxcvbnm.dart';
import 'package:zxcvbnm/languages/en.dart' as en;
import 'package:aerodrive/core/theme/app_colors.dart';
import 'package:aerodrive/data/crypto/encryption_engine.dart';
import 'package:aerodrive/features/auth/recovery_phrase_screen.dart';

class MasterKeySetupScreen extends ConsumerStatefulWidget {
  const MasterKeySetupScreen({super.key});

  @override
  ConsumerState<MasterKeySetupScreen> createState() => _MasterKeySetupScreenState();
}

class _MasterKeySetupScreenState extends ConsumerState<MasterKeySetupScreen> {
  final _passwordController = TextEditingController();
  final _zxcvbn = Zxcvbnm(dictionaries: {...en.dictionaries});
  
  double _strengthScore = 0;
  String _feedbackText = 'Enter a strong password';
  bool _isObscured = true;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_onPasswordChanged);
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _onPasswordChanged() {
    final pass = _passwordController.text;
    if (pass.isEmpty) {
      setState(() {
        _strengthScore = 0;
        _feedbackText = 'Enter a strong password';
      });
      return;
    }

    final result = _zxcvbn(pass);
    setState(() {
      _strengthScore = result.score / 4.0; // Score is 0-4
      if (pass.length < 12) {
        _feedbackText = 'Too short! Minimum 12 characters required.';
        _strengthScore = 0; // Force zero visually if under limit
      } else {
        _feedbackText = result.feedback.warning?.isNotEmpty == true 
          ? result.feedback.warning! 
          : 'Great password!';
      }
    });
  }

  Color _getStrengthColor() {
    if (_strengthScore == 0) return Colors.red;
    if (_strengthScore <= 0.25) return Colors.orange;
    if (_strengthScore <= 0.5) return Colors.yellow;
    if (_strengthScore <= 0.75) return Colors.lightGreen;
    return Colors.green;
  }

  void _showNuclearWarning() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 12),
            Text('Nuclear Warning'),
          ],
        ),
        content: const Text(
          'Because AeroDrive is zero-knowledge, we absolutely cannot reset your password. '
          'If you forget it, you will permanently lose access to your entire Vault and all files mathematically.\n\n'
          'Are you sure you want to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Go Back'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(context);
              _proceedToRecoveryPhrase();
            },
            child: const Text('I Understand, Proceed'),
          ),
        ],
      ),
    );
  }

  void _proceedToRecoveryPhrase() {
    final engine = EncryptionEngine();
    final phrase = engine.generateRecoveryPhrase();
    
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RecoveryPhraseScreen(recoveryPhrase: phrase, password: _passwordController.text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Master Key Setup')),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.shield, size: 64, color: AppColors.primary),
              const SizedBox(height: 24),
              Text(
                'Secure Your Vault',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'AeroDrive uses end-to-end encryption. Your Master Key secures everything.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              
              TextField(
                controller: _passwordController,
                obscureText: _isObscured,
                maxLength: 128,
                decoration: InputDecoration(
                  labelText: 'Master Password (min 12 chars)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  suffixIcon: IconButton(
                    icon: Icon(_isObscured ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _isObscured = !_isObscured),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              
              // Strength Indicator
              LinearProgressIndicator(
                value: _strengthScore,
                backgroundColor: Colors.white24,
                color: _getStrengthColor(),
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 8),
              Text(
                _feedbackText,
                style: TextStyle(color: _getStrengthColor(), fontSize: 12),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 32),
              FilledButton(
                onPressed: (_passwordController.text.length >= 12) ? _showNuclearWarning : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Set Master Key', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
