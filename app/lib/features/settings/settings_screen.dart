import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants.dart';

/// Settings screen — app configuration, accounts, security modes.
///
/// Placeholder for Phase 5; shows categorized settings sections.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SettingsSection(
            title: 'ACCOUNT',
            children: [
              _SettingsTile(
                icon: Icons.phone_android,
                iconColor: AppColors.secondary,
                title: 'Telegram Accounts',
                subtitle: 'No accounts linked',
                onTap: () {},
              ),
              _SettingsTile(
                icon: Icons.storage_outlined,
                iconColor: AppColors.primary,
                title: 'Storage Channels',
                subtitle: 'Configure storage destinations',
                onTap: () {},
              ),
            ],
          ),
          _SettingsSection(
            title: 'SECURITY',
            children: [
              _SettingsTile(
                icon: Icons.shield_outlined,
                iconColor: AppColors.success,
                title: 'Encryption Mode',
                subtitle: 'Convenience mode',
                onTap: () {},
              ),
              _SettingsTile(
                icon: Icons.key_outlined,
                iconColor: AppColors.warning,
                title: 'Recovery Phrase',
                subtitle: 'Back up your recovery phrase',
                onTap: () {},
              ),
            ],
          ),
          _SettingsSection(
            title: 'ABOUT',
            children: [
              _SettingsTile(
                icon: Icons.info_outline,
                iconColor: AppColors.onSurfaceVariant,
                title: 'Version',
                subtitle: AppConstants.appVersion,
                onTap: () {},
              ),
              _SettingsTile(
                icon: Icons.code_outlined,
                iconColor: AppColors.onSurfaceVariant,
                title: 'Open Source Licenses',
                subtitle: 'AGPL-3.0',
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Text(
            title,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(title, style: theme.textTheme.bodyLarge),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      onTap: onTap,
    );
  }
}
