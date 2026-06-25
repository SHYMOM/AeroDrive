import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:aerodrive/core/theme/app_colors.dart';
import 'package:aerodrive/features/telegram/telegram_manager.dart';
import 'package:aerodrive/features/telegram/telegram_service.dart';

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
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Manage multiple Telegram accounts. Bind channels to specific accounts for bandwidth pooling.',
            style: TextStyle(color: Colors.white70),
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
              padding: const EdgeInsets.only(top: 24),
              child: FilledButton.icon(
                onPressed: () {
                  final newId = 'account_${DateTime.now().millisecondsSinceEpoch}';
                  ref.read(telegramManagerProvider.notifier).addClient(newId, isHeadless: true);
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Another Account'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
        ],
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
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSendingCode = false;
  bool _isVerifyingCode = false;
  bool _isSubmittingPassword = false;
  bool _showPassword = false;
  bool _isDeleting = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return;
    setState(() => _isSendingCode = true);
    try {
      await widget.client.setAuthenticationPhoneNumber(phone);
      await Future.delayed(const Duration(seconds: 1));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending code: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingCode = false);
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    setState(() => _isVerifyingCode = true);
    try {
      await widget.client.checkAuthenticationCode(code);
      await Future.delayed(const Duration(seconds: 1));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Verification failed: $e'), backgroundColor: AppColors.error),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Password verification failed: $e'), backgroundColor: AppColors.error),
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
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Remove Telegram Account', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete and log out of the account "${widget.client.displayName}"?\n\n'
          'This will revoke its session and delete all local database files for this account.',
          style: const TextStyle(color: AppColors.onSurface),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
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
        backgroundColor: AppColors.primary.withOpacity(0.2),
        child: initials.isNotEmpty
            ? Text(initials, style: const TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold, fontSize: 18))
            : const Icon(Icons.person, size: 28, color: AppColors.primaryLight),
      );
    }

    return Card(
      color: AppColors.surfaceElevated,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: client.accountId == 'primary' ? AppColors.primary : AppColors.outline,
          width: client.accountId == 'primary' ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                            color: AppColors.primary.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Primary',
                            style: TextStyle(color: AppColors.primaryLight, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    client.phoneNumber ?? 'Ready',
                    style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
                  ),
                  if (client.username != null && client.username!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '@${client.username}',
                      style: const TextStyle(fontSize: 12, color: AppColors.primaryLight),
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
      ),
    );
  }

  Widget _buildPhoneInput() {
    return Card(
      color: AppColors.surfaceElevated,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.login, color: AppColors.primaryLight),
                SizedBox(width: 8),
                Text(
                  'Add Telegram Account',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Enter your Telegram phone number with country code (e.g. +1234567890).',
              style: TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                prefixIcon: Icon(Icons.phone_outlined),
                border: OutlineInputBorder(),
                hintText: '+1 234 567 8900',
              ),
              keyboardType: TextInputType.phone,
              enabled: !_isSendingCode,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    ref.read(telegramManagerProvider.notifier).removeClient(widget.client.accountId);
                  },
                  child: const Text('Cancel', style: TextStyle(color: Colors.redAccent)),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _isSendingCode ? null : _sendCode,
                  child: _isSendingCode
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Send Verification Code'),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildCodeInput() {
    return Card(
      color: AppColors.surfaceElevated,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.primary),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.security, color: AppColors.primaryLight),
                SizedBox(width: 8),
                Text(
                  'Verification Code',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'A verification code has been sent to ${_phoneController.text.isNotEmpty ? _phoneController.text : "your phone number"}.',
              style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(
                labelText: 'Code',
                prefixIcon: Icon(Icons.pin_outlined),
                border: OutlineInputBorder(),
                hintText: 'Enter the 5-digit code',
              ),
              keyboardType: TextInputType.number,
              enabled: !_isVerifyingCode,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    ref.read(telegramManagerProvider.notifier).removeClient(widget.client.accountId);
                  },
                  child: const Text('Cancel', style: TextStyle(color: Colors.redAccent)),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _isVerifyingCode ? null : _verifyCode,
                  child: _isVerifyingCode
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Verify & Login'),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildPasswordInput() {
    return Card(
      color: AppColors.surfaceElevated,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.amber),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.password, color: Colors.amber),
                SizedBox(width: 8),
                Text(
                  '2-Step Verification',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Your Telegram account is protected with 2-step verification. Please enter your password.',
              style: TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_showPassword ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
                border: const OutlineInputBorder(),
              ),
              obscureText: !_showPassword,
              enabled: !_isSubmittingPassword,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    ref.read(telegramManagerProvider.notifier).removeClient(widget.client.accountId);
                  },
                  child: const Text('Cancel', style: TextStyle(color: Colors.redAccent)),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _isSubmittingPassword ? null : _submitPassword,
                  child: _isSubmittingPassword
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Submit Password'),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildLoadingView(String message) {
    return Card(
      color: AppColors.surfaceElevated,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = widget.client.authState;

    switch (authState) {
      case TelegramAuthState.ready:
        return _buildConnectedView()
            .animate()
            .fadeIn(duration: 300.ms)
            .shimmer(duration: 1000.ms, color: Colors.green.withOpacity(0.1));
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
        return Card(
          color: AppColors.surfaceElevated,
          margin: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.error),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.error_outline, color: AppColors.error),
                    SizedBox(width: 8),
                    Text(
                      'Connection Error',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('An error occurred while connecting to TDLib. Please verify API configuration.'),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton(
                      onPressed: () {
                        ref.read(telegramManagerProvider.notifier).removeClient(widget.client.accountId);
                      },
                      child: const Text('Remove & Retry'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
    }
  }
}
