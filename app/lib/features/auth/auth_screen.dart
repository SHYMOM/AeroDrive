import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/core/theme/app_colors.dart';
import 'package:aerodrive/core/widgets/aerodrive_logo.dart';
import 'package:aerodrive/features/telegram/telegram_service.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _submitPhone() {
    final phone = _phoneController.text.trim();
    if (phone.isNotEmpty) {
      ref.read(telegramServiceProvider.notifier).setAuthenticationPhoneNumber(phone);
    }
  }

  void _submitCode() {
    final code = _codeController.text.trim();
    if (code.isNotEmpty) {
      ref.read(telegramServiceProvider.notifier).checkAuthenticationCode(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tdState = ref.watch(telegramServiceProvider);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AeroDriveLogo(size: 80),
                const SizedBox(height: 32),
                Text(
                  'Welcome to AeroDrive',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Secure, unlimited cloud storage\npowered by your Telegram account.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white70,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                
                if (tdState == TelegramAuthState.initial)
                  const Center(child: CircularProgressIndicator())
                else if (tdState == TelegramAuthState.waitPhoneNumber)
                  _buildPhoneEntry()
                else if (tdState == TelegramAuthState.waitCode)
                  _buildCodeEntry()
                else if (tdState == TelegramAuthState.error)
                  const Text('Failed to initialize TDLib. Check your API credentials.', textAlign: TextAlign.center, style: TextStyle(color: Colors.redAccent))
                else
                  const Center(child: Text('Logging in...')),
                  
                const SizedBox(height: 32),
                Text(
                  'By logging in, you agree to our Terms of Service and Privacy Policy.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white54,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneEntry() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _phoneController,
          decoration: InputDecoration(
            labelText: 'Phone Number',
            hintText: '+1 234 567 8900',
            prefixIcon: const Icon(Icons.phone),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          keyboardType: TextInputType.phone,
          onSubmitted: (_) => _submitPhone(),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _submitPhone,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('Send Verification Code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildCodeEntry() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'A code was sent via Telegram to your other devices.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.primaryLight),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _codeController,
          decoration: InputDecoration(
            labelText: 'Verification Code',
            hintText: '12345',
            prefixIcon: const Icon(Icons.lock_outline),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          keyboardType: TextInputType.number,
          onSubmitted: (_) => _submitCode(),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _submitCode,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('Log In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () {
            ref.read(telegramServiceProvider.notifier).logOut(); // Go back to phone
          },
          child: const Text('Change phone number'),
        ),
      ],
    );
  }
}
