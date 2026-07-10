import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/phone_validator.dart';
import '../../core/widgets/aerodrive_logo.dart';
import '../../core/widgets/otp_input.dart';
import '../../core/widgets/premium_button.dart';
import '../telegram/telegram_service.dart';
import '../../widgets/sync_debug_overlay.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen>
    with SingleTickerProviderStateMixin {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();

  late final AnimationController _fadeController;

  bool _isSendingCode = false;
  bool _isVerifying = false;
  bool _isSubmittingPassword = false;
  bool _showPassword = false;
  bool _codeSent = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  TelegramService get _service => ref.read(telegramServiceProvider.notifier);

  Future<void> _submitPhone() async {
    final rawPhone = _phoneController.text.trim();
    final validation = PhoneValidator.validate(rawPhone);
    if (!validation.isValid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(validation.errorMessage ?? 'Invalid phone number.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    final phone = validation.formattedNumber!;
    if (!mounted) return;
    setState(() => _isSendingCode = true);

    try {
      await _service.setAuthenticationPhoneNumber(phone);
      if (mounted) {
        setState(() {
          _isSendingCode = false;
          _codeSent = true;
        });
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _codeSent = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSendingCode = false);
        var errorMsg = 'Failed to send verification code';
        if (e is Map && e['message'] != null) {
          errorMsg = e['message'];
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _submitCode(String code) async {
    if (!mounted) return;
    setState(() => _isVerifying = true);
    try {
      await _service.checkAuthenticationCode(code);
    } catch (e) {
      if (mounted) {
        var errorMsg = 'Invalid verification code';
        if (e is Map && e['message'] != null) errorMsg = e['message'];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _submitPassword() async {
    final pass = _passwordController.text.trim();
    if (pass.isEmpty) return;
    if (!mounted) return;
    setState(() => _isSubmittingPassword = true);
    try {
      await _service.checkAuthenticationPassword(pass);
    } catch (e) {
      if (mounted) {
        var errorMsg = 'Incorrect password';
        if (e is Map && e['message'] != null) errorMsg = e['message'];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmittingPassword = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<TelegramAuthState>(telegramServiceProvider, (previous, next) {
      if (next == TelegramAuthState.ready) {
        context.go('/drive');
      }
    });

    final tdState = ref.watch(telegramServiceProvider);
    final service = ref.read(telegramServiceProvider.notifier);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo section
                      _buildLogo(cs),
                      const SizedBox(height: 40),
                      // Auth form
                      _buildAuthSection(tdState, service, cs),
                      const SizedBox(height: 32),
                      // Footer
                      _buildFooter(cs),
                    ],
                  ),
                ),
              ),
            ),
            if (tdState == TelegramAuthState.initial || tdState == TelegramAuthState.error)
              const Align(
                alignment: Alignment.topCenter,
                child: SyncDebugOverlay(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo(ColorScheme cs) => Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cs.primary.withValues(alpha: 0.1),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withValues(alpha: 0.15),
                blurRadius: 24,
                spreadRadius: 2,
              )
            ],
          ),
          child: const AeroDriveLogo(),
        ),
        const SizedBox(height: 20),
        Text(
          'AeroDrive',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Zero-Knowledge. Encrypted. Decentralized.',
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurfaceVariant,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ).animate().fadeIn(duration: 600.ms).slideY(begin: -16, end: 0, curve: Curves.easeOut);

  Widget _buildAuthSection(TelegramAuthState tdState, TelegramService service, ColorScheme cs) =>
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: _buildCurrentView(tdState, service, cs),
      );

  Widget _buildCurrentView(TelegramAuthState tdState, TelegramService service, ColorScheme cs) {
    switch (tdState) {
      case TelegramAuthState.initial:
        return _buildInitializing(cs);
      case TelegramAuthState.waitPhoneNumber:
        return _buildPhoneEntry(cs);
      case TelegramAuthState.waitCode:
        return _buildCodeEntry(cs);
      case TelegramAuthState.waitPassword:
        return _buildPasswordEntry(service, cs);
      case TelegramAuthState.error:
        return _buildErrorView(cs);
      default:
        return _buildProcessing(cs);
    }
  }

  Widget _buildCard({required Widget child, ColorScheme? cs}) => Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: (cs ?? Theme.of(context).colorScheme).surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border.all(
          color: (cs ?? Theme.of(context).colorScheme).outlineVariant,
        ),
      ),
      child: child,
    );

  Widget _buildInitializing(ColorScheme cs) => _buildCard(
      cs: cs,
      child: Column(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Connecting...',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
        ],
      ),
    ).animate().fadeIn();

  Widget _buildPhoneEntry(ColorScheme cs) => Column(
      key: const ValueKey('phone'),
      children: [
        _buildCard(
          cs: cs,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: cs.primary.withValues(alpha: 0.12),
                    ),
                    child: Icon(Icons.phone_android, color: cs.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Sign in to AeroDrive',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Enter your phone number starting with your country code.',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              PremiumTextField(
                controller: _phoneController,
                label: 'Phone Number',
                hint: '+1 234 567 8900',
                keyboardType: TextInputType.phone,
                enabled: !_isSendingCode,
                prefixIcon: Icons.phone_outlined,
              ),
              const SizedBox(height: 20),
              _buildSendCodeButton(cs),
            ],
          ),
        ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.04, end: 0),
      ],
    );

  Widget _buildSendCodeButton(ColorScheme cs) {
    if (_isSendingCode) {
      return _buildCard(
        cs: cs,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Text('Sending...', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
          ],
        ),
      );
    }
    if (_codeSent) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: cs.primary.withValues(alpha: 0.1),
          border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: cs.primary, size: 20),
            const SizedBox(width: 8),
            Text('Code sent! Check your Telegram.', style: TextStyle(color: cs.primary, fontSize: 13)),
          ],
        ),
      );
    }
    return FilledButton(
      onPressed: _submitPhone,
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: const Text('Send Verification Code'),
    );
  }

  Widget _buildCodeEntry(ColorScheme cs) => Column(
      key: const ValueKey('code'),
      children: [
        _buildCard(
          cs: cs,
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: cs.primary.withValues(alpha: 0.12),
                    ),
                    child: Icon(Icons.pin, color: cs.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Verification Code',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Enter the code sent to your Telegram devices.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 24),
              OtpInput(
                length: 5,
                onCompleted: _submitCode,
                activeColor: cs.primary,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: _isVerifying
                        ? null
                        : () async {
                            await _service.resetAuthFlow();
                          },
                    icon: const Icon(Icons.arrow_back, size: 16),
                    label: const Text('Change Number'),
                  ),
                  TextButton.icon(
                    onPressed: _isVerifying
                        ? null
                        : () async {
                            final rawPhone = _phoneController.text.trim();
                            final validation = PhoneValidator.validate(rawPhone);
                            if (validation.isValid) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Resending verification code...')),
                              );
                              try {
                                await _service.setAuthenticationPhoneNumber(validation.formattedNumber!);
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Failed to resend code: $e'),
                                      backgroundColor: Theme.of(context).colorScheme.error,
                                    ),
                                  );
                                }
                              }
                            }
                          },
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Resend Code'),
                  ),
                ],
              ),
              if (_isVerifying) ...[
                const SizedBox(height: 16),
                const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],
            ],
          ),
        ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.04, end: 0),
      ],
    );

  Widget _buildPasswordEntry(TelegramService service, ColorScheme cs) {
    final hint = service.passwordHint;
    return Column(
      key: const ValueKey('password'),
      children: [
        _buildCard(
          cs: cs,
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: cs.primary.withValues(alpha: 0.12),
                    ),
                    child: Icon(Icons.lock, color: cs.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '2-Step Verification',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'This account has 2-step verification enabled.${hint != null && hint.isNotEmpty ? '\nHint: $hint' : ''}',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.4),
              ),
              if (service.hasRecoveryEmail) ...[
                const SizedBox(height: 6),
                Text('Recovery email is set.', style: TextStyle(color: cs.primary, fontSize: 12)),
              ],
              const SizedBox(height: 20),
              PremiumTextField(
                controller: _passwordController,
                label: 'Password',
                obscureText: !_showPassword,
                enabled: !_isSubmittingPassword,
                prefixIcon: Icons.lock_outline,
                suffixIcon: IconButton(
                  icon: Icon(
                    _showPassword ? Icons.visibility : Icons.visibility_off,
                    color: cs.onSurfaceVariant,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _isSubmittingPassword ? null : _submitPassword,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSubmittingPassword
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Unlock'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => _service.logOut(),
                child: Text('Try another number', style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            ],
          ),
        ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.04, end: 0),
      ],
    );
  }

  Widget _buildProcessing(ColorScheme cs) => _buildCard(
      cs: cs,
      child: Column(
        children: [
          SizedBox(
            width: 40, height: 40,
            child: CircularProgressIndicator(strokeWidth: 3, color: cs.primary),
          ),
          const SizedBox(height: 16),
          Text('Processing...', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
        ],
      ),
    );

  Widget _buildErrorView(ColorScheme cs) => _buildCard(
      cs: cs,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.error.withValues(alpha: 0.12),
            ),
            child: Icon(Icons.error_outline, color: cs.error, size: 28),
          ),
          const SizedBox(height: 16),
          Text('Connection Error', style: TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            'Failed to initialize. Check your API credentials.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );

  Widget _buildFooter(ColorScheme cs) => Text(
      'By logging in, you agree to our Terms of Service and Privacy Policy.',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
        fontSize: 11,
        height: 1.4,
      ),
    ).animate().fadeIn(delay: 600.ms, duration: 400.ms);
}
