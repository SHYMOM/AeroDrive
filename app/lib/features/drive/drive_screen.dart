import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cross_file/cross_file.dart';
import 'package:cryptography/cryptography.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:drift/drift.dart' as drift;
import 'package:file_picker/file_picker.dart';
import 'file_picker_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/logger.dart';
import '../../core/providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/providers/security_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/db/database.dart';
import '../../domain/channel_load_balancer.dart';
import '../../domain/folder_scanner.dart';
import '../../domain/recovery/recovery_scanner.dart';
import '../../domain/sync/config_sync_service.dart';
import '../sharing/share_service.dart';
import '../telegram/telegram_service.dart';
import '../transfers/transfers_screen.dart';
import '../transfers/widgets/global_progress_bar.dart';
import 'providers/drive_providers.dart';
import 'widgets/create_folder_dialog.dart';
import 'widgets/file_grid_item.dart';
import 'widgets/file_list_item.dart';
import 'widgets/folder_grid_item.dart';
import 'widgets/folder_list_item.dart';
import 'widgets/folder_picker_dialog.dart';
import 'widgets/quick_access_row.dart';
import 'widgets/channel_setup_wizard_dialog.dart';
import '../../widgets/sync_debug_overlay.dart';

class DriveScreen extends ConsumerStatefulWidget {
  const DriveScreen({super.key});

  @override
  ConsumerState<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends ConsumerState<DriveScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final settings = ref.read(settingsRepositoryProvider);
      
      // Load view mode preference
      final isGrid = await settings.getBoolSetting('is_grid_view', defaultValue: true);
      if (!mounted) return;
      ref.read(isGridViewProvider.notifier).state = isGrid;

      // Load sort options preference
      final criteriaStr = await settings.getSetting('sort_criteria') ?? 'name';
      final orderStr = await settings.getSetting('sort_order') ?? 'ascending';
      final categoryStr = await settings.getSetting('sort_category') ?? 'none';
      if (!mounted) return;

      final criteria = DriveSortCriteria.values.firstWhere((e) => e.name == criteriaStr, orElse: () => DriveSortCriteria.name);
      final order = DriveSortOrder.values.firstWhere((e) => e.name == orderStr, orElse: () => DriveSortOrder.ascending);
      final category = DriveSortCategory.values.firstWhere((e) => e.name == categoryStr, orElse: () => DriveSortCategory.none);

      ref.read(driveSortOptionProvider.notifier).state = DriveSortOption(
        criteria: criteria,
        order: order,
        categoryPriority: category,
      );

      AppLogger.info('DriveScreen: initState postFrameCallback. isAppUnlocked=${ref.read(isAppUnlockedProvider)}');
      if (mounted && ref.read(isAppUnlockedProvider)) {
        _runConfigAndSetupCheck();
      }
      
      // Cleanup any temp joined sharing channels that were left joined due to interruption
      ref.read(shareServiceProvider).cleanupInterruptedTempChannels();
      
