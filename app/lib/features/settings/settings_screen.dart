import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:aerodrive/core/theme/app_colors.dart';
import 'package:aerodrive/features/telegram/telegram_service.dart';
import 'package:aerodrive/features/settings/webdav_settings_dialog.dart';
import 'package:aerodrive/features/settings/backup_dialogs.dart';
import 'package:aerodrive/features/settings/security_settings_dialogs.dart';
import 'package:aerodrive/features/settings/transfer_settings_dialogs.dart';
import 'package:aerodrive/features/settings/media_settings_dialogs.dart';
import 'package:aerodrive/features/settings/auto_backup_settings_dialogs.dart';
import 'package:aerodrive/features/settings/integration_settings_dialogs.dart';
import 'package:aerodrive/features/settings/companion_server_dialogs.dart';
import 'package:aerodrive/features/settings/network_settings_dialogs.dart';
import 'package:aerodrive/features/settings/appearance_settings_screen.dart';
import 'package:aerodrive/features/settings/advanced_settings_dialogs.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:aerodrive/features/security/biometric_service.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';

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
          _buildTile(context, 'Telegram Accounts', 'Add, remove, or switch accounts', Icons.switch_account, onTap: () {
            context.push('/settings/accounts');
          }),
          _buildTile(context, 'Session Management', 'Active sessions, remote logout', Icons.devices, onTap: () {
            context.push('/settings/session');
          }),
          _buildTile(context, 'Profile', 'Name, Avatar', Icons.badge_outlined, onTap: () {
            context.push('/settings/profile');
          }),
          
          _buildSectionHeader(context, 'Storage Channels', Icons.dns_outlined),
          _buildTile(context, 'Storage Channels', 'Add, remove, or switch storage backends', Icons.dns_outlined, onTap: () {
            context.push('/settings/channels');
          }),
          _buildTile(context, 'Load Balancing Strategy', 'Round Robin / Fill First / Random / Size-Based', Icons.balance, onTap: () {
            context.push('/settings/channels/load_balancing');
          }),
          _buildTile(context, 'Channel Health Check', 'Verify integrity of channel messages', Icons.health_and_safety_outlined, onTap: () {
            context.push('/settings/channels/health');
          }),

          _buildSectionHeader(context, 'Backup & Restore', Icons.settings_backup_restore),
          _buildTile(context, 'Export Backup', 'Local .aerobackup file', Icons.download, onTap: () {
            showDialog(context: context, builder: (context) => const BackupExportDialog());
          }),
          _buildTile(context, 'Import Backup', 'Restore from local storage', Icons.upload, onTap: () {
            showDialog(context: context, builder: (context) => const BackupImportDialog());
          }),
          _buildTile(context, 'Auto-Backup Schedule', 'Daily / Weekly / Monthly', Icons.schedule, onTap: () {
            showDialog(context: context, builder: (context) => const BackupScheduleDialog());
          }),
          _buildTile(context, 'Dropbox Backup', 'Connect / Frequency / Max Retained', Icons.cloud_done_outlined, onTap: () {
            context.push('/settings/backup/dropbox');
          }),
          _buildTile(context, 'Telegram Self-Backup', 'Save to Saved Messages', Icons.telegram, onTap: () {
            showDialog(context: context, builder: (context) => const TelegramSelfBackupDialog());
          }),

          _buildSectionHeader(context, 'Security', Icons.security),
          _buildTile(context, 'Encryption Mode', 'Off / Convenience / Maximum Security', Icons.lock_outline, onTap: () {
            showDialog(context: context, builder: (context) => const EncryptionModeDialog());
          }),
          _buildTile(context, 'Master Password Setup', 'Create or update password', Icons.password, onTap: () {
            context.push('/security_setup');
          }),
          _buildTile(context, 'View Recovery Phrase', '24-word BIP39 phrase', Icons.vpn_key_outlined, onTap: () {
            showDialog(context: context, builder: (context) => const RecoveryPhraseDialog());
          }),
          _buildTile(context, 'Duress PIN Setup', 'Configure hidden vault', Icons.pin_outlined, onTap: () {
            showDialog(context: context, builder: (context) => const DuressPinDialog());
          }),
          _buildTile(context, 'Auto-Lock Timeout', '1m / 5m / 15m / 1h / Never', Icons.timer_outlined, onTap: () {
            showDialog(context: context, builder: (context) => const AutoLockTimeoutDialog());
          }),
          Consumer(builder: (context, ref, _) {
            return FutureBuilder<String?>(
              future: ref.read(settingsRepositoryProvider).getSetting('use_biometrics'),
              builder: (context, snapshot) {
                final isEnabled = snapshot.data == 'true';
                return SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  secondary: const Icon(Icons.fingerprint, color: Colors.white70),
                  title: const Text('Biometric Unlock', style: TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: const Text('Fingerprint / Face ID', style: TextStyle(color: Colors.white54)),
                  value: isEnabled,
                  activeColor: Colors.blueAccent,
                  onChanged: (val) async {
                    if (val) {
                      final auth = await ref.read(biometricServiceProvider).authenticate('Enable Biometrics');
                      if (auth) {
                        await ref.read(settingsRepositoryProvider).setSetting('use_biometrics', 'true');
                      }
                    } else {
                      await ref.read(settingsRepositoryProvider).setSetting('use_biometrics', 'false');
                    }
                    ref.invalidate(settingsRepositoryProvider); // Force rebuild
                  },
                );
              }
            );
          }),

          _buildSectionHeader(context, 'Upload & Download', Icons.swap_vert),
          Consumer(builder: (context, ref, _) {
            return FutureBuilder<String?>(
              future: ref.read(settingsRepositoryProvider).getSetting('parallel_threads'),
              builder: (context, snapshot) {
                final threads = snapshot.data ?? '3';
                return _buildTile(context, 'Parallel Threads', '$threads concurrent transfers', Icons.layers_outlined, onTap: () {
                  showDialog(context: context, builder: (context) => const ParallelThreadsDialog()).then((_) => ref.invalidate(settingsRepositoryProvider));
                });
              }
            );
          }),
          Consumer(builder: (context, ref, _) {
            return FutureBuilder<String?>(
              future: ref.read(settingsRepositoryProvider).getSetting('bandwidth_limit'),
              builder: (context, snapshot) {
                final limit = snapshot.data ?? 'Uncapped';
                final subtitle = limit == 'Uncapped' ? limit : '$limit MB/s';
                return _buildTile(context, 'Bandwidth Limit', subtitle, Icons.speed, onTap: () {
                  showDialog(context: context, builder: (context) => const BandwidthLimitDialog()).then((_) => ref.invalidate(settingsRepositoryProvider));
                });
              }
            );
          }),
          Consumer(builder: (context, ref, _) {
            return FutureBuilder<String?>(
              future: ref.read(settingsRepositoryProvider).getSetting('wifi_only_transfers'),
              builder: (context, snapshot) {
                final isEnabled = snapshot.data == 'true';
                return SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  secondary: const Icon(Icons.wifi, color: Colors.white70),
                  title: const Text('Wi-Fi Only Toggle', style: TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: const Text('Save mobile data', style: TextStyle(color: Colors.white54)),
                  value: isEnabled,
                  activeColor: Colors.blueAccent,
                  onChanged: (val) async {
                    await ref.read(settingsRepositoryProvider).setSetting('wifi_only_transfers', val ? 'true' : 'false');
                    ref.invalidate(settingsRepositoryProvider);
                  },
                );
              }
            );
          }),
          Consumer(builder: (context, ref, _) {
            return FutureBuilder<String?>(
              future: ref.read(settingsRepositoryProvider).getSetting('auto_retry_count'),
              builder: (context, snapshot) {
                final retry = snapshot.data ?? '3';
                return _buildTile(context, 'Auto-Retry Count', '$retry attempts before failing', Icons.replay, onTap: () {
                  showDialog(context: context, builder: (context) => const AutoRetryCountDialog()).then((_) => ref.invalidate(settingsRepositoryProvider));
                });
              }
            );
          }),
          Consumer(builder: (context, ref, _) {
            return FutureBuilder<String?>(
              future: ref.read(settingsRepositoryProvider).getSetting('upload_quality'),
              builder: (context, snapshot) {
                final quality = snapshot.data ?? 'Original';
                return _buildTile(context, 'Default Upload Quality', quality, Icons.image_outlined, onTap: () {
                  showDialog(context: context, builder: (context) => const UploadQualityDialog()).then((_) => ref.invalidate(settingsRepositoryProvider));
                });
              }
            );
          }),

          _buildSectionHeader(context, 'Media & Previews', Icons.perm_media_outlined),
          Consumer(builder: (context, ref, _) {
            return FutureBuilder<String?>(
              future: ref.read(settingsRepositoryProvider).getSetting('thumbnail_cache_size'),
              builder: (context, snapshot) {
                final size = snapshot.data ?? '1GB';
                return _buildTile(context, 'Thumbnail Cache Size', size, Icons.sd_storage_outlined, onTap: () {
                  showDialog(context: context, builder: (context) => const ThumbnailCacheSizeDialog()).then((_) => ref.invalidate(settingsRepositoryProvider));
                });
              }
            );
          }),
          _buildTile(context, 'Clear Thumbnail Cache', 'Free up local space', Icons.cleaning_services_outlined, onTap: () {
            showDialog(context: context, builder: (context) => const ClearThumbnailCacheDialog());
          }),
          Consumer(builder: (context, ref, _) {
            return FutureBuilder<String?>(
              future: ref.read(settingsRepositoryProvider).getSetting('video_player_quality'),
              builder: (context, snapshot) {
                final quality = snapshot.data ?? '1080p';
                return _buildTile(context, 'Video Player Default Quality', quality, Icons.high_quality, onTap: () {
                  showDialog(context: context, builder: (context) => const VideoPlayerQualityDialog()).then((_) => ref.invalidate(settingsRepositoryProvider));
                });
              }
            );
          }),
          Consumer(builder: (context, ref, _) {
            return FutureBuilder<String?>(
              future: ref.read(settingsRepositoryProvider).getSetting('prefetch_folder_open'),
              builder: (context, snapshot) {
                final isEnabled = snapshot.data == 'true';
                return SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  secondary: const Icon(Icons.bolt, color: Colors.white70),
                  title: const Text('Pre-fetch on Folder Open', style: TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: const Text('Load thumbnails immediately', style: TextStyle(color: Colors.white54)),
                  value: isEnabled,
                  activeColor: Colors.blueAccent,
                  onChanged: (val) async {
                    await ref.read(settingsRepositoryProvider).setSetting('prefetch_folder_open', val ? 'true' : 'false');
                    ref.invalidate(settingsRepositoryProvider);
                  },
                );
              }
            );
          }),

          _buildSectionHeader(context, 'Advanced Auto-Backup', Icons.photo_camera_back),
          Consumer(builder: (context, ref, _) {
            return FutureBuilder<String?>(
              future: ref.read(settingsRepositoryProvider).getSetting('master_autobackup_enabled'),
              builder: (context, snapshot) {
                final isEnabled = snapshot.data == 'true';
                return SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  secondary: const Icon(Icons.backup_outlined, color: Colors.white70),
                  title: const Text('Enable Auto-Backup', style: TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: const Text('Master switch for background uploads', style: TextStyle(color: Colors.white54)),
                  value: isEnabled,
                  activeColor: Colors.blueAccent,
                  onChanged: (val) async {
                    await ref.read(settingsRepositoryProvider).setSetting('master_autobackup_enabled', val ? 'true' : 'false');
                    ref.invalidate(settingsRepositoryProvider);
                  },
                );
              }
            );
          }),
          Consumer(builder: (context, ref, _) {
            return FutureBuilder<String?>(
              future: ref.read(settingsRepositoryProvider).getSetting('tracked_backup_folders'),
              builder: (context, snapshot) {
                int activeCount = 0;
                if (snapshot.hasData && snapshot.data != null && snapshot.data!.isNotEmpty) {
                  try {
                    final List<dynamic> decoded = jsonDecode(snapshot.data!);
                    activeCount = decoded.length;
                  } catch (_) {}
                }
                return _buildTile(
                  context, 
                  'Manage Tracked Folders', 
                  '$activeCount active backup profiles', 
                  Icons.folder_special_outlined, 
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageBackupFoldersScreen()))
                        .then((_) => ref.invalidate(settingsRepositoryProvider));
                  }
                );
              }
            );
          }),

          _buildSectionHeader(context, 'Notifications', Icons.notifications_outlined),
          _buildSwitchTile(context, ref, 'Upload Complete', 'Notify when files finish uploading', Icons.upload_file, 'notify_upload_complete', defaultValue: true),
          _buildSwitchTile(context, ref, 'Download Complete', 'Notify when files finish downloading', Icons.download_done, 'notify_download_complete', defaultValue: true),
          _buildSwitchTile(context, ref, 'Sync Status', 'Background sync updates', Icons.sync, 'notify_sync_status', defaultValue: false),
          _buildSwitchTile(context, ref, 'Share Link Accessed', 'Notify when someone views your link', Icons.link, 'notify_share_accessed', defaultValue: true),
          _buildSwitchTile(context, ref, 'Backup Complete', 'Notify when auto-backup finishes', Icons.backup, 'notify_backup_complete', defaultValue: true),

          _buildSectionHeader(context, 'Integrations', Icons.integration_instructions_outlined),
          _buildTile(
            context, 
            'WebDAV Server', 
            'Enable / Port / Credentials', 
            Icons.dns,
            onTap: () {
              showDialog(context: context, builder: (context) => const WebDavSettingsDialog());
            },
          ),
          _buildSecureTile(context, 'Inline Bot Setup', 'integration_inline_bot_token', Icons.smart_button, () {
            showDialog(context: context, builder: (context) => const InlineBotSetupDialog()).then((_) => (context as Element).markNeedsBuild());
          }),
          _buildSecureTile(context, 'Save to Drive Bot Setup', 'integration_savetodrive_bot_token', Icons.save_alt, () {
            showDialog(context: context, builder: (context) => const SaveToDriveBotDialog()).then((_) => (context as Element).markNeedsBuild());
          }),
          _buildSecureTile(context, 'Webhook URL', 'integration_webhook_url', Icons.webhook, () {
            showDialog(context: context, builder: (context) => const WebhookUrlDialog()).then((_) => (context as Element).markNeedsBuild());
          }),
          _buildSecureTile(context, 'API Key Management', 'integration_api_key', Icons.vpn_key, () {
            showDialog(context: context, builder: (context) => const ApiKeyManagementDialog()).then((_) => (context as Element).markNeedsBuild());
          }),

          _buildSectionHeader(context, 'Companion Server', Icons.cloud_sync_outlined),
          _buildSecureTile(context, 'Companion Server Setup', 'companion_server_url', Icons.cloud_upload_outlined, () {
            showDialog(context: context, builder: (context) => const CompanionServerDialog()).then((_) => (context as Element).markNeedsBuild());
          }),

          _buildSectionHeader(context, 'Network', Icons.network_check),
          Consumer(builder: (context, ref, _) {
            return FutureBuilder<String?>(
              future: ref.read(settingsRepositoryProvider).getSetting('proxy_enabled'),
              builder: (context, snapshot) {
                final isEnabled = snapshot.data == 'true';
                return _buildTile(context, 'Proxy Settings', isEnabled ? 'Enabled' : 'SOCKS5 / MTProto', Icons.router_outlined, onTap: () {
                  context.push('/settings/proxy').then((_) => ref.invalidate(settingsRepositoryProvider));
                });
              }
            );
          }),
          Consumer(builder: (context, ref, _) {
            return FutureBuilder<String?>(
              future: ref.read(settingsRepositoryProvider).getSetting('network_connection_timeout'),
              builder: (context, snapshot) {
                final timeout = snapshot.data ?? '30';
                return _buildTile(context, 'Connection Timeout', '$timeout seconds', Icons.timer, onTap: () {
                  showDialog(context: context, builder: (context) => const ConnectionTimeoutDialog());
                });
              }
            );
          }),
          _buildSwitchTile(context, ref, 'Adaptive Chunking', 'Dynamic chunk sizing based on connection speed', Icons.dynamic_form_outlined, 'network_adaptive_chunking', defaultValue: true),

          _buildSectionHeader(context, 'Appearance', Icons.palette),
          _buildTile(context, 'Theme & Colors', 'Dark / Light, Accent, Icons', Icons.color_lens_outlined, onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const AppearanceSettingsScreen()));
          }),

          _buildSectionHeader(context, 'Accessibility', Icons.accessibility_new),
          _buildSwitchTile(context, ref, 'Screen Reader Optimizations', 'TalkBack / VoiceOver support', Icons.record_voice_over, 'accessibility_screen_reader', defaultValue: false),
          _buildSwitchTile(context, ref, 'Reduce Motion', 'Disable animations', Icons.animation, 'accessibility_reduce_motion', defaultValue: false),
          _buildSwitchTile(context, ref, 'Large Touch Targets', 'Easier navigation', Icons.touch_app, 'accessibility_large_targets', defaultValue: false),

          _buildSectionHeader(context, 'Advanced', Icons.build_circle_outlined),
          _buildTile(
            context,
            'Export Logs',
            'Save debugging info',
            Icons.bug_report_outlined,
            onTap: () => context.push('/diagnostics'),
          ),
          _buildTile(context, 'Database Stats', 'File count, DB size, Channel usage', Icons.data_usage, onTap: () {
            showDialog(context: context, builder: (_) => const DatabaseStatsDialog());
          }),
          _buildTile(
            context,
            'Rebuild Drive',
            'Zero-DB Recovery from Telegram captions',
            Icons.build_outlined,
            onTap: () {
              showDialog(context: context, barrierDismissible: false, builder: (_) => const RebuildDriveDialog());
            },
          ),
          _buildTile(context, 'Clear Local Cache', 'Wipes all temporary files', Icons.delete_sweep_outlined, onTap: () {
            showDialog(context: context, builder: (_) => const ClearCacheDialog());
          }),
          _buildTile(context, 'Reset All Settings', 'Revert to defaults', Icons.restore, onTap: () {
            showDialog(context: context, builder: (_) => const ResetSettingsDialog());
          }),
          _buildTile(context, 'Open Source Licenses', 'View dependencies', Icons.policy, onTap: () {
            showLicensePage(context: context, applicationName: 'AeroDrive', applicationVersion: '1.0.0-alpha');
          }),

          _buildSectionHeader(context, 'About', Icons.info_outline),
          _buildTile(context, 'About AeroDrive', 'Version, Developer, Links', Icons.new_releases_outlined, onTap: () {
            context.push('/settings/about');
          }),
          
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

  Widget _buildSwitchTile(BuildContext context, WidgetRef ref, String title, String subtitle, IconData icon, String settingKey, {bool defaultValue = true}) {
    return Consumer(builder: (context, ref, _) {
      return FutureBuilder<String?>(
        future: ref.read(settingsRepositoryProvider).getSetting(settingKey),
        builder: (context, snapshot) {
          final isEnabled = snapshot.data == null ? defaultValue : snapshot.data == 'true';
          return SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            secondary: Icon(icon, color: Colors.white70),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
            value: isEnabled,
            activeColor: Colors.blueAccent,
            onChanged: (val) async {
              await ref.read(settingsRepositoryProvider).setSetting(settingKey, val ? 'true' : 'false');
              ref.invalidate(settingsRepositoryProvider);
            },
          );
        }
      );
    });
  }

  Widget _buildSecureTile(BuildContext context, String title, String secureKey, IconData icon, VoidCallback onTap) {
    const storage = FlutterSecureStorage();
    return FutureBuilder<String?>(
      future: storage.read(key: secureKey),
      builder: (context, snapshot) {
        final isConfigured = snapshot.data != null && snapshot.data!.isNotEmpty;
        final subtitle = isConfigured ? 'Configured' : 'Not configured';
        final color = isConfigured ? Colors.greenAccent : Colors.white54;
        
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: Icon(icon, color: Colors.blueAccent),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
          subtitle: Text(subtitle, style: TextStyle(color: color)),
          trailing: const Icon(Icons.chevron_right, color: Colors.white24),
          onTap: onTap,
        );
      }
    );
  }

  Widget _buildTile(BuildContext context, String title, String subtitle, IconData icon, {VoidCallback? onTap}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
      trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.white24),
      onTap: onTap ?? () {
        // TODO: Navigate to specific settings sub-page
      },
    );
  }

}
