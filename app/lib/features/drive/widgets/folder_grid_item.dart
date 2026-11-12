import 'dart:math';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/db/database.dart';
import '../../../domain/activity/activity_service.dart';
import '../../../domain/drive_operations_service.dart';
import '../../../domain/folder_download_service.dart';
import '../providers/drive_providers.dart';
import '../../../domain/sync/config_sync_service.dart';
import 'folder_picker_dialog.dart';
import '../../security/biometric_auth_service.dart';
import '../../sharing/share_dialog.dart';
import 'file_info_inspector.dart';
import 'rename_item_dialog.dart';

class FolderGridItem extends ConsumerStatefulWidget {
  const FolderGridItem({super.key, required this.folder});
  final FolderData folder;

  @override
  ConsumerState<FolderGridItem> createState() => _FolderGridItemState();
}

class _FolderGridItemState extends ConsumerState<FolderGridItem> {
  bool _isHovered = false;
  Offset? _tapPosition;

  Color _getFolderColor() => AppColors.resolveFolderColor(widget.folder.color);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final folderColor = _getFolderColor();
    final isSelectionMode = ref.watch(isSelectionModeProvider);
    final selectedItems = ref.watch(selectedItemsProvider);
    final isSelected = selectedItems.contains(widget.folder.id);

    final itemsCountAsync = ref.watch(folderItemsCountProvider(widget.folder.id));
    final itemsCountText = itemsCountAsync.when(
      data: (count) => '$count item${count == 1 ? "" : "s"}',
      loading: () => '...',
      error: (_, _) => '0 items',
    );