      // Check for interrupted imports on startup
      _checkForInterruptedImports();
    });
  }

  Future<void> _showPromptDialog({
    required String title,
    required String message,
    required String buttonText,
    required Future<void> Function() onConfirm,
  }) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: Text(title, style: TextStyle(color: AppColors.onSurface)),
          content: Text(message, style: TextStyle(color: AppColors.onSurface)),
          actions: [
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                
                // Show a secondary loader while onConfirm is running
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (dialogCtx) => PopScope(
                    canPop: false,
                    child: AlertDialog(
                      backgroundColor: AppColors.surfaceElevated,
                      content: Row(
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(width: 20),
                          Expanded(child: Text('Processing...', style: TextStyle(color: AppColors.onSurface))),
                        ],
                      ),
                    ),
                  ),
                );
                
                try {
                  await onConfirm();
                } catch (e) {
                  AppLogger.error('Prompt action failed', e);
                }
                
                if (mounted) {
                   Navigator.of(context, rootNavigator: true).pop(); // dismiss loading dialog
                }
              },
              child: Text(buttonText),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runConfigAndSetupCheck() async {
    AppLogger.info('DriveScreen: _runConfigAndSetupCheck() started.');
    if (!mounted) return;

    final configService = ref.read(configSyncServiceProvider);
    final settingsRepo = ref.read(settingsRepositoryProvider);

    // Check if we've already checked config during this app session to avoid repeated checks
    final checked = ref.read(configCheckedProvider);
    AppLogger.info('DriveScreen: configChecked status = $checked');
    if (checked) return;

    // Ensure we show loading state in UI
    ref.read(configCheckedProvider.notifier).state = false;

    // Start check
    AppLogger.info('DriveScreen: Running checkConfigStatus...');
    ConfigStatus status;
    try {
      status = await configService.checkConfigStatus().timeout(const Duration(seconds: 15));
      AppLogger.info('DriveScreen: checkConfigStatus status returned = $status');
    } on TimeoutException {
      AppLogger.warning('Config check timed out after 15s — proceeding with local config');
      if (mounted) ref.read(configCheckedProvider.notifier).state = true;
      return;
    } catch (e) {
      AppLogger.error('Config check failed', e);
      if (mounted) ref.read(configCheckedProvider.notifier).state = true;
      return;
    }

    if (!mounted) return;

    final localChannels = await settingsRepo.getSetting('storage_channels_list');
    final hasLocalConfig = localChannels != null && localChannels.isNotEmpty && localChannels != '[]';
    AppLogger.info('DriveScreen: localConfig=$localChannels, hasLocalConfig=$hasLocalConfig');

    if (!hasLocalConfig && status != ConfigStatus.found_unrestored) {
      AppLogger.info('DriveScreen: No storage channels found on account. Launching ChannelSetupWizardDialog.');
      if (status == ConfigStatus.missing) {
        await configService.syncConfigToChannel();
      }
      if (mounted) {
        ref.read(configCheckedProvider.notifier).state = true;
        _showChannelSetupPrompt(context);
      }
      return;
    }

    if (status == ConfigStatus.missing) {
      if (hasLocalConfig) {
        AppLogger.info('DriveScreen: status is missing, hasLocalConfig is true. Showing recreated prompt.');
        // Prompt that config channel was deleted remotely and we are recreating it
        await _showPromptDialog(
          title: 'Configuration Channel Deleted',
          message: 'The secure configuration channel was deleted on Telegram. We will now recreate it and restore your sync configuration.',
          buttonText: 'Recreate Channel',
          onConfirm: () async {
            await configService.syncConfigToChannel();
          },
        );
      }
    } else if (status == ConfigStatus.missing_message) {
      if (hasLocalConfig) {
        AppLogger.info('DriveScreen: status is missing_message, hasLocalConfig is true. Showing resync prompt.');
        // Prompt that config message was deleted remotely
        await _showPromptDialog(
          title: 'Configuration Message Deleted',
          message: 'The configuration backup inside the channel was deleted. We will now re-encrypt and upload your local configuration.',
          buttonText: 'Re-sync Configuration',
          onConfirm: () async {
            await configService.syncConfigToChannel();
          },
        );
      }
    } else if (status == ConfigStatus.found_unrestored) {
      AppLogger.info('DriveScreen: status is found_unrestored. Auto-restoring configuration.');
      // Auto-restore configuration and run recovery
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogCtx) => PopScope(
            canPop: false,
            child: AlertDialog(
              backgroundColor: AppColors.surfaceElevated,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text('Restoring configuration from Telegram...', style: TextStyle(color: AppColors.onSurface)),
                ],
              ),
            ),
          ),
        );
      }

      final jsonConfig = await configService.restoreConfigFromChannel();
      if (jsonConfig != null) {
        try {
          final telegramService = ref.read(telegramServiceProvider.notifier);
          if (jsonConfig.startsWith('{')) {
            final Map<String, dynamic> configMap = jsonDecode(jsonConfig);
            final rawChannels = configMap['storage_channels_list'] as String? ?? '[]';
            final activeChannel = configMap['active_channel_id'] as String? ?? '';
            final publicShareChannelId = configMap['public_share_channel_id'] as String? ?? '';
            final publicShareChannelUsername = configMap['public_share_channel_username'] as String? ?? '';
            final publicShareChannelInvite = configMap['public_share_channel_invite'] as String? ?? '';

            // Verify channels exist before saving
            final List<dynamic> decoded = jsonDecode(rawChannels);
            final List<Map<String, dynamic>> verifiedChannels = [];
            for (final ch in decoded) {
              final id = ch['id'];
              if (id != null) {
                final int chatId = id is String ? int.parse(id) : id as int;
                try {
                  final chat = await telegramService.sendRequest({"@type": "getChat", "chat_id": chatId});
                  final adminCheck = await telegramService.checkAdminStatus(chatId);
                  if (adminCheck['is_admin'] == true) {
                    verifiedChannels.add({
                      'id': chatId,
                      'title': chat['title'] ?? ch['title'] ?? 'Verified Channel',
                      'accountId': ch['accountId'] ?? 'primary',
                    });
                  }
                } catch (e) {
                  AppLogger.warning('Channel $chatId does not exist: $e');
                }
              }
            }

            if (verifiedChannels.isNotEmpty) {
              await settingsRepo.setSetting('storage_channels_list', jsonEncode(verifiedChannels));
              
              // If active channel is verified, keep it, otherwise pick first verified
              if (activeChannel.isNotEmpty && verifiedChannels.any((c) => c['id'].toString() == activeChannel)) {
                await settingsRepo.setSetting('active_channel_id', activeChannel);
              } else {
                await settingsRepo.setSetting('active_channel_id', verifiedChannels.first['id'].toString());
              }

              if (publicShareChannelId.isNotEmpty) {
                await settingsRepo.setSetting('public_share_channel_id', publicShareChannelId);
              }
              if (publicShareChannelUsername.isNotEmpty) {
                await settingsRepo.setSetting('public_share_channel_username', publicShareChannelUsername);
              }
              if (publicShareChannelInvite.isNotEmpty) {
                await settingsRepo.setSetting('public_share_channel_invite', publicShareChannelInvite);
              }
              final tempJoined = configMap['temp_joined_sharing_channels'] as String? ?? '[]';
              await settingsRepo.setSetting('temp_joined_sharing_channels', tempJoined);

              // Run recovery
              final masterKey = ref.read(masterKeyProvider);
              if (masterKey != null) {
                await ref.read(recoveryServiceProvider).runDisasterRecovery(
                  masterKey: SecretKey(masterKey),
                );
                ref.read(dbRebuildVersionProvider.notifier).update((v) => v + 1);
                ref.invalidate(folderContentsProvider);
              }
            }
          } else {
            // Fallback for legacy simple channels format
            final List<dynamic> decoded = jsonDecode(jsonConfig);
            final List<Map<String, dynamic>> verifiedChannels = [];
            for (final ch in decoded) {
              final id = ch['id'];
              if (id != null) {
                final int chatId = id is String ? int.parse(id) : id as int;
                try {
                  final chat = await telegramService.sendRequest({"@type": "getChat", "chat_id": chatId});
                  final adminCheck = await telegramService.checkAdminStatus(chatId);
                  if (adminCheck['is_admin'] == true) {
                    verifiedChannels.add({
                      'id': chatId,
                      'title': chat['title'] ?? ch['title'] ?? 'Verified Channel',
                      'accountId': ch['accountId'] ?? 'primary',
                    });
                  }
                } catch (e) {
                  AppLogger.warning('Channel $chatId does not exist: $e');
                }
              }
            }

            if (verifiedChannels.isNotEmpty) {
              await settingsRepo.setSetting('storage_channels_list', jsonEncode(verifiedChannels));
              final firstChannelId = verifiedChannels.first['id'].toString();
              await settingsRepo.setSetting('active_channel_id', firstChannelId);

              // Run recovery
              final masterKey = ref.read(masterKeyProvider);
              if (masterKey != null) {
                await ref.read(recoveryServiceProvider).runDisasterRecovery(
                  masterKey: SecretKey(masterKey),
                );
                ref.read(dbRebuildVersionProvider.notifier).update((v) => v + 1);
                ref.invalidate(folderContentsProvider);
              }
            }
          }
        } catch (e) {
          AppLogger.error('Failed to auto-restore config details: $e');
        }
      }

      // Dismiss loading dialog
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    // Mark config check complete so main UI is displayed
    if (mounted) {
      ref.read(configCheckedProvider.notifier).state = true;
      // Also sync the Telegram folder structure to group all connected channels
      configService.syncTelegramFolder();
    }
  }

  void _showChannelSetupPrompt(BuildContext context) {
    ChannelSetupWizardDialog.show(
      context,
      onSetupCompleted: () {
        ref.read(configSyncServiceProvider).syncTelegramFolder();
        ref.invalidate(folderContentsProvider);
      },
    );
  }

  bool _checkSecurityAndChannel(BuildContext context, String? activeChannel, List<int>? masterKey) {
    if (activeChannel == null || activeChannel.isEmpty) {
      _showNoChannelDialog(context);
      return false;
    }
    if (masterKey == null) {
      _showEncryptionErrorDialog(context);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(isAppUnlockedProvider, (previous, next) async {
      AppLogger.info('DriveScreen: ref.listen(isAppUnlockedProvider) changed: previous=$previous, next=$next');
      if (next) {
        _runConfigAndSetupCheck();
      }
    });

    final isConfigChecked = ref.watch(configCheckedProvider);

    if (!isConfigChecked) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withValues(alpha: 0.1),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          blurRadius: 20,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                  SizedBox(height: 32),
                  Text(
                    'Initializing Secure Sync...',
                    style: TextStyle(
                      color: AppColors.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Establishing end-to-end encryption with Telegram.',
                    style: TextStyle(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const Align(
              alignment: Alignment.topCenter,
              child: SyncDebugOverlay(),
            ),
          ],
        ),
      );
    }

    final contentsAsync = ref.watch(folderContentsProvider);
    final currentFolderId = ref.watch(currentFolderIdProvider);
    final breadcrumbsAsync = ref.watch(breadcrumbsProvider);
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    final isMobile = MediaQuery.of(context).size.width < AppConstants.mobileBreakpoint;
    final isGridView = ref.watch(isGridViewProvider);
    final isFavoriteOnly = ref.watch(isFavoriteOnlyProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(context),
      body: DropTarget(
        onDragDone: (detail) async {
          final activeChannel = await ref.read(settingsRepositoryProvider).getSetting('active_channel_id');
          final masterKey = ref.read(masterKeyProvider);
          if (!_checkSecurityAndChannel(context, activeChannel, masterKey)) return;
          
          final scanner = ref.read(folderScannerProvider);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Processing ${detail.files.length} dropped items...')));
          }
          for (final XFile xfile in detail.files) {
            await scanner.scanAndQueueDirectory(xfile.path, currentFolderId);
          }
          ref.invalidate(folderContentsProvider);
        },
        onDragEntered: (_) {},
        child: contentsAsync.when(
          loading: () => Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Error: $err', style: TextStyle(color: AppColors.onSurface))),
          data: (contents) {
            final folders = contents['folders'] as List<FolderData>? ?? [];
            final files = contents['files'] as List<FileData>? ?? [];
            
            final isRoot = ref.watch(navigationStackProvider).isEmpty && currentFolderId == null;

            return RefreshIndicator(
              color: AppColors.primary,
              backgroundColor: AppColors.surfaceElevated,
              onRefresh: () async {
                if (!mounted) return;
                final masterKey = ref.read(masterKeyProvider);
                if (masterKey != null) {
                  await ref.read(recoveryServiceProvider).runDisasterRecovery(
                    masterKey: SecretKey(masterKey),
                  );
                }
                if (mounted) {
                  ref.invalidate(folderContentsProvider);
                }
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                if (isRoot && !isFavoriteOnly) ...[
                  SliverToBoxAdapter(child: QuickAccessRow()),
                ],
                // Header (My Drive or Breadcrumb Path overview)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: isFavoriteOnly
                              ? Row(
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.arrow_back, color: AppColors.onSurfaceVariant),
                                      onPressed: () => ref.read(isFavoriteOnlyProvider.notifier).state = false,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                    SizedBox(width: 12),
                                    Text('Favorites', style: TextStyle(color: AppColors.onSurface, fontSize: 16, fontWeight: FontWeight.w600)),
                                  ],
                                )
                              : isRoot
                                  ? Text(
                                      'My Drive',
                                      style: TextStyle(
                                        color: AppColors.onSurface,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    )
                                  : breadcrumbsAsync.when(
                                      data: (breadcrumbs) => _buildPathOverview(context, breadcrumbs, currentFolderId),
                                      loading: () => const SizedBox.shrink(),
                                      error: (_, _) => const SizedBox.shrink(),
                                    ),
                        ),
                        Row(
                          children: [
                            _buildLayoutSelector(context, isGridView),
                            SizedBox(width: 8),
                             IconButton(
                               onPressed: () => _showSortBottomSheet(context),
                               icon: Icon(Icons.sort, color: AppColors.onSurfaceVariant, size: 20),
                             ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: SizedBox(height: 16)),

                if (isGridView) ...[
                  // Grid Layout
                  if (folders.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Text(
                          'Folders',
                          style: TextStyle(
                            color: AppColors.onSurface.withValues(alpha: 0.7),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 2.6,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => FolderGridItem(folder: folders[index]),
                          childCount: folders.length,
                        ),
                      ),
                    ),
                  ],
                  if (folders.isNotEmpty && files.isNotEmpty)
                    SliverToBoxAdapter(child: SizedBox(height: 20)),
                  if (files.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Text(
                          'Files',
                          style: TextStyle(
                            color: AppColors.onSurface.withValues(alpha: 0.7),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.82,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => FileGridItem(file: files[index], siblings: files),
                          childCount: files.length,
                        ),
                      ),
                    ),
                  ],
                ] else ...[
                  // List Layout
                  if (folders.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Text(
                          'Folders',
                          style: TextStyle(
                            color: AppColors.onSurface.withValues(alpha: 0.7),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => FolderListItem(folder: folders[index]),
                          childCount: folders.length,
                        ),
                      ),
                    ),
                  ],
                  if (folders.isNotEmpty && files.isNotEmpty)
                    SliverToBoxAdapter(child: SizedBox(height: 16)),
                  if (files.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Text(
                          'Files',
                          style: TextStyle(
                            color: AppColors.onSurface.withValues(alpha: 0.7),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => FileListItem(file: files[index], siblings: files),
                          childCount: files.length,
                        ),
                      ),
                    ),
                  ],
                ],

                if (folders.isEmpty && files.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.folder_open, size: 64, color: AppColors.outline),
                          SizedBox(height: 16),
                          Text('No items', style: TextStyle(color: AppColors.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                SliverToBoxAdapter(child: SizedBox(height: 140)), // Padding for FAB
              ],
            ),
          );
          },
        ),
      ),
      floatingActionButton: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: LinearGradient(
            colors: [AppColors.primaryDark, AppColors.primaryLight],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.glowCyan,
              blurRadius: 12,
              offset: Offset(0, 4),
            )
          ],
        ),
        child: FloatingActionButton.extended(
          backgroundColor: Colors.transparent,
          elevation: 0,
          onPressed: () => _showNewOptionsBottomSheet(context, currentFolderId),
          icon: Icon(Icons.add, color: AppColors.onSurface),
          label: Text('New', style: TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      ),
      bottomNavigationBar: (isMobile && !isKeyboardVisible)
          ? const SizedBox(height: 80)
          : null,
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final isSelectionMode = ref.watch(isSelectionModeProvider);
    final selectedItems = ref.watch(selectedItemsProvider);

    if (isSelectionMode) {
      return AppBar(
        backgroundColor: AppColors.surfaceElevated,
        elevation: 4,
        leading: IconButton(
          icon: Icon(Icons.close, color: AppColors.onSurface),
          onPressed: () {
            ref.read(isSelectionModeProvider.notifier).state = false;
            ref.read(selectedItemsProvider.notifier).state = {};
          },
        ),
        title: Text(
          '${selectedItems.length} selected',
          style: TextStyle(color: AppColors.onSurface, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.download_rounded, color: AppColors.onSurface),
            tooltip: 'Download',
            onPressed: () => _handleDownloadSelected(context, selectedItems),
          ),
          IconButton(
            icon: Icon(Icons.copy_rounded, color: AppColors.onSurface),
            tooltip: 'Copy',
            onPressed: () => _handleCopySelected(context, selectedItems),
          ),
          IconButton(
            icon: Icon(Icons.drive_file_move_rounded, color: AppColors.onSurface),
            tooltip: 'Move',
            onPressed: () => _handleMoveSelected(context, selectedItems),
          ),
          IconButton(
            icon: const Icon(Icons.delete_rounded, color: Colors.redAccent),
            tooltip: 'Delete',
            onPressed: () => _handleDeleteSelected(context, selectedItems),
          ),
        ],
      );
    }

    final progressState = ref.watch(aggregateTransferProgressProvider);

    return AppBar(
      backgroundColor: AppColors.background,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.menu, color: AppColors.onSurface),
        onPressed: () {
          Scaffold.of(context).openDrawer();
        },
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_outlined, color: AppColors.primary, size: 28),
          SizedBox(width: 8),
          Text(
            'AeroDrive',
            style: TextStyle(
              color: AppColors.onSurface,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ],
      ),
      centerTitle: false,
      actions: [
        progressState.when(
          data: (data) {
            if (data['hasActive'] != true) return const SizedBox.shrink();
            final progress = data['progress'] as double;
            final upCount = data['uploads'] as int;
            final downCount = data['downloads'] as int;
            
            return InkWell(
              onTap: () => _showBackgroundTasksBottomSheet(context),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 2,
                        backgroundColor: AppColors.outlineVariant.withValues(alpha: 0.3),
                        valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      '${(progress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
        ),
        IconButton(
          icon: Icon(Icons.search, color: AppColors.onSurfaceVariant),
          onPressed: () => context.push('/search'),
        ),
      ],
    );
  }

  Widget _buildPathOverview(BuildContext context, List<FolderData> breadcrumbs, String? currentFolderId) {
    final isRootCurrent = currentFolderId == null;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              ref.read(navigationStackProvider.notifier).state = [];
              ref.read(currentFolderIdProvider.notifier).state = null;
            },
            child: Text(
              'My Drive',
              style: TextStyle(
                color: isRootCurrent ? AppColors.onSurface : AppColors.onSurfaceVariant.withValues(alpha: 0.6),
                fontSize: 14,
                fontWeight: isRootCurrent ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          for (final folder in breadcrumbs) ...[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.chevron_right, size: 14, color: AppColors.outline),
            ),
            GestureDetector(
              onTap: () {
                final index = breadcrumbs.indexOf(folder);
                final newStack = ref.read(navigationStackProvider).take(index + 1).toList();
                ref.read(navigationStackProvider.notifier).state = newStack;
                ref.read(currentFolderIdProvider.notifier).state = folder.id;
              },
              child: Text(
                folder.name,
                style: TextStyle(
                  color: folder.id == currentFolderId ? AppColors.onSurface : AppColors.onSurfaceVariant.withValues(alpha: 0.6),
                  fontSize: 14,
                  fontWeight: folder.id == currentFolderId ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleDownloadSelected(BuildContext context, Set<String> selectedIds) async {
    final db = ref.read(databaseProvider);
    final List<String> filesToDownload = [];
    
    for (final id in selectedIds) {
      final isFolder = await (db.select(db.folders)..where((f) => f.id.equals(id))).getSingleOrNull() != null;
      if (isFolder) {
        filesToDownload.addAll(await _getAllFileIdsInFolder(id, db));
      } else {
        filesToDownload.add(id);
      }
    }
    
    final uniqueFiles = filesToDownload.toSet();
    if (uniqueFiles.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No files found to download.'))
        );
      }
      return;
    }
    
    for (final fileId in uniqueFiles) {
      await db.into(db.transferQueue).insert(
        TransferQueueCompanion.insert(
          id: const Uuid().v4(),
          fileId: drift.Value(fileId),
          type: const drift.Value('DOWNLOAD_FILE'),
          status: const drift.Value('PENDING'),
          priority: const drift.Value(1),
          createdAt: drift.Value(DateTime.now()),
        )
      );
    }
    
    ref.read(isSelectionModeProvider.notifier).state = false;
    ref.read(selectedItemsProvider.notifier).state = {};
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Queued ${uniqueFiles.length} files for download.'))
      );
    }
  }

  Future<List<String>> _getAllFileIdsInFolder(String folderId, AeroDriveDatabase db) async {
    final List<String> fileIds = [];
    
    final files = await (db.select(db.files)
      ..where((f) => f.folderId.equals(folderId) & f.deletedAt.isNull())
    ).get();
    fileIds.addAll(files.map((f) => f.id));
    
    final subfolders = await (db.select(db.folders)
      ..where((f) => f.parentId.equals(folderId) & f.deletedAt.isNull())
    ).get();
    for (final sub in subfolders) {
      fileIds.addAll(await _getAllFileIdsInFolder(sub.id, db));
    }
    
    return fileIds;
  }

  Future<void> _handleDeleteSelected(BuildContext context, Set<String> selectedIds) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text('Delete Items', style: TextStyle(color: AppColors.onSurface)),
        content: Text('Are you sure you want to delete these ${selectedIds.length} items?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    final folderRepo = ref.read(folderRepositoryProvider);
    final fileRepo = ref.read(fileRepositoryProvider);
    final db = ref.read(databaseProvider);
    
    for (final id in selectedIds) {
      final isFolder = await (db.select(db.folders)..where((f) => f.id.equals(id))).getSingleOrNull() != null;
      if (isFolder) {
        await folderRepo.trashFolder(id);
      } else {
        await fileRepo.softDelete(id);
      }
    }
    
    ref.read(isSelectionModeProvider.notifier).state = false;
    ref.read(selectedItemsProvider.notifier).state = {};
    
    ref.read(dbRebuildVersionProvider.notifier).update((v) => v + 1);
    ref.invalidate(folderContentsProvider);
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted selected items.')));
    }
  }

  Future<void> _handleMoveSelected(BuildContext context, Set<String> selectedIds) async {
    final targetFolderId = await showDialog<String?>(
      context: context,
      builder: (context) => FolderPickerDialog(
        title: 'Move Items to...',
        excludeFolderId: selectedIds.length == 1 ? selectedIds.first : null,
      ),
    );
    
    if (targetFolderId == null) return;
    
    final db = ref.read(databaseProvider);
    final String? folderId = targetFolderId == '__root__' ? null : targetFolderId;
    
    for (final id in selectedIds) {
      final isFolder = await (db.select(db.folders)..where((f) => f.id.equals(id))).getSingleOrNull() != null;
      if (isFolder) {
        await (db.update(db.folders)..where((f) => f.id.equals(id))).write(
          FoldersCompanion(parentId: drift.Value(folderId)),
        );
      } else {
        await (db.update(db.files)..where((f) => f.id.equals(id))).write(
          FilesCompanion(folderId: drift.Value(folderId)),
        );
      }
    }
    
    ref.read(isSelectionModeProvider.notifier).state = false;
    ref.read(selectedItemsProvider.notifier).state = {};
    ref.read(dbRebuildVersionProvider.notifier).update((v) => v + 1);
    ref.invalidate(folderContentsProvider);
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Moved selected items.')));
    }
  }

  Future<void> _handleCopySelected(BuildContext context, Set<String> selectedIds) async {
    final targetFolderId = await showDialog<String?>(
      context: context,
      builder: (context) => const FolderPickerDialog(title: 'Copy Items to...'),
    );
    
    if (targetFolderId == null) return;
    
    final db = ref.read(databaseProvider);
    final String? folderId = targetFolderId == '__root__' ? null : targetFolderId;
    
    for (final id in selectedIds) {
      final isFolder = await (db.select(db.folders)..where((f) => f.id.equals(id))).getSingleOrNull() != null;
      if (isFolder) {
        await _copyFolder(id, folderId, db);
      } else {
        await _copyFile(id, folderId, db);
      }
    }
    
    ref.read(isSelectionModeProvider.notifier).state = false;
    ref.read(selectedItemsProvider.notifier).state = {};
    ref.read(dbRebuildVersionProvider.notifier).update((v) => v + 1);
    ref.invalidate(folderContentsProvider);
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied selected items.')));
    }
  }

  Future<void> _copyFile(String fileId, String? targetFolderId, AeroDriveDatabase db) async {
    final file = await (db.select(db.files)..where((f) => f.id.equals(fileId))).getSingleOrNull();
    if (file == null) return;
    
    final newId = const Uuid().v4();
    await db.into(db.files).insert(
      FilesCompanion.insert(
        id: newId,
        name: file.name.contains(' (Copy)') ? file.name : '${file.name} (Copy)',
        folderId: drift.Value(targetFolderId),
        size: drift.Value(file.size),
        mimeType: drift.Value(file.mimeType),
        sha256Hash: drift.Value(file.sha256Hash),
        createdAt: drift.Value(DateTime.now()),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );
    
    final chunks = await (db.select(db.chunks)..where((c) => c.fileId.equals(fileId))).get();
    for (final chunk in chunks) {
      await db.into(db.chunks).insert(
        ChunksCompanion.insert(
          id: const Uuid().v4(),
          fileId: drift.Value(newId),
          chunkIndex: drift.Value(chunk.chunkIndex),
          channelId: drift.Value(chunk.channelId),
          messageId: drift.Value(chunk.messageId),
          size: drift.Value(chunk.size),
          hash: drift.Value(chunk.hash),
        ),
      );
    }
  }

  Future<void> _copyFolder(String folderId, String? targetParentId, AeroDriveDatabase db) async {
    final folder = await (db.select(db.folders)..where((f) => f.id.equals(folderId))).getSingleOrNull();
    if (folder == null) return;
    
    final newFolderId = const Uuid().v4();
    await db.into(db.folders).insert(
      FoldersCompanion.insert(
        id: newFolderId,
        name: folder.name.contains(' (Copy)') ? folder.name : '${folder.name} (Copy)',
        parentId: drift.Value(targetParentId),
        color: drift.Value(folder.color),
        createdAt: drift.Value(DateTime.now()),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );
    
    final files = await (db.select(db.files)..where((f) => f.folderId.equals(folderId) & f.deletedAt.isNull())).get();
    for (final file in files) {
      await _copyFile(file.id, newFolderId, db);
    }
    
    final subfolders = await (db.select(db.folders)..where((f) => f.parentId.equals(folderId) & f.deletedAt.isNull())).get();
    for (final sub in subfolders) {
      await _copyFolder(sub.id, newFolderId, db);
    }
  }

  void _showNewOptionsBottomSheet(BuildContext context, String? currentFolderId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            border: Border.all(color: AppColors.outline),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                SizedBox(height: 16),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text(
                        'Create or Upload',
                        style: TextStyle(
                          color: AppColors.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.outlineVariant.withValues(alpha: 0.3),
                    child: Icon(Icons.create_new_folder, color: AppColors.primary),
                  ),
                  title: Text('New Folder', style: TextStyle(color: AppColors.onSurface)),
                  onTap: () async {
                    Navigator.pop(context);
                    final settingsRepo = ref.read(settingsRepositoryProvider);
                    var activeChannel = await settingsRepo.getSetting('active_channel_id');
                    if (activeChannel == null || activeChannel.isEmpty) {
                      final channels = await ChannelLoadBalancer.getStorageChannels(settingsRepo);
                      if (channels.isNotEmpty) {
                        activeChannel = channels.first['id'].toString();
                        await settingsRepo.setSetting('active_channel_id', activeChannel);
                      }
                    }
                    final masterKey = ref.read(masterKeyProvider);
                    if (!_checkSecurityAndChannel(context, activeChannel, masterKey)) return;
                    
                    if (context.mounted) {
                      showDialog(context: context, builder: (context) => const CreateFolderDialog());
                    }
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.outlineVariant.withValues(alpha: 0.3),
                    child: Icon(Icons.upload_file, color: AppColors.secondary),
                  ),
                  title: Text('Upload Files', style: TextStyle(color: AppColors.onSurface)),
                  onTap: () async {
                    Navigator.pop(context);
                    final settingsRepo = ref.read(settingsRepositoryProvider);
                    var activeChannel = await settingsRepo.getSetting('active_channel_id');
                    if (activeChannel == null || activeChannel.isEmpty) {
                      final channels = await ChannelLoadBalancer.getStorageChannels(settingsRepo);
                      if (channels.isNotEmpty) {
                        activeChannel = channels.first['id'].toString();
                        await settingsRepo.setSetting('active_channel_id', activeChannel);
                      }
                    }
                    final masterKey = ref.read(masterKeyProvider);
                    if (!_checkSecurityAndChannel(context, activeChannel, masterKey)) return;
                    
                    try {
                      final paths = await pickFilesForUpload(allowMultiple: true);
                      if (paths.isNotEmpty) {
                        final scanner = ref.read(folderScannerProvider);
                        for (final path in paths) {
                          await scanner.scanAndQueueDirectory(path, currentFolderId);
                        }
                        ref.invalidate(folderContentsProvider);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${paths.length} file${paths.length > 1 ? "s" : ""} queued for upload.'),
                              backgroundColor: AppColors.primary,
                            ),
                          );
                        }
                      }
                    } catch (e, s) {
                      AppLogger.error('DriveScreen: Failed to select or queue files for upload', e, s);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Could not open selected file: $e'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    }
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.outlineVariant.withValues(alpha: 0.3),
                    child: Icon(Icons.drive_folder_upload, color: Colors.amber),
                  ),
                  title: Text('Upload Folder', style: TextStyle(color: AppColors.onSurface)),
                  onTap: () async {
                    Navigator.pop(context);
                    final settingsRepo = ref.read(settingsRepositoryProvider);
                    var activeChannel = await settingsRepo.getSetting('active_channel_id');
                    if (activeChannel == null || activeChannel.isEmpty) {
                      final channels = await ChannelLoadBalancer.getStorageChannels(settingsRepo);
                      if (channels.isNotEmpty) {
                        activeChannel = channels.first['id'].toString();
                        await settingsRepo.setSetting('active_channel_id', activeChannel);
                      }
                    }
                    final masterKey = ref.read(masterKeyProvider);
                    if (!_checkSecurityAndChannel(context, activeChannel, masterKey)) return;
                    
                    // Request storage permission on Android before accessing folders
                    if (Platform.isAndroid) {
                      final status = await Permission.manageExternalStorage.request();
                      if (status.isDenied || status.isPermanentlyDenied) {
                        if (context.mounted) {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: AppColors.surfaceElevated,
                              title: Text('Storage Permission Required', style: TextStyle(color: AppColors.onSurface)),
                              content: Text(
                                'AeroDrive needs "Manage All Files" access to read and upload folders from your device.\n\n'
                                'Please grant this permission in your device Settings > Apps > AeroDrive > Permissions.',
                                style: TextStyle(color: AppColors.onSurface.withValues(alpha: 0.7)),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    const MethodChannel('com.aerodrive.aerodrive/settings')
                                        .invokeMethod('openManageAllFilesSettings');
                                  },
                                  child: const Text('Open Settings'),
                                ),
                              ],
                            ),
                          );
                        }
                        return;
                      }
                    }

                    String? directoryPath;
                    try {
                      directoryPath = await FilePicker.getDirectoryPath();
                    } catch (e) {
                      if (context.mounted) {
                        _showFolderSelectionError(context, e);
                      }
                    }
                    if (directoryPath != null) {
                      final scanner = ref.read(folderScannerProvider);
                      await scanner.scanAndQueueDirectory(directoryPath, currentFolderId);
                      ref.invalidate(folderContentsProvider);
                    }
                  },
                ),
                SizedBox(height: 16),
              ],
            ),
          ),
        ),
    );
  }

  void _showFolderSelectionError(BuildContext context, dynamic error) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text('Folder Selection Error', style: TextStyle(color: AppColors.onSurface)),
        content: Text(
          'Selecting folders in certain directories (like Downloads or Android/data) is not supported by Android\'s storage system.\n\n'
          'Please select a folder from another storage location (e.g. Device storage root or Documents).\n\n'
          'Error details: $error',
          style: TextStyle(color: AppColors.onSurface.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSortBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
          builder: (context, setModalState) {
            final activeSort = ref.watch(driveSortOptionProvider);
            return DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                border: Border.all(color: AppColors.outline),
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 8),
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.outline,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          'Sort options',
                          style: TextStyle(color: AppColors.onSurface, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Divider(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
                      
                      // Sort Criteria
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Text('Sort By', style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      _buildSortCriteriaItem(context, 'Name', DriveSortCriteria.name, activeSort, setModalState),
                      _buildSortCriteriaItem(context, 'Date Modified', DriveSortCriteria.date, activeSort, setModalState),
                      _buildSortCriteriaItem(context, 'Size', DriveSortCriteria.size, activeSort, setModalState),
                      _buildSortCriteriaItem(context, 'Type', DriveSortCriteria.type, activeSort, setModalState),
                      
                      Divider(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
                      // Sort Order
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Text('Order', style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      _buildSortOrderItem(context, 'Ascending', DriveSortOrder.ascending, activeSort, setModalState),
                      _buildSortOrderItem(context, 'Descending', DriveSortOrder.descending, activeSort, setModalState),
                      
                      Divider(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
                      // Prioritize Type
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Text('Prioritize Category', style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      _buildSortCategoryItem(context, 'None', DriveSortCategory.none, activeSort, setModalState),
                      _buildSortCategoryItem(context, 'Images First', DriveSortCategory.images, activeSort, setModalState),
                      _buildSortCategoryItem(context, 'Videos First', DriveSortCategory.videos, activeSort, setModalState),
                      _buildSortCategoryItem(context, 'Documents First', DriveSortCategory.documents, activeSort, setModalState),
                      _buildSortCategoryItem(context, 'Programs First', DriveSortCategory.programs, activeSort, setModalState),
                      _buildSortCategoryItem(context, 'Others First', DriveSortCategory.others, activeSort, setModalState),
                      
                      SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
    );
  }

  Widget _buildSortCriteriaItem(BuildContext context, String label, DriveSortCriteria criteria, DriveSortOption activeSort, StateSetter setModalState) => RadioListTile<DriveSortCriteria>(
      title: Text(label, style: TextStyle(color: AppColors.onSurface, fontSize: 14)),
      value: criteria,
      groupValue: activeSort.criteria,
      activeColor: AppColors.primary,
      onChanged: (val) async {
        if (val != null) {
          final newSort = activeSort.copyWith(criteria: val);
          ref.read(driveSortOptionProvider.notifier).state = newSort;
          setModalState(() {});
          await ref.read(settingsRepositoryProvider).setSetting('sort_criteria', val.name);
        }
      },
    );

  Widget _buildSortOrderItem(BuildContext context, String label, DriveSortOrder order, DriveSortOption activeSort, StateSetter setModalState) => RadioListTile<DriveSortOrder>(
      title: Text(label, style: TextStyle(color: AppColors.onSurface, fontSize: 14)),
      value: order,
      groupValue: activeSort.order,
      activeColor: AppColors.primary,
      onChanged: (val) async {
        if (val != null) {
          final newSort = activeSort.copyWith(order: val);
          ref.read(driveSortOptionProvider.notifier).state = newSort;
          setModalState(() {});
          await ref.read(settingsRepositoryProvider).setSetting('sort_order', val.name);
        }
      },
    );

  Widget _buildSortCategoryItem(BuildContext context, String label, DriveSortCategory category, DriveSortOption activeSort, StateSetter setModalState) => RadioListTile<DriveSortCategory>(
      title: Text(label, style: TextStyle(color: AppColors.onSurface, fontSize: 14)),
      value: category,
      groupValue: activeSort.categoryPriority,
      activeColor: AppColors.primary,
      onChanged: (val) async {
        if (val != null) {
          final newSort = activeSort.copyWith(categoryPriority: val);
          ref.read(driveSortOptionProvider.notifier).state = newSort;
          setModalState(() {});
          await ref.read(settingsRepositoryProvider).setSetting('sort_category', val.name);
        }
      },
    );

  Widget _buildLayoutSelector(BuildContext context, bool isGridView) => IconButton(
        icon: Icon(
          isGridView ? Icons.list_rounded : Icons.grid_view_rounded,
          size: 22,
          color: Theme.of(context).primaryColor,
        ),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        onPressed: () async {
          final newValue = !isGridView;
          ref.read(isGridViewProvider.notifier).state = newValue;
          await ref.read(settingsRepositoryProvider).setBoolSetting('is_grid_view', newValue);
        },
        tooltip: isGridView ? 'Switch to List view' : 'Switch to Grid view',
      );

  void _showNoChannelDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text('No Storage Channel', style: TextStyle(color: AppColors.onSurface)),
        content: Text(
          'Please set up your AeroDrive storage channels to start uploading and storing files.',
          style: TextStyle(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _showChannelSetupPrompt(context);
            },
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: const Text('Set Up Channels'),
          ),
        ],
      ),
    );
  }

  void _showEncryptionErrorDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text('Encryption Error', style: TextStyle(color: AppColors.onSurface)),
        content: Text(
          'Your encryption keys could not be initialized properly. Please try restarting the app or logging out and logging back in.',
          style: TextStyle(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _checkForInterruptedImports() async {
    final shareService = ref.read(shareServiceProvider);
    final interruptedTask = await shareService.getInterruptedImportTask();
    if (interruptedTask != null && mounted) {
      final totalSize = interruptedTask['totalSize'] as int? ?? 0;
      final bytesTransferred = interruptedTask['bytesTransferred'] as int? ?? 0;
      final remainingBytes = totalSize - bytesTransferred;
      
      final speedBytesPerSec = 1.5 * 1024 * 1024; // Default baseline
      final double totalTransferred = remainingBytes.toDouble() * 2;
      final double durationSec = speedBytesPerSec > 0 ? totalTransferred / speedBytesPerSec : 0;
      final int durationMin = (durationSec / 60).ceil();

      final resume = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: Text('Resume Interrupted Import', style: TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.bold)),
          content: Text(
            'An import of "${interruptedTask['name']}" was interrupted. '
            'Remaining: ${_formatBytes(remainingBytes)} (approx $durationMin min). '
            'Would you like to resume importing?',
            style: TextStyle(color: AppColors.onSurface.withValues(alpha: 0.7)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Discard', style: TextStyle(color: AppColors.onSurfaceVariant)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Resume', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (resume == true) {
        _resumeImport(interruptedTask['taskId'] as String);
      } else {
        await shareService.discardImportTask(interruptedTask['taskId'] as String);
      }
    }
  }

  Future<void> _resumeImport(String taskId) async {
    if (!mounted) return;
    
    // Show a loading progress indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(
                child: Text(
                  'Resuming import and copying chunks...',
                  style: TextStyle(color: AppColors.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      await ref.read(shareServiceProvider).resumeImport(taskId);
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // dismiss loading
        ref.invalidate(folderContentsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully completed resumed import.')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // dismiss loading
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surfaceElevated,
            title: Text('Resume Failed', style: TextStyle(color: AppColors.onSurface)),
            content: Text(e.toString(), style: TextStyle(color: AppColors.onSurface.withValues(alpha: 0.7))),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('OK', style: TextStyle(color: AppColors.primary)),
              )
            ],
          ),
        );
      }
    }
  }

  void _showBackgroundTasksBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final transfersAsync = ref.watch(transfersStreamProvider);
            return Container(
              padding: const EdgeInsets.all(16),
              height: MediaQuery.of(context).size.height * 0.5,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Background Tasks',
                        style: TextStyle(
                          color: AppColors.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          context.push('/transfers');
                        },
                        child: const Text('View All', style: TextStyle(color: Color(0xFF38BDF8))),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Expanded(
                    child: transfersAsync.when(
                      data: (list) {
                        final active = list.where((item) => item.transfer.status == 'PENDING' || item.transfer.status == 'PROCESSING').toList();
                        if (active.isEmpty) {
                          return Center(
                            child: Text(
                              'No active background tasks',
                              style: TextStyle(color: AppColors.onSurfaceVariant),
                            ),
                          );
                        }
                        return ListView.builder(
                          itemCount: active.length,
                          itemBuilder: (context, index) {
                            final item = active[index];
                            final isUpload = item.transfer.type == 'UPLOAD_FILE';
                            final progress = item.transfer.totalBytes != null && item.transfer.totalBytes! > 0
                                ? (item.transfer.bytesTransferred! / item.transfer.totalBytes!)
                                : 0.0;
                            
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: isUpload 
                                    ? AppColors.primary.withValues(alpha: 0.1) 
                                    : AppColors.secondary.withValues(alpha: 0.1),
                                child: Icon(
                                  isUpload ? Icons.cloud_upload : Icons.cloud_download,
                                  color: isUpload ? AppColors.primary : AppColors.secondary,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                item.file?.name ?? item.transfer.fileId ?? 'Unknown File',
                                style: TextStyle(color: AppColors.onSurface, fontSize: 13, fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    backgroundColor: AppColors.outlineVariant.withValues(alpha: 0.3),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      isUpload ? AppColors.primary : AppColors.secondary,
                                    ),
                                    minHeight: 4,
                                  ),
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                                onPressed: () async {
                                  final db = ref.read(databaseProvider);
                                  await (db.delete(db.transferQueue)..where((q) => q.id.equals(item.transfer.id))).go();
                                },
                              ),
                            );
                          },
                        );
                      },
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.redAccent))),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

