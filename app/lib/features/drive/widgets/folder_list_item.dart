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
import '../providers/drive_providers.dart';
import 'folder_picker_dialog.dart';
import 'marquee_text.dart';
import '../../sharing/share_dialog.dart';

class FolderListItem extends ConsumerWidget {
  
  const FolderListItem({super.key, required this.folder});
  final FolderData folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Color folderColor = AppColors.folderDefault;
    if (folder.color != null && folder.color!.isNotEmpty) {
      try {
        var colorStr = folder.color!;
        if (colorStr.startsWith('#')) {
          colorStr = colorStr.replaceFirst('#', '0xFF');
        } else if (!colorStr.startsWith('0x') && !colorStr.startsWith('0X')) {
          colorStr = '0x$colorStr';
        }
        folderColor = Color(int.parse(colorStr));
      } catch (e) {
        // Fallback to default
      }
    }
    
    // Format date: MM/dd/yyyy hh:mm a
    final dateString = folder.createdAt != null 
        ? DateFormat('MM/dd/yyyy hh:mm a').format(folder.createdAt!)
        : 'Unknown time';

    final sizeAsync = ref.watch(folderSizeProvider(folder.id));
    final sizeText = sizeAsync.when(
      data: _formatFolderSize,
      loading: () => '...',
      error: (_, _) => '0 B',
    );

    final isSelectionMode = ref.watch(isSelectionModeProvider);
    final selectedItems = ref.watch(selectedItemsProvider);
    final isSelected = selectedItems.contains(folder.id);

    final itemsCountAsync = ref.watch(folderItemsCountProvider(folder.id));
    final itemsCountText = itemsCountAsync.when(
      data: (count) => '$count item${count == 1 ? "" : "s"}',
      loading: () => '...',
      error: (_, _) => '0 items',
    );

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
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: folderColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.folder, color: folderColor, size: 28),
        ),
        title: Row(
          children: [
            Expanded(
              child: MarqueeText(
                text: folder.name,
                alignment: Alignment.centerLeft,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
            if (folder.isFavorite)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.star_rounded, color: Color(0xFF38BDF8), size: 16),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            itemsCountText,
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
            final current = ref.read(currentFolderIdProvider);
            ref.read(navigationStackProvider.notifier).update((state) => [...state, current]);
            ref.read(currentFolderIdProvider.notifier).state = folder.id;
            
            final loc = GoRouterState.of(context).uri.path;
            if (loc.startsWith('/search')) {
              context.go('/drive');
            }
          }
        },
        onLongPress: () {
          if (!isSelectionMode) {
            ref.read(isSelectionModeProvider.notifier).state = true;
            ref.read(selectedItemsProvider.notifier).state = {folder.id};
          }
        },
      ),
    );
  }

  Widget _buildOptionsMenu(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.white54),
      color: AppColors.surfaceElevated,
      onSelected: (value) async {
        if (value == 'rename') {
          _showRenameDialog(context, ref);
        } else if (value == 'share') {
          showDialog(
            context: context,
            builder: (ctx) => ShareDialog(folder: folder),
          );
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
        const PopupMenuItem(value: 'rename', child: Text('Rename', style: TextStyle(color: Colors.white))),
        const PopupMenuItem(value: 'share', child: Text('Share', style: TextStyle(color: Colors.white))),
        const PopupMenuItem(value: 'copy', child: Text('Copy to...', style: TextStyle(color: Colors.white))),
        const PopupMenuItem(value: 'move', child: Text('Move to...', style: TextStyle(color: Colors.white))),
        PopupMenuItem(value: 'star', child: Text(folder.isFavorite ? 'Remove Star' : 'Star Folder', style: const TextStyle(color: Colors.white))),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.error))),
      ],
    );

  Future<void> _toggleFavorite(WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.folders)..where((f) => f.id.equals(folder.id))).write(
      FoldersCompanion(isFavorite: drift.Value(!folder.isFavorite)),
    );
    ref.read(dbRebuildVersionProvider.notifier).state++;
  }

  void _toggleSelection(WidgetRef ref) {
    ref.read(selectedItemsProvider.notifier).update((s) {
      final next = {...s};
      if (next.contains(folder.id)) {
        next.remove(folder.id);
      } else {
        next.add(folder.id);
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

  Future<void> _showRenameDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: folder.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Rename Folder', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Folder Name',
            hintStyle: TextStyle(color: Colors.white30),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rename', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );

    if (confirmed == true && controller.text.trim().isNotEmpty) {
      final db = ref.read(databaseProvider);
      await (db.update(db.folders)..where((f) => f.id.equals(folder.id))).write(
        FoldersCompanion(name: drift.Value(controller.text.trim())),
      );
      ref.read(dbRebuildVersionProvider.notifier).state++;
    }
  }

  Future<void> _showDeleteConfirm(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Delete Folder', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete "${folder.name}" and all its contents?', style: const TextStyle(color: Colors.white70)),
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
      final folderRepo = ref.read(folderRepositoryProvider);
      await folderRepo.trashFolder(folder.id);
      ref.read(dbRebuildVersionProvider.notifier).state++;
    }
  }

  Future<void> _showMoveDialog(BuildContext context, WidgetRef ref) async {
    final targetFolderId = await showDialog<String?>(
      context: context,
      builder: (ctx) => FolderPickerDialog(
        title: 'Move folder to...',
        excludeFolderId: folder.id,
      ),
    );
    if (targetFolderId == null) return;
    
    final db = ref.read(databaseProvider);
    final String? folderId = targetFolderId == '__root__' ? null : targetFolderId;
    await (db.update(db.folders)..where((f) => f.id.equals(folder.id))).write(
      FoldersCompanion(parentId: drift.Value(folderId)),
    );
    ref.read(dbRebuildVersionProvider.notifier).state++;
  }

  Future<void> _showCopyDialog(BuildContext context, WidgetRef ref) async {
    final targetFolderId = await showDialog<String?>(
      context: context,
      builder: (ctx) => const FolderPickerDialog(title: 'Copy folder to...'),
    );
    if (targetFolderId == null) return;
    
    final db = ref.read(databaseProvider);
    final String? folderId = targetFolderId == '__root__' ? null : targetFolderId;
    
    await _copyFolderRecursive(folder.id, folderId, db);
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
}
