import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:aerodrive/core/theme/app_colors.dart';
import 'package:aerodrive/features/telegram/telegram_service.dart';
import 'package:aerodrive/features/settings/backup_dialogs.dart';
import 'package:aerodrive/features/settings/transfer_settings_dialogs.dart';
import 'package:aerodrive/features/settings/media_settings_dialogs.dart';
import 'package:aerodrive/features/settings/auto_backup_settings_dialogs.dart';
import 'package:aerodrive/features/settings/network_settings_dialogs.dart';
import 'package:aerodrive/features/settings/appearance_settings_screen.dart';
import 'package:aerodrive/features/settings/advanced_settings_dialogs.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';

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
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/drive'),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.5,
            colors: [
              Color(0xFF0D0E23), // deepSpace
              Color(0xFF1A0850), // dark edge
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildSearchBar(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _buildSettingsGroup(
                      'Account',
                      Icons.person_outline,
                      [
                        _SettingsItem('Telegram Accounts', 'Add, remove, or switch accounts', Icons.switch_account, onTap: () => context.push('/settings/accounts')),
                        _SettingsItem('Session Management', 'Active sessions, remote logout', Icons.devices, onTap: () => context.push('/settings/session')),
                        _SettingsItem('Profile', 'Name, Avatar', Icons.badge_outlined, onTap: () => context.push('/settings/profile')),
                      ],
                    ),
                    _buildSettingsGroup(
                      'Storage Channels',
                      Icons.dns_outlined,
                      [
                        _SettingsItem('Storage Channels', 'Manage storage backends', Icons.dns_outlined, onTap: () => context.push('/settings/channels')),
                        _SettingsItem('Load Balancing Strategy', 'Round Robin / Fill First / Random', Icons.balance, onTap: () => context.push('/settings/channels/load_balancing')),
                        _SettingsItem('Channel Health Check', 'Verify integrity of channel messages', Icons.health_and_safety_outlined, onTap: () => context.push('/settings/channels/health')),
                      ],
                    ),
                    _buildSettingsGroup(
                      'Backup & Restore',
                      Icons.settings_backup_restore,
                      [
                        _SettingsItem('Export Backup', 'Local .aerobackup file', Icons.download, onTap: () => showDialog(context: context, builder: (_) => const BackupExportDialog())),
                        _SettingsItem('Import Backup', 'Restore from local storage', Icons.upload, onTap: () => showDialog(context: context, builder: (_) => const BackupImportDialog())),
                        _SettingsItem('Auto-Backup Schedule', 'Daily / Weekly / Monthly', Icons.schedule, onTap: () => showDialog(context: context, builder: (_) => const BackupScheduleDialog())),
                        _SettingsItem('Dropbox Backup', 'Connect / Frequency', Icons.cloud_done_outlined, onTap: () => context.push('/settings/backup/dropbox')),
                        _SettingsItem('Telegram Self-Backup', 'Save to Saved Messages', Icons.telegram, onTap: () => showDialog(context: context, builder: (_) => const TelegramSelfBackupDialog())),
                      ],
                    ),
                    _buildSettingsGroup(
                      'Upload & Download',
                      Icons.swap_vert,
                      [
                        _buildDynamicItem('Parallel Threads', 'concurrent transfers', Icons.layers_outlined, 'parallel_threads', '3', () => showDialog(context: context, builder: (_) => const ParallelThreadsDialog())),
                        _buildDynamicItem('Bandwidth Limit', 'MB/s', Icons.speed, 'bandwidth_limit', 'Uncapped', () => showDialog(context: context, builder: (_) => const BandwidthLimitDialog())),
                        _buildDynamicItem('Auto-Retry Count', 'attempts before failing', Icons.replay, 'auto_retry_count', '3', () => showDialog(context: context, builder: (_) => const AutoRetryCountDialog())),
                        _buildDynamicItem('Default Upload Quality', 'quality', Icons.image_outlined, 'upload_quality', 'Original', () => showDialog(context: context, builder: (_) => const UploadQualityDialog())),
                      ],
                    ),
                    _buildSettingsGroup(
                      'Media & Previews',
                      Icons.perm_media_outlined,
                      [
                        _buildDynamicItem('Thumbnail Cache Size', 'max storage limit', Icons.sd_storage_outlined, 'thumbnail_cache_size', '1GB', () => showDialog(context: context, builder: (_) => const ThumbnailCacheSizeDialog())),
                        _SettingsItem('Clear Thumbnail Cache', 'Free up local space', Icons.cleaning_services_outlined, onTap: () => showDialog(context: context, builder: (_) => const ClearThumbnailCacheDialog())),
                        _buildDynamicItem('Video Player Default Quality', 'resolution', Icons.high_quality, 'video_player_quality', '1080p', () => showDialog(context: context, builder: (_) => const VideoPlayerQualityDialog())),
                        _SettingsSwitchItem('Pre-fetch on Folder Open', 'Load thumbnails immediately', Icons.bolt, 'prefetch_folder_open', false),
                      ],
                    ),
                    _buildSettingsGroup(
                      'Advanced Auto-Backup',
                      Icons.photo_camera_back,
                      [
                        _SettingsSwitchItem('Enable Auto-Backup', 'Master switch for background uploads', Icons.backup_outlined, 'master_autobackup_enabled', false),
                        _SettingsItem('Manage Tracked Folders', 'Active backup profiles', Icons.folder_special_outlined, onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageBackupFoldersScreen())).then((_) => ref.invalidate(settingsRepositoryProvider));
                        }),
                      ],
                    ),
                    _buildSettingsGroup(
                      'Notifications',
                      Icons.notifications_outlined,
                      [
                        _SettingsSwitchItem('Upload Complete', 'Notify when files finish uploading', Icons.upload_file, 'notify_upload_complete', true),
                        _SettingsSwitchItem('Download Complete', 'Notify when files finish downloading', Icons.download_done, 'notify_download_complete', true),
                        _SettingsSwitchItem('Share Link Accessed', 'Notify when someone views your link', Icons.link, 'notify_share_accessed', true),
                        _SettingsSwitchItem('Backup Complete', 'Notify when auto-backup finishes', Icons.backup, 'notify_backup_complete', true),
                      ],
                    ),
                    _buildSettingsGroup(
                      'Network',
                      Icons.network_check,
                      [
                        _SettingsSwitchItem('Proxy Settings', 'SOCKS5 / MTProto', Icons.router_outlined, 'proxy_enabled', false), // Keeping it simple for UI mapping
                      ],
                    ),
                    _buildSettingsGroup(
                      'Appearance',
                      Icons.palette,
                      [
                        _SettingsItem('Theme & Colors', 'Dark / Light, Accent, Icons', Icons.color_lens_outlined, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AppearanceSettingsScreen()))),
                      ],
                    ),
                    _buildSettingsGroup(
                      'Advanced',
                      Icons.build_circle_outlined,
                      [
                        _SettingsItem('Export Logs', 'Save debugging info', Icons.bug_report_outlined, onTap: () => context.push('/diagnostics')),
                        _SettingsItem('Database Stats', 'File count, DB size, Channel usage', Icons.data_usage, onTap: () => showDialog(context: context, builder: (_) => const DatabaseStatsDialog())),
                        _SettingsItem('Rebuild Drive', 'Zero-DB Recovery from Telegram captions', Icons.build_outlined, onTap: () => showDialog(context: context, barrierDismissible: false, builder: (_) => const RebuildDriveDialog())),
                        _SettingsItem('Clear Local Cache', 'Wipes all temporary files', Icons.delete_sweep_outlined, onTap: () => showDialog(context: context, builder: (_) => const ClearCacheDialog())),
                        _SettingsItem('Reset All Settings', 'Revert to defaults', Icons.restore, onTap: () => showDialog(context: context, builder: (_) => const ResetSettingsDialog())),
                        _SettingsItem('Open Source Licenses', 'View dependencies', Icons.policy, onTap: () => showLicensePage(context: context, applicationName: 'AeroDrive', applicationVersion: '1.0.0-alpha')),
                      ],
                    ),
                    _buildSettingsGroup(
                      'About',
                      Icons.info_outline,
                      [
                        _SettingsItem('About AeroDrive', 'Version, Developer, Links', Icons.new_releases_outlined, onTap: () => context.push('/settings/about')),
                      ],
                    ),
                    _buildSettingsGroup(
                      'AI Intelligence',
                      Icons.psychology_outlined,
                      [
                        _SettingsSwitchItem('Power User Mode', 'Run AI processing on battery (drains battery faster)', Icons.battery_alert, 'ai_power_user', false),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildLogoutButton(),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search settings...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                suffixIcon: _searchQuery.isNotEmpty 
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.white70),
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
        ),
      ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.2, end: 0),
    );
  }

  Widget _buildSettingsGroup(String title, IconData icon, List<dynamic> items) {
    // Filter items based on search query
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
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12.0, bottom: 12.0),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: AppColors.primary,
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
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Column(
                  children: List.generate(filteredItems.length, (index) {
                    final item = filteredItems[index];
                    Widget child;
                    if (item is _SettingsItem) {
                      child = _buildTile(item.title, item.subtitle, item.icon, item.onTap);
                    } else if (item is _SettingsSwitchItem) {
                      child = _buildSwitchTile(item.title, item.subtitle, item.icon, item.settingKey, item.defaultValue);
                    } else if (item is _DynamicItemBuilder) {
                      child = item.build(context, ref);
                    } else {
                      child = const SizedBox.shrink();
                    }

                    return Column(
                      children: [
                        child,
                        if (index < filteredItems.length - 1)
                          Divider(height: 1, color: Colors.white.withOpacity(0.05), indent: 56),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ),
        ],
      ).animate().fadeIn(duration: 500.ms).slideX(begin: 0.1, end: 0),
    );
  }

  Widget _buildTile(String title, String subtitle, IconData icon, VoidCallback? onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        highlightColor: Colors.white.withOpacity(0.05),
        splashColor: Colors.white.withOpacity(0.1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: Colors.white.withOpacity(0.3)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchTile(String title, String subtitle, IconData icon, String settingKey, bool defaultValue) {
    return Consumer(builder: (context, ref, _) {
      return FutureBuilder<String?>(
        future: ref.watch(settingsRepositoryProvider).getSetting(settingKey),
        builder: (context, snapshot) {
          final isEnabled = snapshot.data == null ? defaultValue : snapshot.data == 'true';
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                await ref.read(settingsRepositoryProvider).setSetting(settingKey, (!isEnabled) ? 'true' : 'false');
                ref.invalidate(settingsRepositoryProvider);
              },
              highlightColor: Colors.white.withOpacity(0.05),
              splashColor: Colors.white.withOpacity(0.1),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.white)),
                          const SizedBox(height: 2),
                          Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13)),
                        ],
                      ),
                    ),
                    CupertinoSwitch(
                      value: isEnabled,
                      activeColor: AppColors.primary,
                      onChanged: (val) async {
                        await ref.read(settingsRepositoryProvider).setSetting(settingKey, val ? 'true' : 'false');
                        ref.invalidate(settingsRepositoryProvider);
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      );
    });
  }

  _DynamicItemBuilder _buildDynamicItem(String title, String subtitleSuffix, IconData icon, String settingKey, String defaultValue, VoidCallback action) {
    return _DynamicItemBuilder(
      title: title,
      builder: (context, ref) {
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
            });
          }
        );
      }
    );
  }

  Widget _buildLogoutButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: InkWell(
            onTap: () => ref.read(telegramServiceProvider.notifier).logOut(),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.1),
                border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout, color: Colors.redAccent.shade100),
                  const SizedBox(width: 8),
                  Text('Sign Out', style: TextStyle(color: Colors.redAccent.shade100, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
            ),
          ),
        ),
      ),
    ).animate().fadeIn(delay: 300.ms, duration: 400.ms);
  }
}

class _SettingsItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  _SettingsItem(this.title, this.subtitle, this.icon, {required this.onTap});
}

class _SettingsSwitchItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final String settingKey;
  final bool defaultValue;

  _SettingsSwitchItem(this.title, this.subtitle, this.icon, this.settingKey, this.defaultValue);
}

class _DynamicItemBuilder {
  final String title;
  final Widget Function(BuildContext context, WidgetRef ref) builder;

  _DynamicItemBuilder({required this.title, required this.builder});
  
  Widget build(BuildContext context, WidgetRef ref) => builder(context, ref);
}
