import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/background_service_manager.dart';
import '../telegram/telegram_service.dart';
import 'advanced_settings_dialogs.dart';
import 'appearance_settings_screen.dart';
import 'auto_backup_settings_dialogs.dart';
import 'backup_dialogs.dart';
import 'media_settings_dialogs.dart';
import 'transfer_settings_dialogs.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: cs.onSurface),
          onPressed: () => context.go('/drive'),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchBar(cs),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                physics: const BouncingScrollPhysics(),
                children: [
                  _buildSettingsGroup('Account', Icons.person_outline, cs, [
                    _SettingsItem('Telegram Accounts', 'Add, remove, or switch accounts', Icons.switch_account, onTap: () => context.push('/settings/accounts')),
                    _SettingsItem('Session Management', 'Active sessions, remote logout', Icons.devices, onTap: () => context.push('/settings/session')),
                    _SettingsItem('Profile', 'Name, Avatar', Icons.badge_outlined, onTap: () => context.push('/settings/profile')),
                  ]),
                  _buildSettingsGroup('Storage Channels', Icons.dns_outlined, cs, [
                    _SettingsItem('Storage Channels', 'Manage storage backends', Icons.dns_outlined, onTap: () => context.push('/settings/channels')),
                    _SettingsItem('Load Balancing Strategy', 'Round Robin / Fill First / Random', Icons.balance, onTap: () => context.push('/settings/channels/load_balancing')),
                    _SettingsItem('Channel Health Check', 'Verify integrity of channel messages', Icons.health_and_safety_outlined, onTap: () => context.push('/settings/channels/health')),
                  ]),
                  _buildSettingsGroup('Backup & Restore', Icons.settings_backup_restore, cs, [
                    _SettingsItem('Export Backup', 'Local .aerobackup file', Icons.download, onTap: () => showDialog(context: context, builder: (_) => const BackupExportDialog())),
                    _SettingsItem('Import Backup', 'Restore from local storage', Icons.upload, onTap: () => showDialog(context: context, builder: (_) => const BackupImportDialog())),
                    _SettingsItem('Auto-Backup Schedule', 'Daily / Weekly / Monthly', Icons.schedule, onTap: () => showDialog(context: context, builder: (_) => const BackupScheduleDialog())),
                    _SettingsItem('Dropbox Backup', 'Connect / Frequency', Icons.cloud_done_outlined, onTap: () => context.push('/settings/backup/dropbox')),
                    _SettingsItem('Telegram Self-Backup', 'Save to Saved Messages', Icons.telegram, onTap: () => showDialog(context: context, builder: (_) => const TelegramSelfBackupDialog())),
                  ]),
                  _buildSettingsGroup('Upload & Download', Icons.swap_vert, cs, [
                    _buildDynamicItem('Parallel Threads', 'concurrent transfers', Icons.layers_outlined, 'parallel_threads', '3', () => showDialog(context: context, builder: (_) => const ParallelThreadsDialog())),
                    _buildDynamicItem('Bandwidth Limit', 'MB/s', Icons.speed, 'bandwidth_limit', 'Uncapped', () => showDialog(context: context, builder: (_) => const BandwidthLimitDialog())),
                    _buildDynamicItem('Auto-Retry Count', 'attempts before failing', Icons.replay, 'auto_retry_count', '3', () => showDialog(context: context, builder: (_) => const AutoRetryCountDialog())),
                    _buildDynamicItem('Default Upload Quality', 'quality', Icons.image_outlined, 'upload_quality', 'Original', () => showDialog(context: context, builder: (_) => const UploadQualityDialog())),
                  ]),
                  _buildSettingsGroup('Media & Previews', Icons.perm_media_outlined, cs, [
                    _buildDynamicItem('Thumbnail Cache Size', 'max storage limit', Icons.sd_storage_outlined, 'thumbnail_cache_size', '1GB', () => showDialog(context: context, builder: (_) => const ThumbnailCacheSizeDialog())),
                    _SettingsItem('Clear Thumbnail Cache', 'Free up local space', Icons.cleaning_services_outlined, onTap: () => showDialog(context: context, builder: (_) => const ClearThumbnailCacheDialog())),
                    _buildDynamicItem('Video Player Default Quality', 'resolution', Icons.high_quality, 'video_player_quality', '1080p', () => showDialog(context: context, builder: (_) => const VideoPlayerQualityDialog())),
                    _SettingsSwitchItem('Pre-fetch on Folder Open', 'Load thumbnails immediately', Icons.bolt, 'prefetch_folder_open', false),
                  ]),
                  _buildSettingsGroup('Advanced Auto-Backup', Icons.photo_camera_back, cs, [
                    _SettingsSwitchItem('Enable Auto-Backup', 'Master switch for background uploads', Icons.backup_outlined, 'master_autobackup_enabled', false),
                    _SettingsItem('Manage Tracked Folders', 'Active backup profiles', Icons.folder_special_outlined, onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageBackupFoldersScreen())).then((_) => ref.invalidate(settingsRepositoryProvider));
                    }),
                  ]),
                  _buildSettingsGroup('Notifications', Icons.notifications_outlined, cs, [
                    _SettingsSwitchItem('Upload Complete', 'Notify when files finish uploading', Icons.upload_file, 'notify_upload_complete', true),
                    _SettingsSwitchItem('Download Complete', 'Notify when files finish downloading', Icons.download_done, 'notify_download_complete', true),
                    _SettingsSwitchItem('Share Link Accessed', 'Notify when someone views your link', Icons.link, 'notify_share_accessed', true),
                    _SettingsSwitchItem('Backup Complete', 'Notify when auto-backup finishes', Icons.backup, 'notify_backup_complete', true),
                  ]),
                  _buildSettingsGroup('Sharing', Icons.share_outlined, cs, [
                    _SettingsItem('Shared Links', 'Manage and revoke your active share links', Icons.link, onTap: () => context.push('/settings/shared_links')),
                  ]),
                  _buildSettingsGroup('Network', Icons.network_check, cs, [
                    _SettingsSwitchItem('Proxy Settings', 'SOCKS5 / MTProto', Icons.router_outlined, 'proxy_enabled', false),
                  ]),
                  _buildSettingsGroup('Appearance', Icons.palette, cs, [
                    _SettingsItem('Theme & Colors', 'Dark / Light, Accent, Icons', Icons.color_lens_outlined, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AppearanceSettingsScreen()))),
                  ]),
                  _buildSettingsGroup('Advanced', Icons.build_circle_outlined, cs, [
                    _SettingsItem('Export Logs', 'Save debugging info', Icons.bug_report_outlined, onTap: () => context.push('/diagnostics')),
                    _SettingsItem('Database Stats', 'File count, DB size, Channel usage', Icons.data_usage, onTap: () => showDialog(context: context, builder: (_) => const DatabaseStatsDialog())),
                    _SettingsItem('Rebuild Drive', 'Zero-DB Recovery from Telegram captions', Icons.build_outlined, onTap: () => showDialog(context: context, barrierDismissible: false, builder: (_) => const RebuildDriveDialog())),
                    _SettingsItem('Clear Local Cache', 'Wipes all temporary files', Icons.delete_sweep_outlined, onTap: () => showDialog(context: context, builder: (_) => const ClearCacheDialog())),
                    _SettingsItem('Reset All Settings', 'Revert to defaults', Icons.restore, onTap: () => showDialog(context: context, builder: (_) => const ResetSettingsDialog())),
                    _SettingsItem('Open Source Licenses', 'View dependencies', Icons.policy, onTap: () => showLicensePage(context: context, applicationName: 'AeroDrive', applicationVersion: '1.0.0-alpha')),
                  ]),
                  _buildSettingsGroup('About', Icons.info_outline, cs, [
                    _SettingsItem('About AeroDrive', 'Version, Developer, Links', Icons.new_releases_outlined, onTap: () => context.push('/settings/about')),
                  ]),
                  _buildSettingsGroup('AI Intelligence', Icons.psychology_outlined, cs, [
                    _SettingsSwitchItem('Power User Mode', 'Run AI processing on battery (drains battery faster)', Icons.battery_alert, 'ai_power_user', false),
                  ]),
                  const SizedBox(height: 24),
                  _buildLogoutButton(cs),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(ColorScheme cs) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: TextField(
            controller: _searchController,
            style: TextStyle(color: cs.onSurface),
            decoration: InputDecoration(
              hintText: 'Search settings...',
              hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
              prefixIcon: Icon(Icons.search, color: cs.primary),
              suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear, color: cs.onSurfaceVariant),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
            onChanged: (val) {
              setState(() => _searchQuery = val.toLowerCase());
            },
          ),
        ),
      )
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.2, end: 0);

  Widget _buildSettingsGroup(String title, IconData icon, ColorScheme cs, List<dynamic> items) {
    final filteredItems = items.where((item) {
      if (_searchQuery.isEmpty) return true;
      if (item is _SettingsItem) {
        return item.title.toLowerCase().contains(_searchQuery) || item.subtitle.toLowerCase().contains(_searchQuery);
      } else if (item is _SettingsSwitchItem) {
        return item.title.toLowerCase().contains(_searchQuery) || item.subtitle.toLowerCase().contains(_searchQuery);
      } else if (item is _DynamicItemBuilder) {
        return item.title.toLowerCase().contains(_searchQuery);
      }
      return false;
    }).toList();

    if (filteredItems.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Column(
                children: List.generate(filteredItems.length, (index) {
                  final item = filteredItems[index];
                  Widget child;
                  if (item is _SettingsItem) {
                    child = _buildTile(item.title, item.subtitle, item.icon, item.onTap, cs);
                  } else if (item is _SettingsSwitchItem) {
                    child = _buildSwitchTile(item.title, item.subtitle, item.icon, item.settingKey, item.defaultValue, cs);
                  } else if (item is _DynamicItemBuilder) {
                    child = item.build(context, ref);
                  } else {
                    child = const SizedBox.shrink();
                  }

                  return Column(
                    children: [
                      child,
                      if (index < filteredItems.length - 1)
                        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3), indent: 56),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ).animate().fadeIn(duration: 500.ms).slideX(begin: 0.1, end: 0),
    );
  }

  Widget _buildTile(String title, String subtitle, IconData icon, VoidCallback? onTap, ColorScheme cs) => Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        highlightColor: cs.primary.withValues(alpha: 0.05),
        splashColor: cs.primary.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: cs.primary, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: cs.onSurface)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );

  Widget _buildSwitchTile(String title, String subtitle, IconData icon, String settingKey, bool defaultValue, ColorScheme cs) =>
      Consumer(builder: (context, ref, _) => FutureBuilder<String?>(
          future: ref.watch(settingsRepositoryProvider).getSetting(settingKey),
          builder: (context, snapshot) {
            final isEnabled = snapshot.data == null ? defaultValue : snapshot.data == 'true';
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
                  final newVal = !isEnabled;
                  await ref.read(settingsRepositoryProvider).setSetting(settingKey, newVal ? 'true' : 'false');
                  if (settingKey == 'master_autobackup_enabled') {
                    if (newVal) {
                      await BackgroundServiceManager.startService();
                    } else {
                      await BackgroundServiceManager.stopService();
                    }
                  }
                  ref.invalidate(settingsRepositoryProvider);
                },
                highlightColor: cs.primary.withValues(alpha: 0.05),
                splashColor: cs.primary.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, color: cs.primary, size: 22),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: cs.onSurface)),
                            const SizedBox(height: 2),
                            Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                          ],
                        ),
                      ),
                      CupertinoSwitch(
                        value: isEnabled,
                        activeTrackColor: cs.primary,
                        onChanged: (val) async {
                          await ref.read(settingsRepositoryProvider).setSetting(settingKey, val ? 'true' : 'false');
                          if (settingKey == 'master_autobackup_enabled') {
                            if (val) {
                              await BackgroundServiceManager.startService();
                            } else {
                              await BackgroundServiceManager.stopService();
                            }
                          }
                          ref.invalidate(settingsRepositoryProvider);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
        ));

  _DynamicItemBuilder _buildDynamicItem(String title, String subtitleSuffix, IconData icon, String settingKey, String defaultValue, VoidCallback action) => _DynamicItemBuilder(
      title: title,
      builder: (context, ref) {
        final cs = Theme.of(context).colorScheme;
        return FutureBuilder<String?>(
            future: ref.watch(settingsRepositoryProvider).getSetting(settingKey),
            builder: (context, snapshot) {
              final value = snapshot.data ?? defaultValue;
              final subtitle = settingKey == 'bandwidth_limit' && value == 'Uncapped'
                  ? 'Uncapped'
                  : '$value $subtitleSuffix';
              return _buildTile(title, subtitle, icon, () {
                action();
                ref.invalidate(settingsRepositoryProvider);
              }, cs);
            }
          );
      }
    );

  Widget _buildLogoutButton(ColorScheme cs) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => ref.read(telegramServiceProvider.notifier).logOut(),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: cs.error.withValues(alpha: 0.1),
              border: Border.all(color: cs.error.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.logout, color: cs.error),
                const SizedBox(width: 8),
                Text('Sign Out', style: TextStyle(color: cs.error, fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(delay: 300.ms, duration: 400.ms);
}

class _SettingsItem {
  _SettingsItem(this.title, this.subtitle, this.icon, {required this.onTap});
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
}

class _SettingsSwitchItem {
  _SettingsSwitchItem(this.title, this.subtitle, this.icon, this.settingKey, this.defaultValue);
  final String title;
  final String subtitle;
  final IconData icon;
  final String settingKey;
  final bool defaultValue;
}

class _DynamicItemBuilder {
  _DynamicItemBuilder({required this.title, required this.builder});
  final String title;
  final Widget Function(BuildContext context, WidgetRef ref) builder;

  Widget build(BuildContext context, WidgetRef ref) => builder(context, ref);
}
