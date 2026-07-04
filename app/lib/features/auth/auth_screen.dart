import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/phone_validator.dart';
import '../../core/widgets/aerodrive_logo.dart';
import '../../core/widgets/otp_input.dart';
import '../../core/widgets/premium_button.dart';
import '../telegram/telegram_service.dart';

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

  late final AnimationController _bgPulseController;
  late final Animation<double> _bgPulseAnimation;

  bool _isSendingCode = false;
  bool _isVerifying = false;
  bool _isSubmittingPassword = false;
  bool _showPassword = false;
  bool _codeSent = false;
  final bool _isTelegramAuth = true; // Track if we're using Telegram auth (6-digit code)

  @override
  void initState() {
    super.initState();
    _bgPulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    _bgPulseAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _bgPulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    _bgPulseController.dispose();
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
            backgroundColor: Colors.redAccent,
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
        setState(() {
          _isSendingCode = false;
        });
        var errorMsg = 'Failed to send verification code';
        if (e is Map && e['message'] != null) {
          errorMsg = e['message'];
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.redAccent,
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
        if (e is Map && e['message'] != null) {
          errorMsg = e['message'];
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isVerifying = false);
      }
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
        if (e is Map && e['message'] != null) {
          errorMsg = e['message'];
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmittingPassword = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tdState = ref.watch(telegramServiceProvider);
    final service = ref.read(telegramServiceProvider.notifier);

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.3),
            radius: 1.8,
            colors: [
              const Color(0xFF7C3AED).withValues(alpha: 0.3), // neonViolet glow
              const Color(0xFF00E5FF).withValues(alpha: 0.1), // neonCyan glow
              const Color(0xFF0D0E23), // deepSpace
              const Color(0xFF0D0E23), // deepSpace
            ],
          ),
        ),
        child: AnimatedBuilder(
          animation: _bgPulseAnimation,
          builder: (context, child) => DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.2,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.08 * _bgPulseAnimation.value),
                    Colors.transparent,
                  ],
                ),
              ),
              child: child,
            ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildLogo(),
                      const SizedBox(height: 36),
                      _buildAuthSection(tdState, service),
                      const SizedBox(height: 40),
                      _buildFooter(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() => Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary.withValues(alpha: 0.1),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.2),
                blurRadius: 20,
                spreadRadius: 2,
              )
            ],
          ),
          child: const AeroDriveLogo(),
        ),
        const SizedBox(height: 24),
        Text(
          'AeroDrive',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Colors.white.withValues(alpha: 0.95),
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Zero-Knowledge. Encrypted. Decentralized.',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.secondary.withValues(alpha: 0.9),
            letterSpacing: 2,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ).animate().fadeIn(duration: 600.ms).slideY(begin: -20, end: 0);

  Widget _buildAuthSection(TelegramAuthState tdState, TelegramService service) => AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
      child: _buildCurrentView(tdState, service),
    );

  Widget _buildCurrentView(TelegramAuthState tdState, TelegramService service) {
    switch (tdState) {
      case TelegramAuthState.initial:
        return _buildInitializing();
      case TelegramAuthState.waitPhoneNumber:
        return _buildPhoneEntry();
      case TelegramAuthState.waitCode:
        return _buildCodeEntry();
      case TelegramAuthState.waitPassword:
        return _buildPasswordEntry(service);
      case TelegramAuthState.error:
        return _buildErrorView();
      default:
        return _buildProcessing();
    }
  }

  Widget _buildInitializing() => _buildGlassCard(
      child: Column(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(
                AppColors.primary.withValues(alpha: 0.8),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Establishing secure connection...',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 14,
            ),
          ),
        ],
      ),
    ).animate().fadeIn().shimmer(
      duration: 1200.ms,
      color: AppColors.primary.withValues(alpha: 0.05),
    );

  Widget _buildPhoneEntry() => Column(
      key: const ValueKey('phone'),
      children: [
        _buildGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: AppColors.primary.withValues(alpha: 0.15),
                        ),
                        child: const Icon(Icons.phone_android, color: AppColors.primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Sign in to AeroDrive',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
              const SizedBox(height: 20),
              Text(
                'Enter your phone number starting with your country code (e.g. +1 234 567 8900).',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
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
              _buildSendCodeButton(),
            ],
          ),
        ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0),
      ],
    );

  Widget _buildSendCodeButton() {
    if (_isSendingCode) {
      return _buildNaughtySendingAnimation();
    }
    if (_codeSent) {
      return _buildCodeSentAnimation();
    }
    return PremiumButton(
      label: 'Send Verification Code',
      icon: Icons.send,
      onPressed: _submitPhone,
      gradient: const [AppColors.primary, AppColors.secondary],
    );
  }

  Widget _buildNaughtySendingAnimation() => _buildGlassCard(
      child: _NaughtySendingAnimation(),
    );

  Widget _buildCodeSentAnimation() => Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF4CAF50).withValues(alpha: 0.15),
            const Color(0xFF2196F3).withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(
          color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, color: const Color(0xFF4CAF50).withValues(alpha: 0.9), size: 22),
          const SizedBox(width: 10),
          Text(
            'Code sent successfully!',
            style: TextStyle(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.9),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ).animate().scale(duration: 300.ms).then().shake(duration: 400.ms);

  Widget _buildCodeEntry() => Column(
      key: const ValueKey('code'),
      children: [
        _buildGlassCard(
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: const LinearGradient(
                        colors: [AppColors.secondary, AppColors.primary],
                      ),
                    ),
                    child: const Icon(Icons.pin, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Verification Code',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Enter the code sent to your Telegram devices.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 24),
              OtpInput(
                length: _isTelegramAuth ? 5 : 6, // Telegram provides 5 digits
                onCompleted: _submitCode,
                activeColor: AppColors.secondary,
              ),
              const SizedBox(height: 24),
              PremiumButton(
                label: 'Verifying...',
                isLoading: _isVerifying,
                gradient: const [AppColors.secondary, AppColors.primary],
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => _service.logOut(),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white.withValues(alpha: 0.5),
                ),
                child: const Text('Change phone number'),
              ),
            ],
          ),
        ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0),
      ],
    );

  Widget _buildPasswordEntry(TelegramService service) {
    final hint = service.passwordHint;
    return Column(
      key: const ValueKey('password'),
      children: [
        _buildGlassCard(
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.secondary],
                      ),
                    ),
                    child: const Icon(Icons.lock, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '2-Step Verification',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'This account has 2-step verification enabled.${hint != null && hint.isNotEmpty ? '\nHint: $hint' : ''}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              if (service.hasRecoveryEmail) ...[
                const SizedBox(height: 6),
                Text(
                  'Recovery email is set.',
                  style: TextStyle(
                    color: AppColors.primary.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
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
                    color: Colors.white.withValues(alpha: 0.4),
                    size: 20,
                  ),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
              const SizedBox(height: 20),
              PremiumButton(
                label: _isSubmittingPassword ? 'Verifying...' : 'Unlock',
                isLoading: _isSubmittingPassword,
                onPressed: _submitPassword,
                gradient: const [AppColors.primary, AppColors.secondary],
                icon: _isSubmittingPassword ? null : Icons.vpn_key,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => _service.logOut(),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white.withValues(alpha: 0.5),
                ),
                child: const Text('Try another number'),
              ),
            ],
          ),
        ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0),
      ],
    );
  }

  Widget _buildProcessing() => _buildGlassCard(
      child: Column(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(
                AppColors.primary.withValues(alpha: 0.8),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Processing...',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );

  Widget _buildErrorView() => _buildGlassCard(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.redAccent.withValues(alpha: 0.15),
            ),
            child: const Icon(Icons.error_outline, color: Colors.redAccent, size: 32),
          ),
          const SizedBox(height: 16),
          const Text(
            'Connection Error',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Failed to initialize. Check your API credentials.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );

  Widget _buildFooter() => Text(
      'By logging in, you agree to our Terms of Service and Privacy Policy.',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.3),
        fontSize: 11,
        height: 1.4,
      ),
    ).animate().fadeIn(delay: 800.ms, duration: 500.ms);

  Widget _buildGlassCard({required Widget child}) => RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: AppColors.glassBgDark,
              border: Border.all(
                color: AppColors.glassBorder,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );

}

