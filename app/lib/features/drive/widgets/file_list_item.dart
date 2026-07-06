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

class FileListItem extends ConsumerWidget {
  
  const FileListItem({super.key, required this.file, this.siblings});
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

    final isImg = file.mimeType?.startsWith('image/') == true;
    final isVid = file.mimeType?.startsWith('video/') == true;
    final isAud = file.mimeType?.startsWith('audio/') == true;

    // Formatting date based on file type to mirror reference list layout exactly
    String dateString;
    if (isVid || isAud) {
      dateString = file.createdAt != null 
          ? DateFormat('MMM dd, yyyy').format(file.createdAt!)
          : 'Unknown Date';
    } else {
      dateString = file.createdAt != null 
          ? DateFormat('MMM dd, yyyy hh:mm a').format(file.createdAt!)
          : 'Unknown Date';
    }
    
    final sizeString = _formatBytes(file.size ?? 0);

    // Build subtitle layout: size • duration • date
    String subtitleText;
    if (isVid || isAud) {
      subtitleText = '$sizeString • ${_formatDuration(file.duration)} • $dateString';
    } else {
      subtitleText = '$sizeString • $dateString';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected 
            ? Colors.white.withValues(alpha: 0.08) 
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected 
              ? const Color(0xFF38BDF8) 
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: SizedBox(
          width: 52,
          height: 52,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: (isImg || isVid)
                ? FutureBuilder<File?>(
                    future: ref.read(thumbnailServiceProvider).getThumbnail(file),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data != null) {
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(snapshot.data!, fit: BoxFit.cover),
                            if (isVid)
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.black45,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                          ],
                        );
                      }
                      return FileTypeIcon(mimeType: file.mimeType, fileName: file.name, size: 52);
                    },
                  )
                : FileTypeIcon(mimeType: file.mimeType, fileName: file.name, size: 52),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                file.name, 
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (file.isFavorite)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.star_rounded, color: Color(0xFF38BDF8), size: 16),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitleText,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ),
        trailing: isSelectionMode
            ? Checkbox(
                value: isSelected,
                activeColor: Colors.cyanAccent,
                checkColor: Colors.black,
                onChanged: (val) {
                  _toggleSelection(ref);
                },
              )
            : _buildOptionsMenu(context, ref),
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
      ),
    );
  }

  Widget _buildOptionsMenu(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.white54),
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
