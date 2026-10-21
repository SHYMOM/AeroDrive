import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

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
  final _apiIdController = TextEditingController();
  final _apiHashController = TextEditingController();

  late final AnimationController _fadeController;

  bool _isSendingCode = false;
  bool _isVerifying = false;
  bool _isSubmittingPassword = false;
  bool _showPassword = false;
  bool _codeSent = false;
  bool _isSavingCredentials = false;
  String? _credentialsError;

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
    _apiIdController.dispose();
    _apiHashController.dispose();
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

  Future<void> _submitApiCredentials(TelegramService service) async {
    final rawId = _apiIdController.text.trim();
    final hash = _apiHashController.text.trim();

    if (rawId.isEmpty || hash.isEmpty) {
      setState(() => _credentialsError = 'Both API ID and API Hash are required.');
      return;
    }

    final apiId = int.tryParse(rawId);
    if (apiId == null || apiId <= 0) {
      setState(() => _credentialsError = 'API ID must be a valid positive number.');
      return;
    }

    if (hash.length < 16) {
      setState(() => _credentialsError = 'API Hash must be a valid 32-character string.');
      return;
    }

    setState(() {
      _isSavingCredentials = true;
      _credentialsError = null;
    });

    try {
      await service.setApiCredentials(apiId, hash);
    } catch (e) {
      if (mounted) {
        setState(() {
          _credentialsError = 'Failed to initialize with provided credentials: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingCredentials = false);
      }
    }
  }

  Future<void> _pasteToController(TextEditingController controller) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      setState(() {
        controller.text = data.text!.trim();
        _credentialsError = null;
      });
    }
  }

  Future<void> _openTelegramDevPortal() async {
    final uri = Uri.parse('https://my.telegram.org');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error launching my.telegram.org: $e');
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
      case TelegramAuthState.waitApiCredentials:
        return _buildApiCredentialsEntry(service, cs);
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

  Widget _buildApiCredentialsEntry(TelegramService service, ColorScheme cs) => Column(
      key: const ValueKey('api_credentials'),
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
                    child: Icon(Icons.key_rounded, color: cs.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Telegram API Setup',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Direct TDLib Client Configuration',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'AeroDrive connects directly to Telegram servers. Enter your personal Telegram API credentials to get started.',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),

              // Instructions Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: cs.primary.withValues(alpha: 0.06),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.help_outline_rounded, size: 16, color: cs.primary),
                        const SizedBox(width: 6),
                        Text(
                          'How to get your free API credentials:',
                          style: TextStyle(
                            color: cs.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildStepRow(
                      number: '1',
                      text: 'Log in with your phone number at my.telegram.org',
                      cs: cs,
                    ),
                    const SizedBox(height: 6),
                    _buildStepRow(
                      number: '2',
                      text: 'Click on "API development tools"',
                      cs: cs,
                    ),
                    const SizedBox(height: 6),
                    _buildStepRow(
                      number: '3',
                      text: 'Create an app (e.g. App title: AeroDrive)',
                      cs: cs,
                    ),
                    const SizedBox(height: 6),
                    _buildStepRow(
                      number: '4',
                      text: 'Copy your App api_id and App api_hash below',
                      cs: cs,
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: _openTelegramDevPortal,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Open my.telegram.org',
                              style: TextStyle(
                                color: cs.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.open_in_new_rounded, size: 14, color: cs.primary),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // API ID Field
              PremiumTextField(
                controller: _apiIdController,
                label: 'API ID (api_id)',
                hint: 'e.g. 12345678',
                keyboardType: TextInputType.number,
                enabled: !_isSavingCredentials,
                prefixIcon: Icons.tag_rounded,
                suffixIcon: IconButton(
                  tooltip: 'Paste from clipboard',
                  icon: Icon(Icons.content_paste_rounded, size: 18, color: cs.onSurfaceVariant),
                  onPressed: _isSavingCredentials ? null : () => _pasteToController(_apiIdController),
                ),
              ),
              const SizedBox(height: 14),

              // API HASH Field
              PremiumTextField(
                controller: _apiHashController,
                label: 'API Hash (api_hash)',
                hint: 'e.g. 0123456789abcdef0123456789abcdef',
                keyboardType: TextInputType.text,
                enabled: !_isSavingCredentials,
                prefixIcon: Icons.key_rounded,
                suffixIcon: IconButton(
                  tooltip: 'Paste from clipboard',
                  icon: Icon(Icons.content_paste_rounded, size: 18, color: cs.onSurfaceVariant),
                  onPressed: _isSavingCredentials ? null : () => _pasteToController(_apiHashController),
                ),
              ),

              if (_credentialsError != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: cs.error.withValues(alpha: 0.12),
                    border: Border.all(color: cs.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded, size: 16, color: cs.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _credentialsError!,
                          style: TextStyle(color: cs.error, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              FilledButton(
                onPressed: _isSavingCredentials ? null : () => _submitApiCredentials(service),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSavingCredentials
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save & Continue'),
              ),

              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shield_outlined, size: 13, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Credentials are saved locally on your device only.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.04, end: 0),
      ],
    );

  Widget _buildStepRow({required String number, required String text, required ColorScheme cs}) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: cs.primary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant,
              height: 1.3,
            ),
          ),
        ),
      ],
    );

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