class _NaughtySendingAnimation extends StatefulWidget {
  @override
  State<_NaughtySendingAnimation> createState() => _NaughtySendingAnimationState();
}

class _NaughtySendingAnimationState extends State<_NaughtySendingAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _bounceAnimation;
  late final Animation<double> _floatAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _bounceAnimation = Tween<double>(begin: 1, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _floatAnimation = Tween<double>(begin: 0, end: -8).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.translate(
          offset: Offset(0, _floatAnimation.value),
          child: Transform.scale(
            scale: _bounceAnimation.value,
            child: child,
          ),
        ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildDot(0),
          const SizedBox(width: 8),
          Icon(
            Icons.send_rounded,
            color: AppColors.primary.withValues(alpha: 0.9),
            size: 24,
          ),
          const SizedBox(width: 8),
          _buildDot(1),
          const SizedBox(width: 8),
          Text(
            'Sending...',
            style: TextStyle(
              color: AppColors.primary.withValues(alpha: 0.7),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          _buildDot(2),
        ],
      ),
    );

  Widget _buildDot(int index) => AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final delay = (index * 0.15);
        final t = (_controller.value + delay) % 1.0;
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary.withValues(
              alpha: 0.3 + (t * 0.7),
            ),
          ),
        );
      },
    );
}


