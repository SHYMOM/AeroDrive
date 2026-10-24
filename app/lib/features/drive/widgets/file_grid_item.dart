import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/db/database.dart';
import '../../gallery/thumbnail_service.dart';
import '../../preview/preview_router.dart';
import '../../sharing/share_dialog.dart';
import '../../tags/tag_dialog.dart';
import '../../../domain/sync/config_sync_service.dart';
import '../../../domain/offline/offline_pin_service.dart';
import '../providers/drive_providers.dart';
import 'file_type_icon.dart';
import 'folder_picker_dialog.dart';

class FileGridItem extends ConsumerWidget {
  
  const FileGridItem({super.key, required this.file, this.siblings});
  final FileData file;
  final List<FileData>? siblings;

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return '00:00';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    
    final hStr = h > 0 ? '${h.toString().padLeft(2, '0')}:' : '';
    final mStr = m.toString().padLeft(2, '0');
    final sStr = s.toString().padLeft(2, '0');
    
    return '$hStr$mStr:$sStr';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSelectionMode = ref.watch(isSelectionModeProvider);
    final selectedItems = ref.watch(selectedItemsProvider);
    final isSelected = selectedItems.contains(file.id);

    final dateString = file.createdAt != null 
        ? DateFormat('MMM dd, yyyy').format(file.createdAt!)
        : 'Unknown date';
    final sizeString = _formatBytes(file.size ?? 0);

    final ext = file.name.split('.').last.toLowerCase();
    final isImg = file.mimeType?.startsWith('image/') == true;
    final isVid = file.mimeType?.startsWith('video/') == true;

    Offset? tapPosition;

