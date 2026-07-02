import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:aerodrive/core/theme/app_colors.dart';
import 'package:aerodrive/core/widgets/otp_input.dart';
import 'package:aerodrive/core/widgets/premium_button.dart';
import 'package:aerodrive/features/telegram/telegram_manager.dart';
import 'package:aerodrive/features/telegram/telegram_service.dart';
import 'package:aerodrive/core/utils/phone_validator.dart';

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  bool _hasPendingAccount(List<TelegramService> accounts) {
    return accounts.any((c) => c.authState != TelegramAuthState.ready);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(telegramManagerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Telegram Accounts'),
        scrolledUnderElevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D0D0D), Color(0xFF000000)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Manage multiple Telegram accounts. Bind channels to specific accounts for bandwidth pooling.',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
            ),
            const SizedBox(height: 24),
            ...accounts.map((client) {
              return TelegramAccountCard(
                key: ValueKey(client.accountId),
                client: client,
              );
            }),
            if (!_hasPendingAccount(accounts))
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: PremiumButton(
                  label: 'Add Another Account',
                  icon: Icons.add,
                  onPressed: () {
                    final newId = 'account_${DateTime.now().millisecondsSinceEpoch}';
                    ref.read(telegramManagerProvider.notifier).addClient(newId, isHeadless: true);
                  },
                  gradient: const [Color(0xFFBB86FC), Color(0xFF7C4DFF)],
                ),
              ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0),
          ],
        ),
      ),
    );
  }
}

class TelegramAccountCard extends ConsumerStatefulWidget {
  final TelegramService client;
  const TelegramAccountCard({super.key, required this.client});

  @override
  ConsumerState<TelegramAccountCard> createState() => _TelegramAccountCardState();
}

