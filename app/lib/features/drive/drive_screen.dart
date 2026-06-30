import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_selector/file_selector.dart';
import 'package:aerodrive/core/theme/app_colors.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:aerodrive/features/drive/providers/drive_providers.dart';
import 'package:aerodrive/domain/folder_scanner.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:go_router/go_router.dart';
import 'package:aerodrive/features/sharing/share_service.dart';
import 'package:aerodrive/features/sharing/import_link_dialog.dart';
import 'package:aerodrive/features/drive/widgets/quick_access_row.dart';
import 'package:aerodrive/features/drive/widgets/folder_grid_item.dart';
import 'package:aerodrive/features/drive/widgets/folder_list_item.dart';
import 'package:aerodrive/features/drive/widgets/file_list_item.dart';
import 'package:aerodrive/features/drive/widgets/file_grid_item.dart';
import 'package:aerodrive/features/drive/widgets/create_folder_dialog.dart';
import 'package:aerodrive/features/drive/widgets/folder_picker_dialog.dart';
import 'package:aerodrive/core/constants.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';

class DriveScreen extends ConsumerWidget {
  const DriveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentsAsync = ref.watch(folderContentsProvider);
    final currentFolderId = ref.watch(currentFolderIdProvider);
    final breadcrumbsAsync = ref.watch(breadcrumbsProvider);
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    final isMobile = MediaQuery.of(context).size.width < AppConstants.mobileBreakpoint;
    final isGridView = ref.watch(isGridViewProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(context, ref),
      body: DropTarget(
        onDragDone: (detail) async {
          final activeChannel = await ref.read(settingsRepositoryProvider).getSetting('active_channel_id');
          if (activeChannel == null && context.mounted) {
            _showNoChannelDialog(context);
            return;
          }
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

            return CustomScrollView(
              slivers: [
                if (isRoot) ...[
                  SliverToBoxAdapter(child: QuickAccessRow()),
                ],
                // Header (My Drive or Breadcrumb Path overview)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: isRoot
                              ? const Text(
                                  'My Drive',
                                  style: TextStyle(
                                    color: AppColors.onSurface,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              : breadcrumbsAsync.when(
                                  data: (breadcrumbs) => _buildPathOverview(context, ref, breadcrumbs, currentFolderId),
                                  loading: () => const SizedBox.shrink(),
                                  error: (_, __) => const SizedBox.shrink(),
                                ),
                        ),
                        Row(
                          children: [
                            _buildLayoutSelector(context, ref, isGridView),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () => _showSortBottomSheet(context, ref),
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
                          (context, index) => FileGridItem(file: files[index]),
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
                          (context, index) => FileListItem(file: files[index]),
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
            );
          },
        ),
      ),
      floatingActionButton: Container(
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
          onPressed: () => _showNewOptionsBottomSheet(context, ref, currentFolderId),
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('New', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      ),
      bottomNavigationBar: (isMobile && !isKeyboardVisible)
          ? const SizedBox(height: 80)
          : null,
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, WidgetRef ref) {
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
            onPressed: () => _handleCopySelected(context, ref, selectedItems),
          ),
          IconButton(
            icon: const Icon(Icons.drive_file_move_rounded, color: Colors.white),
            tooltip: 'Move',
            onPressed: () => _handleMoveSelected(context, ref, selectedItems),
          ),
          IconButton(
            icon: const Icon(Icons.delete_rounded, color: Colors.redAccent),
            tooltip: 'Delete',
            onPressed: () => _handleDeleteSelected(context, ref, selectedItems),
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

  Widget _buildPathOverview(BuildContext context, WidgetRef ref, List<FolderData> breadcrumbs, String? currentFolderId) {
    return SingleChildScrollView(
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
              padding: EdgeInsets.symmetric(horizontal: 4.0),
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
  }

  Future<void> _handleDeleteSelected(BuildContext context, WidgetRef ref, Set<String> selectedIds) async {
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

  Future<void> _handleMoveSelected(BuildContext context, WidgetRef ref, Set<String> selectedIds) async {
    // Open FolderPickerDialog
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

  Future<void> _handleCopySelected(BuildContext context, WidgetRef ref, Set<String> selectedIds) async {
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

  void _showNewOptionsBottomSheet(BuildContext context, WidgetRef ref, String? currentFolderId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            border: Border.all(color: AppColors.outline, width: 1),
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
                  onTap: () {
                    Navigator.pop(context);
                    showDialog(context: context, builder: (context) => const CreateFolderDialog());
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
                    if (activeChannel == null && context.mounted) {
                      _showNoChannelDialog(context);
                      return;
                    }
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
                    if (activeChannel == null && context.mounted) {
                      _showNoChannelDialog(context);
                      return;
                    }
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
        );
      },
    );
  }

  void _showSortBottomSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final activeSort = ref.watch(driveSortOptionProvider);
            return Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                border: Border.all(color: AppColors.outline, width: 1),
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
                      _buildSortCriteriaItem(context, ref, 'Name', DriveSortCriteria.name, activeSort, setModalState),
                      _buildSortCriteriaItem(context, ref, 'Date Modified', DriveSortCriteria.date, activeSort, setModalState),
                      _buildSortCriteriaItem(context, ref, 'Size', DriveSortCriteria.size, activeSort, setModalState),
                      _buildSortCriteriaItem(context, ref, 'Type', DriveSortCriteria.type, activeSort, setModalState),
                      
                      const Divider(color: Colors.white10),
                      // Sort Order
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Text('Order', style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      _buildSortOrderItem(context, ref, 'Ascending', DriveSortOrder.ascending, activeSort, setModalState),
                      _buildSortOrderItem(context, ref, 'Descending', DriveSortOrder.descending, activeSort, setModalState),
                      
                      const Divider(color: Colors.white10),
                      // Prioritize Type
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Text('Prioritize Category', style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      _buildSortCategoryItem(context, ref, 'None', DriveSortCategory.none, activeSort, setModalState),
                      _buildSortCategoryItem(context, ref, 'Images First', DriveSortCategory.images, activeSort, setModalState),
                      _buildSortCategoryItem(context, ref, 'Videos First', DriveSortCategory.videos, activeSort, setModalState),
                      _buildSortCategoryItem(context, ref, 'Documents First', DriveSortCategory.documents, activeSort, setModalState),
                      _buildSortCategoryItem(context, ref, 'Programs First', DriveSortCategory.programs, activeSort, setModalState),
                      _buildSortCategoryItem(context, ref, 'Others First', DriveSortCategory.others, activeSort, setModalState),
                      
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSortCriteriaItem(BuildContext context, WidgetRef ref, String label, DriveSortCriteria criteria, DriveSortOption activeSort, StateSetter setModalState) {
    return RadioListTile<DriveSortCriteria>(
      title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
      value: criteria,
      groupValue: activeSort.criteria,
      activeColor: AppColors.primary,
      onChanged: (val) {
        if (val != null) {
          ref.read(driveSortOptionProvider.notifier).state = activeSort.copyWith(criteria: val);
          setModalState(() {});
        }
      },
    );
  }

  Widget _buildSortOrderItem(BuildContext context, WidgetRef ref, String label, DriveSortOrder order, DriveSortOption activeSort, StateSetter setModalState) {
    return RadioListTile<DriveSortOrder>(
      title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
      value: order,
      groupValue: activeSort.order,
      activeColor: AppColors.primary,
      onChanged: (val) {
        if (val != null) {
          ref.read(driveSortOptionProvider.notifier).state = activeSort.copyWith(order: val);
          setModalState(() {});
        }
      },
    );
  }

  Widget _buildSortCategoryItem(BuildContext context, WidgetRef ref, String label, DriveSortCategory category, DriveSortOption activeSort, StateSetter setModalState) {
    return RadioListTile<DriveSortCategory>(
      title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
      value: category,
      groupValue: activeSort.categoryPriority,
      activeColor: AppColors.primary,
      onChanged: (val) {
        if (val != null) {
          ref.read(driveSortOptionProvider.notifier).state = activeSort.copyWith(categoryPriority: val);
          setModalState(() {});
        }
      },
    );
  }

  Widget _buildLayoutSelector(BuildContext context, WidgetRef ref, bool isGridView) {
    return Container(
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
            onTap: () => ref.read(isGridViewProvider.notifier).state = true,
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
            onTap: () => ref.read(isGridViewProvider.notifier).state = false,
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
  }

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
}