    final sizeAsync = ref.watch(folderSizeProvider(widget.folder.id));
    final sizeText = sizeAsync.when(
      data: _formatFolderBadgeSize,
      loading: () => '',
      error: (_, _) => '',
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (details) {
          _tapPosition = details.globalPosition;
        },
        onTap: () async {
          ref.read(selectedFolderForInspectorProvider.notifier).state = widget.folder;
          ref.read(selectedFileForInspectorProvider.notifier).state = null;
          if (isSelectionMode) {
            _toggleSelection();
          } else {
            if (widget.folder.isVault) {
              final auth = ref.read(biometricAuthServiceProvider);
              final ok = await auth.authenticate(localizedReason: 'Authenticate to access Secure Vault');
              if (!ok) return;
            }
            final current = ref.read(currentFolderIdProvider);
            ref.read(navigationStackProvider.notifier).update((state) => [...state, current]);
            ref.read(currentFolderIdProvider.notifier).state = widget.folder.id;

            final loc = GoRouterState.of(context).uri.path;
            if (loc.startsWith('/search')) {
              context.go('/drive');
            }
          }
        },
        onLongPress: () {
          if (!isSelectionMode && _tapPosition != null) {
            _showGridContextMenu(context, _tapPosition!);
          } else {
            _toggleSelection();
          }
        },
        onSecondaryTapDown: (details) {
          _tapPosition = details.globalPosition;
        },
        onSecondaryTap: () {
          if (!isSelectionMode && _tapPosition != null) {
            _showGridContextMenu(context, _tapPosition!);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 68,
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.surfaceVariant
                : (_isHovered ? AppColors.surfaceVariant.withValues(alpha: 0.6) : AppColors.surface),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : (_isHovered
                          ? AppColors.outline
                          : AppColors.outline.withValues(alpha: 0.5))),
              width: isSelected ? 1.5 : 1.0,
            ),
            boxShadow: AppColors.cardShadow,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              // Left: Theme-Adaptive Duotone Folder Icon (with optional Vault badge)
              Stack(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: folderColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.folder_rounded,
                        size: 26,
                        color: folderColor,
                      ),
                    ),
                  ),
                  if (!widget.folder.isEncrypted)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.bolt_rounded, size: 10, color: Color(0xFFF59E0B)),
                      ),
                    )
                  else if (widget.folder.isVault)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.lock_rounded, size: 10, color: folderColor),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),

              // Center: Folder Name & Metadata Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.folder.name,
                      style: TextStyle(
                        color: AppColors.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sizeText.isNotEmpty ? '$itemsCountText • $sizeText' : itemsCountText,
                      style: TextStyle(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Right: Selection Checkbox or Context Menu
              if (isSelectionMode)
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: isSelected ? colorScheme.primary : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? colorScheme.primary : AppColors.outline,
                      width: 1.5,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 13, color: Colors.white)
                      : null,
                )
              else
                IconButton(
                  onPressed: () {
                    final isMobile = MediaQuery.of(context).size.width < 600;
                    if (isMobile) {
                      FileInfoInspector.showModal(context, ref, folder: widget.folder);
                    } else if (_tapPosition != null) {
                      _showGridContextMenu(context, _tapPosition!);
                    }
                  },
                  icon: Icon(
                    Icons.more_vert_rounded,
                    size: 18,
                    color: AppColors.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                  splashRadius: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionsMenu(BuildContext context) => Theme(
        data: Theme.of(context).copyWith(
          popupMenuTheme: PopupMenuThemeData(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
            ),
          ),
        ),
        child: PopupMenuButton<String>(
          icon: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isHovered ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08) : Colors.transparent,
            ),
            child: Icon(
              Icons.more_vert_rounded,
              size: 16,
              color: _isHovered
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
          tooltip: 'Folder options',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onSelected: (value) async {
            if (value == 'download') {
              FolderTreeHelper.confirmAndDownloadFolder(context: context, ref: ref, folder: widget.folder);
            } else if (value == 'rename') {
              _showRenameDialog(context);
            } else if (value == 'color') {
              _showColorPickerDialog(context);
            } else if (value == 'share') {
              showDialog(
                context: context,
                builder: (ctx) => ShareDialog(folder: widget.folder),
              );
            } else if (value == 'info') {
              _showInfoDialog(context);
            } else if (value == 'delete') {
              _showDeleteConfirm(context);
            } else if (value == 'move') {
              _showMoveDialog(context);
            } else if (value == 'copy') {
              _showCopyDialog(context);
            } else if (value == 'star') {
              _toggleFavorite();
            } else if (value == 'toggle_encryption') {
              await ref.read(folderRepositoryProvider).updateFolder(
                widget.folder.id,
                isEncrypted: !widget.folder.isEncrypted,
              );
              ref.read(dbRebuildVersionProvider.notifier).update((v) => v + 1);
            }
          },
          itemBuilder: (context) {
            final theme = Theme.of(context);
            return [
              PopupMenuItem(
                value: 'download',
                child: Row(
                  children: [
                    Icon(Icons.download_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Text('Download Folder', style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Text('Rename', style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'color',
                child: Row(
                  children: [
                    Icon(Icons.palette_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Text('Change Color', style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'toggle_encryption',
                child: Row(
                  children: [
                    Icon(
                      widget.folder.isEncrypted ? Icons.bolt_rounded : Icons.lock_outline_rounded,
                      size: 16,
                      color: widget.folder.isEncrypted ? const Color(0xFFF59E0B) : const Color(0xFF3B82F6),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      widget.folder.isEncrypted ? 'Fast Native Mode' : 'Encrypted Mode',
                      style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'star',
                child: Row(
                  children: [
                    Icon(
                      widget.folder.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 16,
                      color: widget.folder.isFavorite ? const Color(0xFFFFC107) : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      widget.folder.isFavorite ? 'Remove Star' : 'Star Folder',
                      style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Text('Share', style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'copy',
                child: Row(
                  children: [
                    Icon(Icons.copy_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Text('Copy to...', style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'move',
                child: Row(
                  children: [
                    Icon(Icons.drive_file_move_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Text('Move to...', style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'info',
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Text('Info / Details', style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.error),
                    const SizedBox(width: 10),
                    Text('Delete', style: TextStyle(color: AppColors.error, fontSize: 13)),
                  ],
                ),
              ),
            ];
          },
        ),
      );

  Future<void> _showColorPickerDialog(BuildContext context) async {
    String selectedHex = widget.folder.color ?? '0xFF60A5FA';
    final confirmed = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.palette_outlined, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Text('Folder Color', style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose a color for "${widget.folder.name}":',
                style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: AppColors.folderColors.entries.map((entry) {
                  final hex = '0x${entry.value.toARGB32().toRadixString(16).toUpperCase()}';
                  final isSelected = selectedHex.toUpperCase() == hex.toUpperCase() ||
                      selectedHex.toUpperCase() == entry.value.toARGB32().toRadixString(16).toUpperCase();
                  return InkWell(
                    onTap: () {
                      setDialogState(() {
                        selectedHex = hex;
                      });
                    },
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: entry.value,
                        boxShadow: [
                          if (isSelected)
                            BoxShadow(
                              color: entry.value.withValues(alpha: 0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                        ],
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: isSelected ? 3 : 1,
                        ),
                      ),
                      child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: Text('Cancel', style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, selectedHex),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != null) {
      final db = ref.read(databaseProvider);
      await (db.update(db.folders)..where((f) => f.id.equals(widget.folder.id))).write(
        FoldersCompanion(
          color: drift.Value(confirmed),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );
      ref.read(dbRebuildVersionProvider.notifier).state++;
    }
  }

  void _showInfoDialog(BuildContext context) {
    final sizeAsync = ref.read(folderSizeProvider(widget.folder.id));
    final itemsCountAsync = ref.read(folderItemsCountProvider(widget.folder.id));

    final sizeStr = sizeAsync.maybeWhen(
      data: _formatFolderSize,
      orElse: () => 'Calculating...',
    );
    final countStr = itemsCountAsync.maybeWhen(
      data: (c) => '$c item${c == 1 ? "" : "s"}',
      orElse: () => 'Calculating...',
    );

    final createdStr = widget.folder.createdAt != null
        ? DateFormat('MM/dd/yyyy hh:mm a').format(widget.folder.createdAt!)
        : 'Unknown';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.info_outline, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 10),
            Text('Folder Details', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow(context, 'Name', widget.folder.name),
            _buildInfoRow(context, 'Type', 'Folder'),
            _buildInfoRow(context, 'Contains', countStr),
            _buildInfoRow(context, 'Total Size', sizeStr),
            _buildInfoRow(context, 'Created', createdStr),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleFavorite() async {
    await ref.read(driveOperationsServiceProvider).toggleFolderFavorite(widget.folder.id);
  }

  void _toggleSelection() {
    ref.read(selectedItemsProvider.notifier).update((s) {
      final next = {...s};
      if (next.contains(widget.folder.id)) {
        next.remove(widget.folder.id);
      } else {
        next.add(widget.folder.id);
      }
      if (next.isEmpty) {
        ref.read(isSelectionModeProvider.notifier).state = false;
      }
      return next;
    });
  }

  String _formatFolderSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _formatFolderBadgeSize(int bytes) {
    if (bytes <= 0) return '';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  Future<void> _showRenameDialog(BuildContext context) async {
    await showAeroDriveRenameDialog(context: context, ref: ref, folder: widget.folder);
  }

  Future<void> _showDeleteConfirm(BuildContext context) async {
    final db = ref.read(databaseProvider);
    final scan = await FolderTreeHelper.scanFolderTree(db, widget.folder);
    if (!mounted) return;

    final countWarning = (scan.totalFiles > 0 || scan.totalSubfolders > 0)
        ? '\n\nThis folder contains ${scan.totalFiles} file(s) and ${scan.totalSubfolders} subfolder(s). All contents will be moved to the Trash bin.'
        : '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Folder "${widget.folder.name}"?',
          style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to move "${widget.folder.name}" to Trash?$countWarning',
          style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.8), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Move to Trash'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final folderRepo = ref.read(folderRepositoryProvider);
      await folderRepo.trashFolder(widget.folder.id);
      await ref.read(activityServiceProvider).recordTrash(folder: widget.folder);
      ref.read(configSyncServiceProvider).syncConfigToChannel();
      ref.read(dbRebuildVersionProvider.notifier).state++;
    }
  }

  Future<void> _showMoveDialog(BuildContext context) async {
    final targetFolderId = await showDialog<String?>(
      context: context,
      builder: (ctx) => FolderPickerDialog(
        title: 'Move folder to...',
        excludeFolderId: widget.folder.id,
      ),
    );
    if (targetFolderId == null) return;

    final db = ref.read(databaseProvider);
    final String? folderId = targetFolderId == '__root__' ? null : targetFolderId;
    await (db.update(db.folders)..where((f) => f.id.equals(widget.folder.id))).write(
      FoldersCompanion(parentId: drift.Value(folderId)),
    );
    ref.read(dbRebuildVersionProvider.notifier).state++;
  }

  Future<void> _showCopyDialog(BuildContext context) async {
    final targetFolderId = await showDialog<String?>(
      context: context,
      builder: (ctx) => const FolderPickerDialog(title: 'Copy folder to...'),
    );
    if (targetFolderId == null) return;

    final db = ref.read(databaseProvider);
    final String? folderId = targetFolderId == '__root__' ? null : targetFolderId;

    await _copyFolderRecursive(widget.folder.id, folderId, db);
    ref.read(dbRebuildVersionProvider.notifier).state++;
  }

  Future<void> _copyFolderRecursive(String srcId, String? destParentId, AeroDriveDatabase db) async {
    final src = await (db.select(db.folders)..where((f) => f.id.equals(srcId))).getSingleOrNull();
    if (src == null) return;

    final newId = const Uuid().v4();
    await db.into(db.folders).insert(
      FoldersCompanion.insert(
        id: newId,
        name: src.name.contains(' (Copy)') ? src.name : '${src.name} (Copy)',
        parentId: drift.Value(destParentId),
        color: drift.Value(src.color),
        createdAt: drift.Value(DateTime.now()),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );

    final files = await (db.select(db.files)..where((f) => f.folderId.equals(srcId) & f.deletedAt.isNull())).get();
    for (final file in files) {
      final newFileId = const Uuid().v4();
      await db.into(db.files).insert(
        FilesCompanion.insert(
          id: newFileId,
          name: file.name,
          folderId: drift.Value(newId),
          size: drift.Value(file.size),
          mimeType: drift.Value(file.mimeType),
          sha256Hash: drift.Value(file.sha256Hash),
          createdAt: drift.Value(DateTime.now()),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );

      final chunks = await (db.select(db.chunks)..where((c) => c.fileId.equals(file.id))).get();
      for (final chunk in chunks) {
        await db.into(db.chunks).insert(
          ChunksCompanion.insert(
            id: const Uuid().v4(),
            fileId: drift.Value(newFileId),
            chunkIndex: drift.Value(chunk.chunkIndex),
            channelId: drift.Value(chunk.channelId),
            messageId: drift.Value(chunk.messageId),
            size: drift.Value(chunk.size),
            hash: drift.Value(chunk.hash),
          ),
        );
      }
    }

    final subs = await (db.select(db.folders)..where((f) => f.parentId.equals(srcId) & f.deletedAt.isNull())).get();
    for (final sub in subs) {
      await _copyFolderRecursive(sub.id, newId, db);
    }
  }

  void _showGridContextMenu(BuildContext context, Offset position) async {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Rect.fromLTWH(0, 0, overlay.size.width, overlay.size.height),
      ),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      items: [
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Text('Rename', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'color',
          child: Row(
            children: [
              Icon(Icons.palette_outlined, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Text('Change Color', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'star',
          child: Row(
            children: [
              Icon(
                widget.folder.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 16,
                color: widget.folder.isFavorite ? const Color(0xFFFFC107) : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Text(
                widget.folder.isFavorite ? 'Remove Star' : 'Star Folder',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'share',
          child: Row(
            children: [
              Icon(Icons.share_outlined, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Text('Share', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'copy',
          child: Row(
            children: [
              Icon(Icons.copy_rounded, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Text('Copy to...', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'move',
          child: Row(
            children: [
              Icon(Icons.drive_file_move_outlined, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Text('Move to...', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'info',
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Text('Info / Details', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'select',
          child: Row(
            children: [
              Icon(Icons.check_circle_outline_rounded, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Text('Select', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.error),
              const SizedBox(width: 10),
              Text('Delete', style: TextStyle(color: AppColors.error, fontSize: 13)),
            ],
          ),
        ),
      ],
    );

    if (value == null) return;

    if (value == 'rename') {
      _showRenameDialog(context);
    } else if (value == 'color') {
      _showColorPickerDialog(context);
    } else if (value == 'share') {
      showDialog(
        context: context,
        builder: (ctx) => ShareDialog(folder: widget.folder),
      );
    } else if (value == 'info') {
      _showInfoDialog(context);
    } else if (value == 'delete') {
      _showDeleteConfirm(context);
    } else if (value == 'move') {
      _showMoveDialog(context);
    } else if (value == 'copy') {
      _showCopyDialog(context);
    } else if (value == 'star') {
      _toggleFavorite();
    } else if (value == 'select') {
      ref.read(isSelectionModeProvider.notifier).state = true;
      ref.read(selectedItemsProvider.notifier).state = {widget.folder.id};
    }
  }
}
