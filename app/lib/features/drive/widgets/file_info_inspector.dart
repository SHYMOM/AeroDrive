import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/db/database.dart';
import '../../../domain/activity/activity_service.dart';
import '../../../domain/folder_download_service.dart';
import '../../gallery/thumbnail_service.dart';
import '../../sharing/share_dialog.dart';
import '../providers/drive_providers.dart';
import 'file_type_icon.dart';

enum InspectorTab { details, activity }

class FileInfoInspector extends ConsumerStatefulWidget {
  const FileInfoInspector({super.key, this.isModal = false});

  final bool isModal;

  static Future<void> showModal(BuildContext context, WidgetRef ref, {FileData? file, FolderData? folder}) async {
    ref.read(selectedFileForInspectorProvider.notifier).state = file;
    ref.read(selectedFolderForInspectorProvider.notifier).state = folder;
    
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _FileInfoBottomSheet(),
    );
  }

  @override
  ConsumerState<FileInfoInspector> createState() => _FileInfoInspectorState();
}

class _FileInfoInspectorState extends ConsumerState<FileInfoInspector> {
  InspectorTab _currentTab = InspectorTab.details;

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _handleDownload(FileData? file, FolderData? folder) async {
    if (file != null) {
      final db = ref.read(databaseProvider);
      const uuid = Uuid();
      await db.into(db.transferQueue).insert(
        TransferQueueCompanion.insert(
          id: uuid.v4(),
          type: const drift.Value('DOWNLOAD_FILE'),
          status: const drift.Value('PENDING'),
          priority: const drift.Value(1),
          totalBytes: drift.Value(file.size ?? 0),
          fileId: drift.Value(file.id),
          createdAt: drift.Value(DateTime.now()),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Queued "${file.name}" for download'),
            backgroundColor: AppColors.primary,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else if (folder != null) {
      await FolderTreeHelper.confirmAndDownloadFolder(
        context: context,
        ref: ref,
        folder: folder,
      );
    }
  }

  Future<void> _handleShare(FileData? file, FolderData? folder) async {
    if (file != null) {
      await ref.read(activityServiceProvider).recordShare(file: file);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => ShareDialog(file: file),
      );
    } else if (folder != null) {
      final db = ref.read(databaseProvider);
      final scan = await FolderTreeHelper.scanFolderTree(db, folder);
      if (!mounted) return;
      if (scan.totalFiles > 0 || scan.totalSubfolders > 0) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surfaceElevated,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.share_outlined, color: AppColors.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Share Folder "${folder.name}"?',
                    style: TextStyle(color: AppColors.onSurface, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Text(
              'Creating a share link for this folder will allow anyone with the link to access all ${scan.totalFiles} file(s) and ${scan.totalSubfolders} subfolder(s) contained within it.\n\nDo you want to proceed?',
              style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('Proceed to Share'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }
      await ref.read(activityServiceProvider).recordShare(folder: folder);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => ShareDialog(folder: folder),
      );
    }
  }

  Future<void> _handleToggleStar(FileData? file, FolderData? folder) async {
    final db = ref.read(databaseProvider);
    if (file != null) {
      final newFav = !file.isFavorite;
      await (db.update(db.files)..where((f) => f.id.equals(file.id))).write(
        FilesCompanion(isFavorite: drift.Value(newFav)),
      );
      ref.read(selectedFileForInspectorProvider.notifier).state =
          file.copyWith(isFavorite: newFav);
      ref.invalidate(folderContentsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newFav ? 'Starred "${file.name}"' : 'Unstarred "${file.name}"'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else if (folder != null) {
      final newFav = !folder.isFavorite;
      await (db.update(db.folders)..where((f) => f.id.equals(folder.id))).write(
        FoldersCompanion(isFavorite: drift.Value(newFav)),
      );
      ref.read(selectedFolderForInspectorProvider.notifier).state =
          folder.copyWith(isFavorite: newFav);
      ref.invalidate(folderContentsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newFav ? 'Starred "${folder.name}"' : 'Unstarred "${folder.name}"'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _handleDelete(FileData? file, FolderData? folder) async {
    if (file != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Delete "${file.name}"?',
            style: TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'This file will be moved to the Trash bin.',
            style: TextStyle(color: AppColors.onSurfaceVariant),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
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
        final fileRepo = ref.read(fileRepositoryProvider);
        await fileRepo.softDelete(file.id);
        await ref.read(activityServiceProvider).recordTrash(file: file);
        ref.read(selectedFileForInspectorProvider.notifier).state = null;
        ref.invalidate(folderContentsProvider);
        if (widget.isModal && mounted) {
          Navigator.pop(context);
        }
      }
    } else if (folder != null) {
      final db = ref.read(databaseProvider);
      final scan = await FolderTreeHelper.scanFolderTree(db, folder);
      if (!mounted) return;

      final countWarning = (scan.totalFiles > 0 || scan.totalSubfolders > 0)
          ? '\n\nThis folder contains ${scan.totalFiles} file(s) and ${scan.totalSubfolders} subfolder(s). All contents will be moved to Trash.'
          : '';

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Delete Folder "${folder.name}"?',
            style: TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Are you sure you want to move "${folder.name}" to the Trash bin?$countWarning',
            style: TextStyle(color: AppColors.onSurfaceVariant, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
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
        await folderRepo.trashFolder(folder.id);
        await ref.read(activityServiceProvider).recordTrash(folder: folder);
        ref.read(selectedFolderForInspectorProvider.notifier).state = null;
        ref.invalidate(folderContentsProvider);
        if (widget.isModal && mounted) {
          Navigator.pop(context);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedFile = ref.watch(selectedFileForInspectorProvider);
    final selectedFolder = ref.watch(selectedFolderForInspectorProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final name = selectedFile?.name ?? selectedFolder?.name ?? 'My Drive';
    final isRootDrive = selectedFile == null && selectedFolder == null;
    final isFolder = selectedFolder != null || isRootDrive;

    final isStarred = selectedFile?.isFavorite ?? selectedFolder?.isFavorite ?? false;

    // Real folder metadata if folder selected
    final folderItemsCountAsync = selectedFolder != null
        ? ref.watch(folderItemsCountProvider(selectedFolder.id))
        : null;
    final folderSizeAsync = selectedFolder != null
        ? ref.watch(folderSizeProvider(selectedFolder.id))
        : null;

    final folderItemsText = folderItemsCountAsync?.when(
          data: (count) => '$count item${count == 1 ? "" : "s"}',
          loading: () => '...',
          error: (_, _) => '0 items',
        ) ??
        '';

    final folderSizeBytes = folderSizeAsync?.valueOrNull ?? 0;
    final folderSizeFormatted = folderSizeBytes > 0 ? _formatBytes(folderSizeBytes) : '0 B';

    final subtitle = selectedFile != null
        ? '${_formatBytes(selectedFile.size ?? 0)} • ${selectedFile.mimeType?.split('/').last.toUpperCase() ?? "FILE"}'
        : (selectedFolder != null
            ? '$folderItemsText • $folderSizeFormatted'
            : 'Root Cloud Vault • End-to-End Encrypted');

    final folderColor = AppColors.resolveFolderColor(selectedFolder?.color);

    return Container(
      width: widget.isModal ? double.infinity : 300,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: widget.isModal
            ? null
            : Border(
                left: BorderSide(
                  color: AppColors.outline.withValues(alpha: 0.6),
                  width: 1,
                ),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: Title & Close Button ──────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  selectedFile != null
                      ? 'File Info'
                      : (selectedFolder != null ? 'Folder Info' : 'Drive Info'),
                  style: TextStyle(
                    color: AppColors.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                IconButton(
                  onPressed: () {
                    if (widget.isModal) {
                      Navigator.pop(context);
                    } else {
                      ref.read(isInspectorOpenProvider.notifier).state = false;
                    }
                  },
                  icon: Icon(
                    Icons.close_rounded,
                    color: AppColors.onSurfaceVariant,
                    size: 20,
                  ),
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                const SizedBox(height: 12),
                // ── Hero Preview (Sleek 88x88 container, subtle soft-tinted surface) ──
                Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: isFolder
                          ? (selectedFolder != null
                              ? folderColor.withValues(alpha: 0.12)
                              : AppColors.primary.withValues(alpha: 0.12))
                          : AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Center(
                      child: isFolder
                          ? Icon(
                              selectedFolder != null ? Icons.folder_rounded : Icons.cloud_done_rounded,
                              size: 46,
                              color: selectedFolder != null ? folderColor : AppColors.primary,
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: selectedFile!.mimeType?.startsWith('image/') == true
                                  ? FutureBuilder<File?>(
                                      future: ref.read(thumbnailServiceProvider).getThumbnail(selectedFile),
                                      builder: (context, snapshot) {
                                        if (snapshot.hasData && snapshot.data != null) {
                                          return Image.file(snapshot.data!, fit: BoxFit.cover, width: 88, height: 88);
                                        }
                                        return FileTypeIcon(mimeType: selectedFile.mimeType, fileName: selectedFile.name, size: 44);
                                      },
                                    )
                                  : FileTypeIcon(mimeType: selectedFile.mimeType, fileName: selectedFile.name, size: 44),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Name & Metadata Subtitle
                Center(
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── 4-Button Interactive Quick Action Row ──────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildActionButton(
                      icon: Icons.download_rounded,
                      label: 'Download',
                      color: AppColors.primary,
                      onTap: () => _handleDownload(selectedFile, selectedFolder),
                    ),
                    _buildActionButton(
                      icon: Icons.link_rounded,
                      label: 'Share',
                      color: AppColors.secondary,
                      onTap: () => _handleShare(selectedFile, selectedFolder),
                    ),
                    _buildActionButton(
                      icon: isStarred ? Icons.star_rounded : Icons.star_outline_rounded,
                      label: isStarred ? 'Starred' : 'Star',
                      color: isStarred ? const Color(0xFFF59E0B) : AppColors.onSurfaceVariant,
                      onTap: isRootDrive ? () {} : () => _handleToggleStar(selectedFile, selectedFolder),
                    ),
                    _buildActionButton(
                      icon: Icons.delete_outline_rounded,
                      label: 'Delete',
                      color: const Color(0xFFEF4444),
                      isDestructive: true,
                      onTap: isRootDrive ? () {} : () => _handleDelete(selectedFile, selectedFolder),
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // ── Segmented Pill Toggle (Info details | Activity) ──
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _currentTab = InspectorTab.details),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _currentTab == InspectorTab.details
                                  ? AppColors.surface
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: _currentTab == InspectorTab.details
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Center(
                              child: Text(
                                'Info details',
                                style: TextStyle(
                                  color: _currentTab == InspectorTab.details
                                      ? AppColors.onSurface
                                      : AppColors.onSurfaceVariant,
                                  fontSize: 12.5,
                                  fontWeight: _currentTab == InspectorTab.details
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _currentTab = InspectorTab.activity),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _currentTab == InspectorTab.activity
                                  ? AppColors.surface
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: _currentTab == InspectorTab.activity
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Center(
                              child: Text(
                                'Activity',
                                style: TextStyle(
                                  color: _currentTab == InspectorTab.activity
                                      ? AppColors.onSurface
                                      : AppColors.onSurfaceVariant,
                                  fontSize: 12.5,
                                  fontWeight: _currentTab == InspectorTab.activity
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // ── Tab Content ──────────────────────────────────────
                if (_currentTab == InspectorTab.details)
                  _buildDetailsContent(
                    selectedFile,
                    selectedFolder,
                    folderSizeFormatted: folderSizeFormatted,
                    folderItemsText: folderItemsText,
                  )
                else
                  _buildActivityContent(selectedFile, selectedFolder),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDestructive
        ? const Color(0xFFEF4444).withValues(alpha: isDark ? 0.14 : 0.08)
        : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9));
    final borderColor = isDestructive
        ? const Color(0xFFEF4444).withValues(alpha: 0.3)
        : AppColors.outline.withValues(alpha: 0.5);
    final iconColor = isDestructive ? const Color(0xFFEF4444) : color;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: borderColor,
                width: 1,
              ),
            ),
            child: Center(
              child: Icon(icon, color: iconColor, size: 20),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: isDestructive ? const Color(0xFFEF4444) : AppColors.onSurface,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsContent(
    FileData? file,
    FolderData? folder, {
    required String folderSizeFormatted,
    required String folderItemsText,
  }) {
    if (file == null && folder == null) {
      final totalBytesAsync = ref.watch(totalStorageProvider);
      final totalBytes = totalBytesAsync.valueOrNull ?? 0;
      final countsAsync = ref.watch(quickAccessStatsProvider);
      final counts = countsAsync.valueOrNull ?? {};
      final totalFiles = counts.values.fold<int>(0, (sum, val) => sum + val);

      return Column(
        children: [
          _buildMetaRow('Type', 'Root Cloud Vault'),
          _buildMetaRow('Storage Used', _formatBytes(totalBytes)),
          _buildMetaRow('Total Files', '$totalFiles indexed'),
          _buildMetaRow('Encryption', 'AES-256-GCM (Zero-Knowledge)'),
          _buildMetaRow('Cloud Provider', 'Telegram Cloud (TDLib)'),
          _buildMetaRow('Sync Protocol', 'Silent Background Revalidation'),
          _buildMetaRow('Status', 'Active & Protected'),
        ],
      );
    }

    final dateFormat = DateFormat('MMM d, yyyy  h:mm a');
    return Column(
      children: [
        _buildMetaRow('Type', file?.mimeType ?? (folder != null ? 'Folder' : 'Directory')),
        _buildMetaRow(
          'Size',
          file != null ? _formatBytes(file.size ?? 0) : folderSizeFormatted,
        ),
        if (folder != null)
          _buildMetaRow('Items', folderItemsText),
        _buildMetaRow(
          'Created',
          file?.createdAt != null
              ? dateFormat.format(file!.createdAt!)
              : (folder?.createdAt != null ? dateFormat.format(folder!.createdAt!) : '—'),
        ),
        _buildMetaRow('Encryption', 'AES-256-GCM'),
        _buildMetaRow('Storage', 'Telegram Cloud (TDLib)'),
        _buildMetaRow('Local Cache', 'Decrypted on-demand'),
      ],
    );
  }

  Widget _buildMetaRow(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            key,
            style: TextStyle(
              color: AppColors.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: AppColors.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityContent(FileData? file, FolderData? folder) {
    final eventsAsync = ref.watch(
      driveActivityEventsProvider((fileId: file?.id, folderId: folder?.id)),
    );

    return eventsAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (_, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'No activity recorded yet.',
          style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ),
      data: (events) {
        if (events.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No activity history yet',
                style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12),
              ),
            ),
          );
        }

        return Column(
          children: List.generate(events.length, (index) {
            final e = events[index];
            final isFirst = index == 0;
            final isLast = index == events.length - 1;

            Color statusColor;
            switch (e.type) {
              case DriveActivityType.upload:
                statusColor = AppColors.primary;
                break;
              case DriveActivityType.createFolder:
                statusColor = AppColors.secondary;
                break;
              case DriveActivityType.rename:
              case DriveActivityType.colorChange:
                statusColor = const Color(0xFFF59E0B);
                break;
              case DriveActivityType.share:
                statusColor = const Color(0xFF10B981);
                break;
              case DriveActivityType.trash:
                statusColor = AppColors.error;
                break;
              case DriveActivityType.move:
              case DriveActivityType.restore:
                statusColor = const Color(0xFF8B5CF6);
                break;
            }

            return _buildTimelineItem(
              statusColor: statusColor,
              actionText: e.title,
              timeAgo: _formatRelativeTime(e.timestamp),
              description: e.description,
              fileId: e.fileId,
              fileName: e.fileName,
              fileSize: e.fileSize,
              mimeType: e.mimeType,
              isFirst: isFirst,
              isLast: isLast,
            );
          }),
        );
      },
    );
  }

  String _formatRelativeTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return DateFormat('MMM d, yyyy').format(dt);
    }
  }

  Widget _buildTimelineItem({
    required Color statusColor,
    required String actionText,
    required String timeAgo,
    String? description,
    String? fileId,
    String? fileName,
    int? fileSize,
    String? mimeType,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Vertical timeline: 8px dot + 2px vertical line
          Column(
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withValues(alpha: 0.4),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: AppColors.outline.withValues(alpha: 0.6),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          actionText,
                          style: TextStyle(
                            color: AppColors.onSurface,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        timeAgo,
                        style: TextStyle(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  if (description != null && description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                  if (fileName != null && fileSize != null)
                    _buildActivityFileCard(
                      fileId: fileId,
                      fileName: fileName,
                      fileSize: fileSize,
                      mimeType: mimeType,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityFileCard({
    required String? fileId,
    required String fileName,
    required int fileSize,
    required String? mimeType,
  }) {
    final isMedia = mimeType != null &&
        (mimeType.startsWith('image/') || mimeType.startsWith('video/'));
    final isVid = mimeType != null && mimeType.startsWith('video/');

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.outline.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 52x52 thumbnail or soft-tonic icon container
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 52,
              height: 52,
              child: isMedia && fileId != null
                  ? Consumer(
                      builder: (context, ref, _) {
                        final fileAsync = ref.watch(fileByIdProvider(fileId));
                        final file = fileAsync.valueOrNull;
                        if (file != null) {
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              FutureBuilder<File?>(
                                future: ref.read(thumbnailServiceProvider).getThumbnail(file),
                                builder: (context, snapshot) {
                                  if (snapshot.hasData && snapshot.data != null) {
                                    return Image.file(snapshot.data!, fit: BoxFit.cover);
                                  }
                                  return Container(
                                    color: AppColors.primary.withValues(alpha: 0.1),
                                    child: Center(
                                      child: Icon(
                                        isVid ? Icons.movie_outlined : Icons.image_outlined,
                                        color: AppColors.primary,
                                        size: 24,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              if (isVid)
                                Center(
                                  child: Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.5),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        }
                        return Container(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          child: Center(
                            child: Icon(
                              isVid ? Icons.movie_outlined : Icons.image_outlined,
                              color: AppColors.primary,
                              size: 24,
                            ),
                          ),
                        );
                      },
                    )
                  : Center(
                      child: FileTypeIcon(
                        mimeType: mimeType,
                        fileName: fileName,
                        size: 38,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          // File Name and Size
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fileName,
                  style: TextStyle(
                    color: AppColors.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  _formatBytes(fileSize),
                  style: TextStyle(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _FileInfoBottomSheet extends ConsumerWidget {
  const _FileInfoBottomSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) => DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: AppColors.floatingShadow,
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outline.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Expanded(
              child: FileInfoInspector(isModal: true),
            ),
          ],
        ),
      ),
    );
  }
}
