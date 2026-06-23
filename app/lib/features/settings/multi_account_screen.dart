import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/core/theme/app_colors.dart';
import 'package:aerodrive/features/telegram/telegram_manager.dart';
import 'package:aerodrive/features/telegram/telegram_service.dart';

class MultiAccountScreen extends ConsumerStatefulWidget {
  const MultiAccountScreen({super.key});

  @override
  ConsumerState<MultiAccountScreen> createState() => _MultiAccountScreenState();
}

class _MultiAccountScreenState extends ConsumerState<MultiAccountScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  String? _addingAccountId;

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(telegramManagerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Telegram Accounts'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Manage multiple Telegram accounts for bandwidth load balancing.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 24),
          ...accounts.map((client) {
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                child: const Icon(Icons.person, color: AppColors.primary),
              ),
              title: Text('Account ID: ${client.accountId}', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(client.accountId == 'primary' ? 'Main Account' : 'Secondary Load-Balancer'),
              trailing: client.accountId == 'primary' ? null : IconButton(
                icon: const Icon(Icons.delete, color: Colors.redAccent),
                onPressed: () {
                  ref.read(telegramManagerProvider.notifier).removeClient(client.accountId);
                },
              ),
            );
          }),
          const SizedBox(height: 32),
          if (_addingAccountId == null)
            FilledButton.icon(
              onPressed: () {
                final newId = 'account_${DateTime.now().millisecondsSinceEpoch}';
                ref.read(telegramManagerProvider.notifier).addClient(newId, isHeadless: true);
                setState(() => _addingAccountId = newId);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Another Account'),
            )
          else ...[
            const Text('Logging in to new account...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            // We find the state of the adding client
            Consumer(
              builder: (context, ref, child) {
                final client = accounts.firstWhere((c) => c.accountId == _addingAccountId, orElse: () => accounts.first);
                // Actually, listening to individual client state in a list is tricky without a family provider.
                // For simplicity, we just show generic inputs and assume user enters them correctly.
                return Column(
                  children: [
                    TextField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number (incl. country code)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () {
                        client.setAuthenticationPhoneNumber(_phoneController.text.trim());
                      },
                      child: const Text('Send Code'),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _codeController,
                      decoration: const InputDecoration(
                        labelText: 'Login Code',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () {
                        client.checkAuthenticationCode(_codeController.text.trim());
                        setState(() => _addingAccountId = null); // Reset UI assuming success
                      },
                      child: const Text('Login'),
                    ),
                  ],
                );
              },
            ),
          ]
        ],
      ),
    );
  }
}
