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
import '../../gallery/thumbnail_service.dart';
import '../../preview/preview_router.dart';
import '../../sharing/share_dialog.dart';
import '../../tags/tag_dialog.dart';
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

  String _getMockDuration() {
    final hash = file.id.hashCode.abs();
    final seconds = (hash % 7200) + 15; // 15s to 2h
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

    return InkWell(
      onTap: () {
        if (isSelectionMode) {
          _toggleSelection(ref);
        } else {
          PreviewRouter.openPreview(context, file, siblings: siblings);
        }
      },
      onLongPress: () {
        if (!isSelectionMode) {
          ref.read(isSelectionModeProvider.notifier).state = true;
          ref.read(selectedItemsProvider.notifier).state = {file.id};
        }
      },
      onSecondaryTap: () {
        if (!isSelectionMode) {
          ref.read(isSelectionModeProvider.notifier).state = true;
          ref.read(selectedItemsProvider.notifier).state = {file.id};
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A).withValues(alpha: 0.6), // Dark slate theme
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected 
                ? const Color(0xFF38BDF8) // Glow cyan
                : Colors.white.withValues(alpha: 0.05),
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                blurRadius: 10,
              )
            else
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
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
                      _buildFilePlaceholder(),
                    
                    // Gradient overlay
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.4),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.4),
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
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: _buildTypeBadgeIcon(ext),
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
                            color: file.isFavorite ? const Color(0xFF38BDF8) : Colors.white70,
                            size: 20,
                          ),
                          onPressed: () => _toggleFavorite(ref),
                        ),
                      ),
                    ),

                    // Video Play overlay button in the middle
                    if (isVid)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.black,
                            size: 24,
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
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _getMockDuration(),
                            style: const TextStyle(
                              color: Colors.white,
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
                            color: isSelected ? AppColors.primary : Colors.black45,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: Icon(
                            isSelected ? Icons.check : Icons.add,
                            size: 12,
                            color: isSelected ? Colors.black : Colors.transparent,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              
              // Bottom Section: Title, options & details
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (!isSelectionMode)
                          _buildOptionsMenu(context, ref),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          sizeString,
                          style: const TextStyle(
                            color: AppColors.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 10,
                          color: AppColors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          dateString,
                          style: const TextStyle(
                            color: AppColors.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeBadgeIcon(String ext) {
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
        textColor = const Color(0xFF38BDF8);
      case 'pdf':
        textColor = Colors.redAccent;
      case 'xlsx':
      case 'xls':
        textColor = Colors.greenAccent;
      default:
        textColor = Colors.white70;
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

  Widget _buildFilePlaceholder() => DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
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
      icon: const Icon(Icons.more_horiz, size: 16, color: Colors.white70),
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
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'download', child: Text('Download', style: TextStyle(color: Colors.white))),
        const PopupMenuItem(value: 'share', child: Text('Share Link', style: TextStyle(color: Colors.white))),
        const PopupMenuItem(value: 'tags', child: Text('Tags', style: TextStyle(color: Colors.white))),
        const PopupMenuItem(value: 'copy', child: Text('Copy to...', style: TextStyle(color: Colors.white))),
        const PopupMenuItem(value: 'move', child: Text('Move to...', style: TextStyle(color: Colors.white))),
        PopupMenuItem(value: 'star', child: Text(file.isFavorite ? 'Remove Star' : 'Star File', style: const TextStyle(color: Colors.white))),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.error))),
      ],
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
        title: const Text('Delete File', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete "${file.name}"?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final fileRepo = ref.read(fileRepositoryProvider);
      await fileRepo.softDelete(file.id);
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
      color: Colors.white.withValues(alpha: 0.05),
      child: const Icon(Icons.image_outlined, color: Colors.white24, size: 28),
    );
  }
}