class _TelegramAccountCardState extends ConsumerState<TelegramAccountCard> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSendingCode = false;
  bool _isVerifyingCode = false;
  bool _isSubmittingPassword = false;
  bool _showPassword = false;
  bool _isDeleting = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final rawPhone = _phoneController.text.trim();
    final validation = PhoneValidator.validate(rawPhone);
    if (!validation.isValid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(validation.errorMessage ?? 'Invalid phone number.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    final phone = validation.formattedNumber!;
    setState(() => _isSendingCode = true);
    try {
      await widget.client.setAuthenticationPhoneNumber(phone);
      await Future.delayed(const Duration(seconds: 1));
    } catch (e) {
      if (mounted) {
        String errorMsg = 'Error sending code';
        if (e is Map && e['message'] != null) {
          errorMsg = e['message'];
        } else {
          errorMsg = e.toString();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingCode = false);
    }
  }

  Future<void> _verifyCode(String code) async {
    setState(() => _isVerifyingCode = true);
    try {
      await widget.client.checkAuthenticationCode(code);
    } catch (e) {
      if (mounted) {
        String errorMsg = 'Invalid verification code';
        if (e is Map && e['message'] != null) {
          errorMsg = e['message'];
        } else {
          errorMsg = e.toString();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isVerifyingCode = false);
    }
  }

  Future<void> _submitPassword() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) return;
    setState(() => _isSubmittingPassword = true);
    try {
      await widget.client.checkAuthenticationPassword(password);
      await Future.delayed(const Duration(seconds: 1));
    } catch (e) {
      if (mounted) {
        String errorMsg = 'Password verification failed';
        if (e is Map && e['message'] != null) {
          errorMsg = e['message'];
        } else {
          errorMsg = e.toString();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmittingPassword = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Remove Telegram Account', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete and log out of the account "${widget.client.displayName}"?\n\n'
          'This will revoke its session and delete all local database files for this account.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete & Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isDeleting = true);
      try {
        await ref.read(telegramManagerProvider.notifier).removeClient(widget.client.accountId);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete account: $e'), backgroundColor: AppColors.error),
          );
        }
      } finally {
        if (mounted) setState(() => _isDeleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = widget.client.authState;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: _buildViewForState(authState),
    );
  }

  Widget _buildViewForState(TelegramAuthState authState) {
    switch (authState) {
      case TelegramAuthState.ready:
        return _buildConnectedView();
      case TelegramAuthState.waitPhoneNumber:
        return _buildPhoneInput();
      case TelegramAuthState.waitCode:
        return _buildCodeInput();
      case TelegramAuthState.waitPassword:
        return _buildPasswordInput();
      case TelegramAuthState.initial:
        return _buildLoadingView('Initializing TDLib client...');
      case TelegramAuthState.loggingOut:
        return _buildLoadingView('Logging out...');
      case TelegramAuthState.closed:
        return _buildLoadingView('Connection closed...');
      case TelegramAuthState.error:
        return _buildErrorView();
    }
  }

  Widget _buildConnectedView() {
    final client = widget.client;
    final photoPath = client.photoPath;

    Widget avatar;
    if (photoPath != null && File(photoPath).existsSync()) {
      avatar = CircleAvatar(
        radius: 28,
        backgroundImage: FileImage(File(photoPath)),
      );
    } else {
      final initials = client.displayName.isNotEmpty
          ? client.displayName.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join().toUpperCase()
          : '';
      avatar = CircleAvatar(
        radius: 28,
        backgroundColor: const Color(0xFFBB86FC).withOpacity(0.2),
        child: initials.isNotEmpty
            ? Text(initials, style: const TextStyle(color: Color(0xFFBB86FC), fontWeight: FontWeight.bold, fontSize: 18))
            : const Icon(Icons.person, size: 28, color: Color(0xFFBB86FC)),
      );
    }

    return _buildCard(
      borderColor: client.accountId == 'primary' ? const Color(0xFFBB86FC) : Colors.white12,
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        client.displayName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                      ),
                    ),
                    if (client.accountId == 'primary')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFBB86FC), Color(0xFF7C4DFF)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Primary',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  client.phoneNumber ?? 'Ready',
                  style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.5)),
                ),
                if (client.username != null && client.username!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '@${client.username}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFFBB86FC)),
                  ),
                ],
              ],
            ),
          ),
          if (client.accountId != 'primary')
            _isDeleting
                ? const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    onPressed: _confirmDelete,
                  ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).shimmer(duration: 1000.ms, color: Colors.green.withOpacity(0.08));
  }

  Widget _buildPhoneInput() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFBB86FC), Color(0xFF7C4DFF)],
                  ),
                ),
                child: const Icon(Icons.login, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Text(
                'Add Telegram Account',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Enter your Telegram phone number with country code (e.g. +1234567890).',
            style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.5)),
          ),
          const SizedBox(height: 16),
          PremiumTextField(
            controller: _phoneController,
            label: 'Phone Number',
            hint: '+1 234 567 8900',
            keyboardType: TextInputType.phone,
            enabled: !_isSendingCode,
            prefixIcon: Icons.phone_outlined,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => ref.read(telegramManagerProvider.notifier).removeClient(widget.client.accountId),
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 44,
                child: PremiumButton(
                  label: _isSendingCode ? 'Sending...' : 'Send Verification Code',
                  isLoading: _isSendingCode,
                  onPressed: _isSendingCode ? null : _sendCode,
                  fullWidth: false,
                  gradient: const [Color(0xFFBB86FC), Color(0xFF7C4DFF)],
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildCodeInput() {
    return _buildCard(
      borderColor: const Color(0xFF03DAC6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF03DAC6), Color(0xFF00BCD4)],
                  ),
                ),
                child: const Icon(Icons.security, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Text(
                'Verification Code',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'A verification code has been sent to ${_phoneController.text.isNotEmpty ? _phoneController.text : "your phone number"}.',
            style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.5)),
          ),
          const SizedBox(height: 20),
          Center(
            child: OtpInput(
              length: 5,
              onCompleted: _verifyCode,
              activeColor: const Color(0xFF03DAC6),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => ref.read(telegramManagerProvider.notifier).removeClient(widget.client.accountId),
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 44,
                child: PremiumButton(
                  label: _isVerifyingCode ? 'Verifying...' : 'Verify & Login',
                  isLoading: _isVerifyingCode,
                  fullWidth: false,
                  gradient: const [Color(0xFF03DAC6), Color(0xFF00BCD4)],
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildPasswordInput() {
    final hint = widget.client.passwordHint;
    return _buildCard(
      borderColor: Colors.amber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF9800), Color(0xFFF44336)],
                  ),
                ),
                child: const Icon(Icons.password, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Text(
                '2-Step Verification',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'This account has 2-step verification enabled.${hint != null && hint.isNotEmpty ? '\nHint: $hint' : ''}',
            style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.5), height: 1.4),
          ),
          const SizedBox(height: 16),
          PremiumTextField(
            controller: _passwordController,
            label: 'Password',
            obscureText: !_showPassword,
            enabled: !_isSubmittingPassword,
            prefixIcon: Icons.lock_outline,
            suffixIcon: IconButton(
              icon: Icon(
                _showPassword ? Icons.visibility : Icons.visibility_off,
                color: Colors.white.withOpacity(0.4),
                size: 20,
              ),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => ref.read(telegramManagerProvider.notifier).removeClient(widget.client.accountId),
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 44,
                child: PremiumButton(
                  label: _isSubmittingPassword ? 'Verifying...' : 'Submit Password',
                  isLoading: _isSubmittingPassword,
                  onPressed: _isSubmittingPassword ? null : _submitPassword,
                  fullWidth: false,
                  gradient: const [Color(0xFFFF9800), Color(0xFFF44336)],
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildLoadingView(String message) {
    return _buildCard(
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                const Color(0xFFBB86FC).withOpacity(0.8),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return _buildCard(
      borderColor: Colors.redAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent),
              const SizedBox(width: 8),
              Text(
                'Connection Error',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'An error occurred while connecting to TDLib. Please verify API configuration.',
            style: TextStyle(color: Colors.white.withOpacity(0.5)),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton(
                onPressed: () => ref.read(telegramManagerProvider.notifier).removeClient(widget.client.accountId),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent.withOpacity(0.2),
                  foregroundColor: Colors.redAccent,
                ),
                child: const Text('Remove & Retry'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required Widget child, Color? borderColor}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withOpacity(0.04),
        border: Border.all(
          color: borderColor ?? Colors.white.withOpacity(0.06),
          width: 1,
        ),
      ),
      child: child,
    );
  }
}