    return GestureDetector(
      onTapDown: (details) {
        tapPosition = details.globalPosition;
      },
      onTap: () {
        if (isSelectionMode) {
          _toggleSelection(ref);
        } else {
          PreviewRouter.openPreview(context, file, siblings: siblings);
        }
      },
      onLongPress: () {
        if (!isSelectionMode && tapPosition != null) {
          _showGridContextMenu(context, ref, tapPosition!);
        } else {
          _toggleSelection(ref);
        }
      },
      onSecondaryTapDown: (details) {
        tapPosition = details.globalPosition;
      },
      onSecondaryTap: () {
        if (!isSelectionMode && tapPosition != null) {
          _showGridContextMenu(context, ref, tapPosition!);
        }
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected 
                ? Theme.of(context).colorScheme.primary // Glow cyan
                : Theme.of(context).colorScheme.outlineVariant, // Subtle 1px stroke
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                blurRadius: 10,
              )
            else
              BoxShadow(
                color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.2),
                blurRadius: 8,
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Half: Cover image or File Type placeholder
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (isImg || isVid)
                          _FileThumbnail(file: file)
                        else
                          _buildFilePlaceholder(context),
                        
                        // Gradient overlay
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
                                Colors.transparent,
                                Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
                              ],
                            ),
                          ),
                        ),

                        // Top-Left Badge (File type icon)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: _buildTypeBadgeIcon(ext, context),
                          ),
                        ),
                        
                        // Top-Right Star Icon
                        Positioned(
                          top: 2,
                          right: 2,
                          child: Material(
                            color: Colors.transparent,
                            child: IconButton(
                              icon: Icon(
                                file.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                                color: file.isFavorite ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                                size: 20,
                              ),
                              onPressed: () => _toggleFavorite(ref),
                            ),
                          ),
                        ),

                        // Video Play overlay button in the middle (with frosted glass effect)
                        if (isVid)
                          Center(
                            child: ClipOval(
                              child: BackdropFilter(
                                filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                                      width: 1.2,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.play_arrow_rounded,
                                    color: Theme.of(context).colorScheme.onSurface,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // Bottom-Left Offline Pin Badge
                        if (ref.watch(offlinePinnedIdsProvider).contains(file.id))
                          Positioned(
                            bottom: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.offline_pin_rounded,
                                color: Colors.tealAccent,
                                size: 12,
                              ),
                            ),
                          ),

                        // Video Duration tag at bottom-right
                        if (isVid)
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _formatDuration(file.duration),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),

                        // Checkbox Selection Mode Overlay
                        if (isSelectionMode)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.primary : Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
                                shape: BoxShape.circle,
                                border: Border.all(color: Theme.of(context).colorScheme.onSurface, width: 1.5),
                              ),
                              child: Icon(
                                isSelected ? Icons.check : Icons.add,
                                size: 12,
                                color: isSelected ? Theme.of(context).colorScheme.surface : Colors.transparent,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  // Bottom Section: Title & details
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                file.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$dateString • $sizeString',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontSize: 10,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (!isSelectionMode)
                          _buildOptionsMenu(context, ref),
                      ],
                    ),
                  ),
                ],
              ),

              // Translucent blue overlay on selection
              if (isSelected)
                Positioned.fill(
                  child: Container(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeBadgeIcon(String ext, BuildContext context) {
    if (file.mimeType?.startsWith('video/') == true) {
      return const Icon(Icons.play_arrow_rounded, color: Colors.amber, size: 14);
    }
    if (file.mimeType?.startsWith('image/') == true) {
      return const Icon(Icons.image_outlined, color: Colors.grey, size: 14);
    }
    
    // For other documents, show 2-letter uppercase file extension
    final text = ext.length > 2 ? ext.substring(0, 2) : ext;
    
    Color textColor;
    switch (ext) {
      case 'psd':
      case 'ps':
        textColor = Theme.of(context).colorScheme.primary;
      case 'pdf':
        textColor = Colors.redAccent;
      case 'xlsx':
      case 'xls':
        textColor = Colors.greenAccent;
      default:
        textColor = Theme.of(context).colorScheme.onSurfaceVariant;
    }
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: textColor,
        fontSize: 9,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildFilePlaceholder(BuildContext context) => DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
      ),
      child: Center(
        child: FileTypeIcon(
          mimeType: file.mimeType,
          fileName: file.name,
          size: 44,
        ),
      ),
    );

  Widget _buildOptionsMenu(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      color: AppColors.surfaceElevated,
      onSelected: (value) async {
        if (value == 'download') {
          final db = ref.read(databaseProvider);
          await db.into(db.transferQueue).insert(
            TransferQueueCompanion.insert(
              id: const Uuid().v4(),
              fileId: drift.Value(file.id),
              type: const drift.Value('DOWNLOAD_FILE'),
              status: const drift.Value('PENDING'),
              priority: const drift.Value(1),
              createdAt: drift.Value(DateTime.now()),
            )
          );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Queued ${file.name} for download...')));
          }
        } else if (value == 'offline') {
          final pinService = ref.read(offlinePinServiceProvider);
          final isPinned = ref.read(offlinePinnedIdsProvider).contains(file.id);
          if (isPinned) {
            await pinService.unpinFile(file.id);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Removed ${file.name} from offline access')),
              );
            }
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Caching ${file.name} for offline access...')),
            );
            final pinned = await pinService.pinFile(file);
            if (context.mounted) {
              if (pinned != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${file.name} is now available offline')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to cache ${file.name} for offline')),
                );
              }
            }
          }
        } else if (value == 'share') {
          showDialog(
            context: context,
            builder: (ctx) => ShareDialog(file: file),
          );
        } else if (value == 'tags') {
          TagDialog.show(context, file);
        } else if (value == 'delete') {
          _showDeleteConfirm(context, ref);
        } else if (value == 'move') {
          _showMoveDialog(context, ref);
        } else if (value == 'copy') {
          _showCopyDialog(context, ref);
        } else if (value == 'star') {
          _toggleFavorite(ref);
        }
      },
      itemBuilder: (context) {
        final isOfflinePinned = ref.watch(offlinePinnedIdsProvider).contains(file.id);
        return [
          PopupMenuItem(value: 'download', child: Text('Download', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
          PopupMenuItem(
            value: 'offline',
            child: Row(
              children: [
                Icon(isOfflinePinned ? Icons.offline_pin_outlined : Icons.offline_pin_rounded, color: Colors.tealAccent, size: 18),
                const SizedBox(width: 8),
                Text(isOfflinePinned ? 'Remove Offline Access' : 'Available Offline', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
              ],
            ),
          ),
          PopupMenuItem(value: 'share', child: Text('Share Link', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
          PopupMenuItem(value: 'tags', child: Text('Tags', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
          PopupMenuItem(value: 'copy', child: Text('Copy to...', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
          PopupMenuItem(value: 'move', child: Text('Move to...', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
          PopupMenuItem(value: 'star', child: Text(file.isFavorite ? 'Remove Star' : 'Star File', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
          const PopupMenuDivider(),
          PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.error))),
        ];
      },
    );

  Future<void> _toggleFavorite(WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.files)..where((f) => f.id.equals(file.id))).write(
      FilesCompanion(isFavorite: drift.Value(!file.isFavorite)),
    );
    ref.read(dbRebuildVersionProvider.notifier).state++;
  }

  void _toggleSelection(WidgetRef ref) {
    ref.read(selectedItemsProvider.notifier).update((s) {
      final next = {...s};
      if (next.contains(file.id)) {
        next.remove(file.id);
      } else {
        next.add(file.id);
      }
      if (next.isEmpty) {
        ref.read(isSelectionModeProvider.notifier).state = false;
      }
      return next;
    });
  }

  Future<void> _showDeleteConfirm(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text('Delete File', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Text('Are you sure you want to delete "${file.name}"?', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final fileRepo = ref.read(fileRepositoryProvider);
      await fileRepo.softDelete(file.id);
      ref.read(configSyncServiceProvider).syncConfigToChannel();
      ref.read(dbRebuildVersionProvider.notifier).state++;
    }
  }

  Future<void> _showMoveDialog(BuildContext context, WidgetRef ref) async {
    final targetFolderId = await showDialog<String?>(
      context: context,
      builder: (ctx) => const FolderPickerDialog(title: 'Move file to...'),
    );
    if (targetFolderId == null) return;
    
    final db = ref.read(databaseProvider);
    final String? folderId = targetFolderId == '__root__' ? null : targetFolderId;
    await (db.update(db.files)..where((f) => f.id.equals(file.id))).write(
      FilesCompanion(folderId: drift.Value(folderId)),
    );
    ref.read(dbRebuildVersionProvider.notifier).state++;
  }

  Future<void> _showCopyDialog(BuildContext context, WidgetRef ref) async {
    final targetFolderId = await showDialog<String?>(
      context: context,
      builder: (ctx) => const FolderPickerDialog(title: 'Copy file to...'),
    );
    if (targetFolderId == null) return;
    
    final db = ref.read(databaseProvider);
    final String? folderId = targetFolderId == '__root__' ? null : targetFolderId;
    
    final newId = const Uuid().v4();
    await db.into(db.files).insert(
      FilesCompanion.insert(
        id: newId,
        name: file.name.contains(' (Copy)') ? file.name : '${file.name} (Copy)',
        folderId: drift.Value(folderId),
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
          fileId: drift.Value(newId),
          chunkIndex: drift.Value(chunk.chunkIndex),
          channelId: drift.Value(chunk.channelId),
          messageId: drift.Value(chunk.messageId),
          size: drift.Value(chunk.size),
          hash: drift.Value(chunk.hash),
        ),
      );
    }
    
    ref.read(dbRebuildVersionProvider.notifier).state++;
  }

  void _showGridContextMenu(BuildContext context, WidgetRef ref, Offset position) async {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Rect.fromLTWH(0, 0, overlay.size.width, overlay.size.height),
      ),
      color: AppColors.surfaceElevated,
      items: [
        PopupMenuItem(value: 'download', child: Text('Download', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
        PopupMenuItem(value: 'share', child: Text('Share Link', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
        PopupMenuItem(value: 'tags', child: Text('Tags', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
        PopupMenuItem(value: 'copy', child: Text('Copy to...', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
        PopupMenuItem(value: 'move', child: Text('Move to...', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
        PopupMenuItem(value: 'star', child: Text(file.isFavorite ? 'Remove Star' : 'Star File', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
        PopupMenuItem(value: 'select', child: Text('Select', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.error))),
      ],
    );

    if (value == null) return;

    if (value == 'download') {
      final db = ref.read(databaseProvider);
      await db.into(db.transferQueue).insert(
        TransferQueueCompanion.insert(
          id: const Uuid().v4(),
          fileId: drift.Value(file.id),
          type: const drift.Value('DOWNLOAD_FILE'),
          status: const drift.Value('PENDING'),
          priority: const drift.Value(1),
          createdAt: drift.Value(DateTime.now()),
        )
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Queued ${file.name} for download...')));
      }
    } else if (value == 'share') {
      showDialog(
        context: context,
        builder: (ctx) => ShareDialog(file: file),
      );
    } else if (value == 'tags') {
      TagDialog.show(context, file);
    } else if (value == 'delete') {
      _showDeleteConfirm(context, ref);
    } else if (value == 'move') {
      _showMoveDialog(context, ref);
    } else if (value == 'copy') {
      _showCopyDialog(context, ref);
    } else if (value == 'star') {
      _toggleFavorite(ref);
    } else if (value == 'select') {
      ref.read(isSelectionModeProvider.notifier).state = true;
      ref.read(selectedItemsProvider.notifier).state = {file.id};
    }
  }
}

class _FileThumbnail extends ConsumerStatefulWidget {
  const _FileThumbnail({required this.file});
  final FileData file;

  @override
  ConsumerState<_FileThumbnail> createState() => _FileThumbnailState();
}

class _FileThumbnailState extends ConsumerState<_FileThumbnail> {
  File? _thumbnail;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant _FileThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.id != widget.file.id) {
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    final thumb = await ref.read(thumbnailServiceProvider).getThumbnail(widget.file);
    if (mounted) {
      setState(() {
        _thumbnail = thumb;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_thumbnail != null) {
      return Image.file(_thumbnail!, fit: BoxFit.cover);
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return ColoredBox(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
      child: Icon(Icons.image_outlined, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.24), size: 28),
    );
  }
}
