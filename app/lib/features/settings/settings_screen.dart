import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/core/theme/app_colors.dart';
import 'package:aerodrive/features/telegram/telegram_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          _buildSectionHeader(context, 'Account', Icons.person_outline),
          _buildTile(context, 'Telegram Accounts', 'Add, remove, or switch accounts', Icons.switch_account),
          _buildTile(context, 'Session Management', 'Active sessions, remote logout', Icons.devices),
          _buildTile(context, 'Profile', 'Name, Avatar', Icons.badge_outlined),
          
          _buildSectionHeader(context, 'Storage Channels', Icons.dns_outlined),
          _buildTile(context, 'Add New Channel', 'Create or link a Telegram channel', Icons.add_circle_outline),
          _buildTile(context, 'Channel List', 'Name, Used Space, Health', Icons.list_alt),
          _buildTile(context, 'Load Balancing Strategy', 'Round Robin / Fill First / Random / Size-Based', Icons.balance),
          _buildTile(context, 'Channel Health Check', 'Verify integrity of channel messages', Icons.health_and_safety_outlined),

          _buildSectionHeader(context, 'Backup & Restore', Icons.settings_backup_restore),
          _buildTile(context, 'Export Backup', 'Local .aerobackup file', Icons.download),
          _buildTile(context, 'Import Backup', 'Restore from local storage', Icons.upload),
          _buildTile(context, 'Auto-Backup Schedule', 'Daily / Weekly / Monthly', Icons.schedule),
          _buildTile(context, 'Google Drive Backup', 'Connect / Frequency / Max Retained', Icons.cloud_circle_outlined),
          _buildTile(context, 'Telegram Self-Backup', 'Save to Saved Messages', Icons.telegram),

          _buildSectionHeader(context, 'Security', Icons.security),
          _buildTile(context, 'Encryption Mode', 'Off / Convenience / Maximum Security', Icons.lock_outline),
          _buildTile(context, 'Change Password', 'Update master password', Icons.password),
          _buildTile(context, 'View Recovery Phrase', '24-word BIP39 phrase', Icons.vpn_key_outlined),
          _buildTile(context, 'Duress PIN Setup', 'Configure hidden vault', Icons.pin_outlined),
          _buildTile(context, 'Auto-Lock Timeout', '1m / 5m / 15m / 1h / Never', Icons.timer_outlined),
          _buildTile(context, 'Biometric Unlock', 'Fingerprint / Face ID', Icons.fingerprint),

          _buildSectionHeader(context, 'Upload & Download', Icons.swap_vert),
          _buildTile(context, 'Parallel Threads', '1-10 concurrent transfers', Icons.layers_outlined),
          _buildTile(context, 'Bandwidth Limit', 'Cap upload/download speeds', Icons.speed),
          _buildTile(context, 'Wi-Fi Only Toggle', 'Save mobile data', Icons.wifi),
          _buildTile(context, 'Auto-Retry Count', 'Exponential backoff settings', Icons.replay),
          _buildTile(context, 'Default Upload Quality', 'Photos: Original / High / Medium', Icons.image_outlined),

          _buildSectionHeader(context, 'Media & Previews', Icons.perm_media_outlined),
          _buildTile(context, 'Thumbnail Cache Size', '500MB / 1GB / 2GB / Unlimited', Icons.sd_storage_outlined),
          _buildTile(context, 'Clear Thumbnail Cache', 'Free up local space', Icons.cleaning_services_outlined),
          _buildTile(context, 'Video Player Default Quality', 'Original / 1080p / 720p', Icons.high_quality),
          _buildTile(context, 'Pre-fetch on Folder Open', 'On / Off', Icons.bolt),

          _buildSectionHeader(context, 'Auto-Backup (Camera Roll)', Icons.photo_camera_back),
          _buildTile(context, 'Enable Auto-Backup', 'On / Off', Icons.backup_outlined),
          _buildTile(context, 'Selected Folders', 'Camera, Screenshots, WhatsApp', Icons.folder_special_outlined),
          _buildTile(context, 'Upload Quality', 'Original / High / Medium', Icons.hd_outlined),
          _buildTile(context, 'Include Videos', 'On / Off', Icons.video_file_outlined),

          _buildSectionHeader(context, 'Notifications', Icons.notifications_outlined),
          _buildTile(context, 'Upload Complete', 'On / Off', Icons.upload_file),
          _buildTile(context, 'Download Complete', 'On / Off', Icons.download_done),
          _buildTile(context, 'Sync Status', 'On / Off', Icons.sync),
          _buildTile(context, 'Share Link Accessed', 'On / Off', Icons.link),
          _buildTile(context, 'Backup Complete', 'On / Off', Icons.backup),

          _buildSectionHeader(context, 'Integrations', Icons.integration_instructions_outlined),
          _buildTile(context, 'WebDAV Server', 'Enable / Port / Credentials', Icons.dns),
          _buildTile(context, 'Inline Bot Setup', 'Search via @aerodrive_bot', Icons.smart_button),
          _buildTile(context, 'Save to Drive Bot Setup', 'Forward to save', Icons.save_alt),
          _buildTile(context, 'Webhook URL', 'Automate via POST requests', Icons.webhook),
          _buildTile(context, 'API Key Management', 'For third-party tools', Icons.vpn_key),

          _buildSectionHeader(context, 'Network', Icons.network_check),
          _buildTile(context, 'Proxy Settings', 'SOCKS5 / MTProto', Icons.router_outlined),
          _buildTile(context, 'Connection Timeout', 'Manage delay limits', Icons.timer),
          _buildTile(context, 'Adaptive Chunking', 'Dynamic chunk sizing based on connection', Icons.dynamic_form_outlined),

          _buildSectionHeader(context, 'Appearance', Icons.palette_outlined),
          _buildTile(context, 'Theme', 'System / Dark / Light / Material You', Icons.color_lens_outlined),
          _buildTile(context, 'Accent Color', 'Deep Purple', Icons.format_color_fill),
          _buildTile(context, 'File Icon Style', 'Choose icon set', Icons.insert_drive_file_outlined),
          _buildTile(context, 'Language', 'English, Spanish, etc.', Icons.language),
          _buildTile(context, 'Font Size', 'System default', Icons.text_fields),
          _buildTile(context, 'High Contrast Mode', 'On / Off', Icons.contrast),

          _buildSectionHeader(context, 'Accessibility', Icons.accessibility_new),
          _buildTile(context, 'Screen Reader Optimizations', 'TalkBack / VoiceOver support', Icons.record_voice_over),
          _buildTile(context, 'Reduce Motion', 'Disable animations', Icons.animation),
          _buildTile(context, 'Large Touch Targets', 'Easier navigation', Icons.touch_app),

          _buildSectionHeader(context, 'Advanced', Icons.build_circle_outlined),
          _buildTile(context, 'Export Logs', 'Save debugging info', Icons.bug_report_outlined),
          _buildTile(context, 'Database Stats', 'File count, DB size, Channel usage', Icons.data_usage),
          _buildTile(context, 'Rebuild Drive', 'Zero-DB Recovery from Telegram captions', Icons.build_outlined),
          _buildTile(context, 'Clear Local Cache', 'Wipes all temporary files', Icons.delete_sweep_outlined),
          _buildTile(context, 'Reset All Settings', 'Revert to defaults', Icons.restore),
          _buildTile(context, 'Open Source Licenses', 'View dependencies', Icons.policy),

          _buildSectionHeader(context, 'About', Icons.info_outline),
          _buildTile(context, 'Version', '1.0.0-alpha', Icons.new_releases_outlined),
          _buildTile(context, 'Check for Updates', 'Verify latest release', Icons.update),
          _buildTile(context, 'GitHub Repository', 'View source code', Icons.code),
          _buildTile(context, 'Report a Bug', 'Submit issue on GitHub', Icons.report_problem),
          _buildTile(context, 'Donate', 'Support the project', Icons.favorite_border),
          
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: FilledButton.icon(
              onPressed: () {
                ref.read(telegramServiceProvider.notifier).logOut();
              },
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.withValues(alpha: 0.2),
                foregroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(BuildContext context, String title, String subtitle, IconData icon) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
      trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.white24),
      onTap: () {
        // TODO: Navigate to specific settings sub-page
      },
    );
  }
}
