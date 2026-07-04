import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:drift/drift.dart' as drift;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/providers/security_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/db/database.dart';
import '../../domain/folder_scanner.dart';
import '../../domain/recovery/recovery_scanner.dart';
import '../../domain/sync/config_sync_service.dart';
import 'providers/drive_providers.dart';
import 'widgets/create_folder_dialog.dart';
import 'widgets/file_grid_item.dart';
import 'widgets/file_list_item.dart';
import 'widgets/folder_grid_item.dart';
import 'widgets/folder_list_item.dart';
import 'widgets/folder_picker_dialog.dart';
import 'widgets/quick_access_row.dart';

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

      final channelsStr = await settings.getSetting('storage_channels_list');
      if (!mounted) return;
      if (channelsStr == null || channelsStr.isEmpty || channelsStr == '[]') {
        if (mounted && ref.read(isAppUnlockedProvider)) {
          _checkConfigRoutine(); // Check for remote config before prompting if already unlocked
        }
      } else {
        ref.read(configCheckedProvider.notifier).state = true;
        if (mounted && ref.read(isAppUnlockedProvider)) {
          _checkAndRecreateConfigBackup();
        }
      }
    });
  }

  Future<void> _checkConfigRoutine() async {
    if (!mounted) return;
    
    // Check if we've already done this during this session
    final checked = ref.read(configCheckedProvider);
    if (checked) {
      _showChannelSetupPrompt(context);
      return;
    }
    
    ref.read(configCheckedProvider.notifier).state = true;
    
    // Show immediate loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(child: Text('Connecting securely...', style: TextStyle(color: Colors.white))),
            ],
          ),
        ),
      ),
    );
    
    final configService = ref.read(configSyncServiceProvider);
    final status = await configService.checkConfigStatus();
    
    if (!mounted) return;
    
    // Dismiss loading dialog
    Navigator.of(context, rootNavigator: true).pop();

    if (status == ConfigStatus.missing) {
      // Channel doesn't exist. Tell user we are creating it, then show setup prompt.
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: AppColors.surfaceElevated,
            title: const Text('Creating Sync Channel', style: TextStyle(color: Colors.white)),
            content: const Text(
              'We are creating a private Telegram channel named "AeroDrive Config" in your account. '
              'It will be placed in your Archive folder. This channel stores your storage configuration securely so you can sync across devices.\n\n'
              '⚠️ Please NEVER delete this channel, or you will lose your sync configuration!',
              style: TextStyle(color: AppColors.onSurface),
            ),
            actions: [
              FilledButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (dialogCtx) => const PopScope(
                      canPop: false,
                      child: AlertDialog(
                        backgroundColor: AppColors.surfaceElevated,
                        content: Row(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(width: 20),
                            Expanded(child: Text('Creating your secure channel...', style: TextStyle(color: Colors.white))),
                          ],
                        ),
                      ),
                    ),
                  );
                  
                  await configService.syncConfigToChannel();
                  
                  if (mounted) {
                    Navigator.of(context, rootNavigator: true).pop(); // safely close loading dialog
                    _showChannelSetupPrompt(context);
                  }
                },
                child: const Text('Create Config Channel'),
              ),
            ],
          ),
        ),
      );
    } else if (status == ConfigStatus.found_unrestored) {
      // Prompt to restore
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: const Text('Configuration Found', style: TextStyle(color: Colors.white)),
          content: const Text(
            'We found a previous storage configuration saved in your AeroDrive Config channel. '
            'Would you like to restore these channels and rebuild your database?',
            style: TextStyle(color: AppColors.onSurface),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _showChannelSetupPrompt(context);
              },
              child: const Text('Skip', style: TextStyle(color: Colors.white54)),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final jsonConfig = await configService.restoreConfigFromChannel();
                if (jsonConfig != null) {
                  await ref.read(settingsRepositoryProvider).setSetting('storage_channels_list', jsonConfig);
                  try {
                    final List<dynamic> decoded = jsonDecode(jsonConfig);
                    if (decoded.isNotEmpty) {
                      final firstChannelId = decoded.first['id'].toString();
                      await ref.read(settingsRepositoryProvider).setSetting('active_channel_id', firstChannelId);
                    }
                  } catch (e) {
                    debugPrint('Failed to auto-set active channel: $e');
                  }
                  // Trigger disaster recovery
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Restored config. Rebuilding database...'))
                    );
                  }
                  final masterKey = ref.read(masterKeyProvider);
                  if (masterKey != null) {
                     await ref.read(recoveryServiceProvider).runDisasterRecovery(
                       masterKey: SecretKey(masterKey),
                       onProgress: (scanned, recovered) {
                         debugPrint('Recovered $recovered items from $scanned messages');
                       }
                     );
                     ref.read(dbRebuildVersionProvider.notifier).update((v) => v + 1);
                     ref.invalidate(folderContentsProvider);
                     if (mounted) {
                       ScaffoldMessenger.of(context).showSnackBar(
                         const SnackBar(content: Text('Database rebuild complete!'))
                       );
                     }
                  }
                }
              },
              child: const Text('Restore & Rebuild'),
            ),
          ],
        ),
      );
    } else {
      _showChannelSetupPrompt(context);
    }
  }

  Future<void> _checkAndRecreateConfigBackup() async {
    try {
      final configService = ref.read(configSyncServiceProvider);
      final status = await configService.checkConfigStatus();
      if (!mounted) return;
      if (status == ConfigStatus.missing) {
        debugPrint('DriveScreen: Config channel was deleted remotely. Auto-recreating config channel backup...');
        await configService.syncConfigToChannel();
      }
    } catch (e) {
      debugPrint('DriveScreen: Failed to check or recreate config backup: $e');
    }
  }

  void _showChannelSetupPrompt(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Welcome to AeroDrive!', style: TextStyle(color: Colors.white)),
        content: const Text(
          'To start uploading and syncing your files securely, you need to connect at least one Telegram storage channel.',
          style: TextStyle(color: AppColors.onSurface),
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.push('/settings/channels');
            },
            child: const Text('Connect Storage Channels'),
          ),
        ],
      ),
    );
  }

  bool _checkSecurityAndChannel(BuildContext context, String? activeChannel, List<int>? masterKey) {
    if (activeChannel == null) {
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
      if (next) {
        final settings = ref.read(settingsRepositoryProvider);
        final channelsStr = await settings.getSetting('storage_channels_list');
        if (!mounted) return;
        final isConfigChecked = ref.read(configCheckedProvider);
        if (!isConfigChecked && (channelsStr == null || channelsStr.isEmpty || channelsStr == '[]')) {
          _checkConfigRoutine();
        } else if (channelsStr != null && channelsStr.isNotEmpty && channelsStr != '[]') {
          _checkAndRecreateConfigBackup();
        }
      }
    });

    final isConfigChecked = ref.watch(configCheckedProvider);

    if (!isConfigChecked) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
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
                child: const CircularProgressIndicator(color: AppColors.primary),
              ),
              const SizedBox(height: 32),
              const Text(
                'Initializing Secure Sync...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Establishing end-to-end encryption with Telegram.',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                ),
              ),
            ],
          ),
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
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.white))),
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
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: isFavoriteOnly
                              ? Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.arrow_back, color: AppColors.onSurfaceVariant),
                                      onPressed: () => ref.read(isFavoriteOnlyProvider.notifier).state = false,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                    const SizedBox(width: 12),
                                    const Text('Favorites', style: TextStyle(color: AppColors.onSurface, fontSize: 16, fontWeight: FontWeight.w600)),
                                  ],
                                )
                              : isRoot
                                  ? const Text(
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
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () => _showSortBottomSheet(context),
                              icon: const Icon(Icons.sort, color: AppColors.onSurfaceVariant, size: 20),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),

                if (isGridView) ...[
                  // Grid Layout
                  if (folders.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 0.82,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => FolderGridItem(folder: folders[index]),
                          childCount: folders.length,
                        ),
                      ),
                    ),
                  if (folders.isNotEmpty && files.isNotEmpty)
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  if (files.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 0.82,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => FileGridItem(file: files[index], siblings: files),
                          childCount: files.length,
                        ),
                      ),
                    ),
                ] else ...[
                  // List Layout
                  if (folders.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => FolderListItem(folder: folders[index]),
                          childCount: folders.length,
                        ),
                      ),
                    ),
                  if (folders.isNotEmpty && files.isNotEmpty)
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  if (files.isNotEmpty)
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

                if (folders.isEmpty && files.isEmpty)
                  const SliverFillRemaining(
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
                const SliverToBoxAdapter(child: SizedBox(height: 100)), // Padding for FAB
              ],
            ),
          );
          },
        ),
      ),
      floatingActionButton: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            colors: [AppColors.primaryDark, AppColors.primaryLight],
          ),
          boxShadow: const [
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
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('New', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
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
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () {
            ref.read(isSelectionModeProvider.notifier).state = false;
            ref.read(selectedItemsProvider.notifier).state = {};
          },
        ),
        title: Text(
          '${selectedItems.length} selected',
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded, color: Colors.white),
            tooltip: 'Copy',
            onPressed: () => _handleCopySelected(context, selectedItems),
          ),
          IconButton(
            icon: const Icon(Icons.drive_file_move_rounded, color: Colors.white),
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

    return AppBar(
      backgroundColor: AppColors.background,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.menu, color: AppColors.onSurface),
        onPressed: () {
          Scaffold.of(context).openDrawer();
        },
      ),
      title: const Row(
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
        IconButton(
          icon: const Icon(Icons.search, color: AppColors.onSurfaceVariant),
          onPressed: () => context.push('/search'),
        ),
      ],
    );
  }

  Widget _buildPathOverview(BuildContext context, List<FolderData> breadcrumbs, String? currentFolderId) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              ref.read(navigationStackProvider.notifier).state = [];
              ref.read(currentFolderIdProvider.notifier).state = null;
            },
            child: const Text(
              'My Drive',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          for (final folder in breadcrumbs) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.chevron_right, size: 16, color: AppColors.onSurfaceVariant),
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
                  color: folder.id == currentFolderId ? AppColors.onSurface : AppColors.primary,
                  fontSize: 14,
                  fontWeight: folder.id == currentFolderId ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ],
      ),
    );

  Future<void> _handleDeleteSelected(BuildContext context, Set<String> selectedIds) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Delete Items', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete these ${selectedIds.length} items?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
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
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            border: Border.all(color: AppColors.outline),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text(
                        'Create or Upload',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.white10,
                    child: Icon(Icons.create_new_folder, color: AppColors.primary),
                  ),
                  title: const Text('New Folder', style: TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.pop(context);
                    final activeChannel = await ref.read(settingsRepositoryProvider).getSetting('active_channel_id');
                    final masterKey = ref.read(masterKeyProvider);
                    if (!_checkSecurityAndChannel(context, activeChannel, masterKey)) return;
                    
                    if (context.mounted) {
                      showDialog(context: context, builder: (context) => const CreateFolderDialog());
                    }
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.white10,
                    child: Icon(Icons.upload_file, color: AppColors.secondary),
                  ),
                  title: const Text('Upload Files', style: TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.pop(context);
                    final activeChannel = await ref.read(settingsRepositoryProvider).getSetting('active_channel_id');
                    final masterKey = ref.read(masterKeyProvider);
                    if (!_checkSecurityAndChannel(context, activeChannel, masterKey)) return;
                    
                    final List<XFile> result = await openFiles();
                    if (result.isNotEmpty) {
                      final scanner = ref.read(folderScannerProvider);
                      for (final file in result) {
                        await scanner.scanAndQueueDirectory(file.path, currentFolderId);
                      }
                      ref.invalidate(folderContentsProvider);
                    }
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.white10,
                    child: Icon(Icons.drive_folder_upload, color: Colors.amber),
                  ),
                  title: const Text('Upload Folder', style: TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.pop(context);
                    final activeChannel = await ref.read(settingsRepositoryProvider).getSetting('active_channel_id');
                    final masterKey = ref.read(masterKeyProvider);
                    if (!_checkSecurityAndChannel(context, activeChannel, masterKey)) return;
                    
                    final String? directoryPath = await getDirectoryPath();
                    if (directoryPath != null) {
                      final scanner = ref.read(folderScannerProvider);
                      await scanner.scanAndQueueDirectory(directoryPath, currentFolderId);
                      ref.invalidate(folderContentsProvider);
                    }
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
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
                borderRadius: const BorderRadius.only(
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
                      const SizedBox(height: 8),
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          'Sort options',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Divider(color: Colors.white10),
                      
                      // Sort Criteria
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Text('Sort By', style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      _buildSortCriteriaItem(context, 'Name', DriveSortCriteria.name, activeSort, setModalState),
                      _buildSortCriteriaItem(context, 'Date Modified', DriveSortCriteria.date, activeSort, setModalState),
                      _buildSortCriteriaItem(context, 'Size', DriveSortCriteria.size, activeSort, setModalState),
                      _buildSortCriteriaItem(context, 'Type', DriveSortCriteria.type, activeSort, setModalState),
                      
                      const Divider(color: Colors.white10),
                      // Sort Order
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Text('Order', style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      _buildSortOrderItem(context, 'Ascending', DriveSortOrder.ascending, activeSort, setModalState),
                      _buildSortOrderItem(context, 'Descending', DriveSortOrder.descending, activeSort, setModalState),
                      
                      const Divider(color: Colors.white10),
                      // Prioritize Type
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Text('Prioritize Category', style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      _buildSortCategoryItem(context, 'None', DriveSortCategory.none, activeSort, setModalState),
                      _buildSortCategoryItem(context, 'Images First', DriveSortCategory.images, activeSort, setModalState),
                      _buildSortCategoryItem(context, 'Videos First', DriveSortCategory.videos, activeSort, setModalState),
                      _buildSortCategoryItem(context, 'Documents First', DriveSortCategory.documents, activeSort, setModalState),
                      _buildSortCategoryItem(context, 'Programs First', DriveSortCategory.programs, activeSort, setModalState),
                      _buildSortCategoryItem(context, 'Others First', DriveSortCategory.others, activeSort, setModalState),
                      
                      const SizedBox(height: 16),
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
      title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
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
      title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
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
      title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
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

  Widget _buildLayoutSelector(BuildContext context, bool isGridView) => Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () async {
              ref.read(isGridViewProvider.notifier).state = true;
              await ref.read(settingsRepositoryProvider).setBoolSetting('is_grid_view', true);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isGridView ? const Color(0xFF1E293B) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: isGridView 
                    ? Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.4))
                    : Border.all(color: Colors.transparent),
                boxShadow: isGridView ? [
                  BoxShadow(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                    blurRadius: 8,
                  )
                ] : null,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.grid_view_rounded,
                    size: 14,
                    color: isGridView ? const Color(0xFF38BDF8) : Colors.white60,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Grid',
                    style: TextStyle(
                      color: isGridView ? Colors.white : Colors.white60,
                      fontSize: 11,
                      fontWeight: isGridView ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: () async {
              ref.read(isGridViewProvider.notifier).state = false;
              await ref.read(settingsRepositoryProvider).setBoolSetting('is_grid_view', false);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: !isGridView ? const Color(0xFF1E293B) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: !isGridView 
                    ? Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.4))
                    : Border.all(color: Colors.transparent),
                boxShadow: !isGridView ? [
                  BoxShadow(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                    blurRadius: 8,
                  )
                ] : null,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.list_rounded,
                    size: 14,
                    color: !isGridView ? const Color(0xFF38BDF8) : Colors.white60,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'List',
                    style: TextStyle(
                      color: !isGridView ? Colors.white : Colors.white60,
                      fontSize: 11,
                      fontWeight: !isGridView ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

  void _showNoChannelDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('No Storage Channel', style: TextStyle(color: AppColors.onSurface)),
        content: const Text('Please select a Telegram channel in Settings before uploading.', style: TextStyle(color: AppColors.onSurfaceVariant)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: AppColors.primary)),
          )
        ],
      ),
    );
  }

  void _showEncryptionErrorDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Encryption Error', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Your encryption keys could not be initialized properly. Please try restarting the app or logging out and logging back in.',
          style: TextStyle(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
