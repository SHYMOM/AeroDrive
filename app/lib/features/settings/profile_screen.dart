import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../telegram/telegram_manager.dart';
import '../telegram/telegram_service.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Widget _buildAvatar(TelegramService client, {double radius = 40}) {
    final photoPath = client.photoPath;
    if (photoPath != null && File(photoPath).existsSync()) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: FileImage(File(photoPath)),
      );
    }

    final initials = client.displayName.isNotEmpty
        ? client.displayName.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join().toUpperCase()
        : '';

    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary.withValues(alpha: 0.2),
      child: initials.isNotEmpty
          ? Text(initials, style: TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold, fontSize: radius * 0.5))
          : Icon(Icons.person, size: radius, color: AppColors.primaryLight),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(telegramManagerProvider);
    
    // Find primary and secondary accounts
    final primary = accounts.firstWhere((c) => c.accountId == 'primary', orElse: () => accounts.first);
    final secondaries = accounts.where((c) => c.accountId != 'primary' && c.authState == TelegramAuthState.ready).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Telegram Profiles'),
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Primary Profile Card
          Center(
            child: Text(
              'PRIMARY ACCOUNT',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: AppColors.surfaceElevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  _buildAvatar(primary, radius: 50),
                  const SizedBox(height: 16),
                  Text(
                    primary.displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    primary.phoneNumber ?? 'Not authenticated',
                    style: const TextStyle(fontSize: 14, color: AppColors.onSurfaceVariant),
                  ),
                  if (primary.username != null && primary.username!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '@${primary.username}',
                        style: const TextStyle(color: AppColors.primaryLight, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Secondary Account Profiles
          if (secondaries.isNotEmpty) ...[
            const Row(
              children: [
                Icon(Icons.link, size: 18, color: AppColors.secondaryLight),
                SizedBox(width: 8),
                Text(
                  'LINKED SECONDARY PROFILES',
                  style: TextStyle(
                    color: AppColors.secondaryLight,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...secondaries.map((client) => Card(
                color: AppColors.surface,
                margin: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppColors.outline),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: _buildAvatar(client, radius: 24),
                  title: Text(
                    client.displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(client.phoneNumber ?? 'Secondary Load-Balancer', style: const TextStyle(fontSize: 12)),
                      if (client.username != null && client.username!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '@${client.username}',
                          style: const TextStyle(fontSize: 11, color: AppColors.secondaryLight),
                        ),
                      ],
                    ],
                  ),
                ),
              )),
          ] else ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  children: [
                    Icon(Icons.people_outline, size: 48, color: AppColors.onSurfaceVariant),
                    SizedBox(height: 12),
                    Text(
                      'No secondary accounts linked yet',
                      style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
