import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/logger.dart';
import '../../core/providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/db/database.dart';
import '../../domain/sync/config_sync_service.dart';
import '../drive/widgets/file_type_icon.dart';
import '../telegram/telegram_manager.dart';
import '../telegram/telegram_service.dart';

final trashedItemsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final db = ref.watch(databaseProvider);
  
  final folders = await (db.select(db.folders)
    ..where((f) => f.deletedAt.isNotNull()))
    .get();

  final files = await (db.select(db.files)
    ..where((f) => f.deletedAt.isNotNull()))
    .get();

  return {'folders': folders, 'files': files};
});

class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  final Set<String> _selectedFolderIds = {};
  final Set<String> _selectedFileIds = {};

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _emptyTrash(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Empty Trash?', style: TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.bold)),
        content: Text(
          'All items in the trash will be permanently deleted from Telegram cloud and local storage. This action cannot be undone.',
          style: TextStyle(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Permanently Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final db = ref.read(databaseProvider);

    // 1. Collect ALL trashed files (including files inside trashed folders)
    final trashedFiles = await (db.select(db.files)..where((f) => f.deletedAt.isNotNull())).get();
    final trashedFolders = await (db.select(db.folders)..where((f) => f.deletedAt.isNotNull())).get();

    final folderIds = trashedFolders.map((f) => f.id).toSet();
    List<FileData> allFilesToDelete = [...trashedFiles];
    for (final folderId in folderIds) {
      final filesInFolder = await (db.select(db.files)..where((f) => f.folderId.equals(folderId))).get();
      for (final file in filesInFolder) {
        if (!allFilesToDelete.any((f) => f.id == file.id)) {
          allFilesToDelete.add(file);
        }
      }
    }

    // 2. Batch Telegram message deletions
    final Map<int, List<int>> channelMessageMap = {};
    void addToDeleteMap(int channelId, int messageId) {
      channelMessageMap.putIfAbsent(channelId, () => []).add(messageId);
    }

    for (final file in allFilesToDelete) {
      final chunks = await (db.select(db.chunks)..where((c) => c.fileId.equals(file.id))).get();
      for (final chunk in chunks) {
        if (chunk.channelId != null && chunk.messageId != null) {
          addToDeleteMap(chunk.channelId!, chunk.messageId!);
        }
      }

      if (file.manifestMessageId != null && chunks.isNotEmpty) {
        final channelId = chunks.first.channelId;
        if (channelId != null) {
          addToDeleteMap(channelId, file.manifestMessageId!);
        }
      }

      if (file.thumbnailMessageId != null && file.thumbnailChannelId != null) {
        addToDeleteMap(file.thumbnailChannelId!, file.thumbnailMessageId!);
      }
    }

    var deletedCount = 0;
    final telegram = ref.read(telegramManagerProvider.notifier).getClient('primary');
    if (telegram.authState == TelegramAuthState.ready) {
      for (final entry in channelMessageMap.entries) {
        final channelId = entry.key;
        final messageIds = entry.value.toSet().toList();

        for (var i = 0; i < messageIds.length; i += 100) {
          final batch = messageIds.sublist(i, i + 100 > messageIds.length ? messageIds.length : i + 100);
          try {
            await telegram.sendRequest({
              '@type': 'deleteMessages',
              'chat_id': channelId,
              'message_ids': batch,
              'revoke': true,
            });
            deletedCount += batch.length;
          } catch (e) {
            AppLogger.error('Failed to delete ${batch.length} Telegram messages from channel $channelId', e);
          }
        }
      }
    }

    final allFileIds = allFilesToDelete.map((f) => f.id).toList();
    await db.transaction(() async {
      if (allFileIds.isNotEmpty) {
        await (db.delete(db.chunks)..where((c) => c.fileId.isIn(allFileIds))).go();
        await (db.delete(db.thumbnails)..where((t) => t.fileId.isIn(allFileIds))).go();
        await (db.delete(db.fileTags)..where((ft) => ft.fileId.isIn(allFileIds))).go();
        await (db.delete(db.photoFaces)..where((pf) => pf.fileId.isIn(allFileIds))).go();
        await (db.delete(db.filePlaces)..where((fp) => fp.fileId.isIn(allFileIds))).go();
        await (db.delete(db.shareLinks)..where((sl) => sl.fileId.isIn(allFileIds))).go();
        await (db.delete(db.files)..where((f) => f.id.isIn(allFileIds))).go();
      }

      if (folderIds.isNotEmpty) {
        await (db.delete(db.shareLinks)..where((sl) => sl.folderId.isIn(folderIds.toList()))).go();
        await (db.delete(db.folders)..where((f) => f.id.isIn(folderIds.toList()))).go();
      }
    });

    for (final file in allFilesToDelete) {
      if (file.thumbnailPath != null) {
        try {
          final thumbFile = File(file.thumbnailPath!);
          if (await thumbFile.exists()) {
            await thumbFile.delete();
          }
        } catch (_) {}
      }
    }

    AppLogger.info('Trash emptied: $deletedCount Telegram messages permanently deleted');
    await ref.read(configSyncServiceProvider).recordPermanentDeletion(
      fileIds: allFileIds,
      folderIds: folderIds.toList(),
    );
    ref.invalidate(trashedItemsProvider);
    if (mounted) {
      setState(() {
        _selectedFolderIds.clear();
        _selectedFileIds.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Trash emptied successfully!'), backgroundColor: AppColors.primary),
      );
    }
  }

  Future<void> _restoreSelected() async {
    final folderRepo = ref.read(folderRepositoryProvider);
    final fileRepo = ref.read(fileRepositoryProvider);

    for (final fId in _selectedFolderIds) {
      await folderRepo.restoreFolder(fId);
    }
    for (final fId in _selectedFileIds) {
      await fileRepo.restoreFile(fId);
    }

    ref.read(configSyncServiceProvider).syncConfigToChannel();
    ref.invalidate(trashedItemsProvider);

    if (mounted) {
      final total = _selectedFolderIds.length + _selectedFileIds.length;
      setState(() {
        _selectedFolderIds.clear();
        _selectedFileIds.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restored $total item(s)'), backgroundColor: AppColors.primary),
      );
    }
  }

  Future<void> _permanentlyDeleteFolder(BuildContext context, FolderData folder) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete "${folder.name}"?', style: TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.bold)),
        content: Text(
          'This folder and all its contents will be permanently deleted from Telegram.',
          style: TextStyle(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final db = ref.read(databaseProvider);
    final filesInFolder = await (db.select(db.files)..where((f) => f.folderId.equals(folder.id))).get();
    final fileIds = filesInFolder.map((f) => f.id).toList();

    for (final f in filesInFolder) {
      await _deleteTelegramMessagesForFile(f);
    }

    await db.transaction(() async {
      if (fileIds.isNotEmpty) {
        await (db.delete(db.chunks)..where((c) => c.fileId.isIn(fileIds))).go();
        await (db.delete(db.thumbnails)..where((t) => t.fileId.isIn(fileIds))).go();
        await (db.delete(db.files)..where((f) => f.id.isIn(fileIds))).go();
      }
      await (db.delete(db.folders)..where((f) => f.id.equals(folder.id))).go();
    });

    ref.invalidate(trashedItemsProvider);
  }

  Future<void> _permanentlyDeleteFile(BuildContext context, FileData file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete "${file.name}"?', style: TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.bold)),
        content: Text(
          'This file will be permanently deleted from Telegram cloud.',
          style: TextStyle(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _deleteTelegramMessagesForFile(file);

    final db = ref.read(databaseProvider);
    await db.transaction(() async {
      await (db.delete(db.chunks)..where((c) => c.fileId.equals(file.id))).go();
      await (db.delete(db.thumbnails)..where((t) => t.fileId.equals(file.id))).go();
      await (db.delete(db.files)..where((f) => f.id.equals(file.id))).go();
    });

    ref.invalidate(trashedItemsProvider);
  }

  Future<void> _deleteTelegramMessagesForFile(FileData file) async {
    final db = ref.read(databaseProvider);
    final chunks = await (db.select(db.chunks)..where((c) => c.fileId.equals(file.id))).get();
    final telegram = ref.read(telegramManagerProvider.notifier).getClient('primary');
    if (telegram.authState != TelegramAuthState.ready) return;

    final Map<int, List<int>> channelMap = {};
    for (final c in chunks) {
      if (c.channelId != null && c.messageId != null) {
        channelMap.putIfAbsent(c.channelId!, () => []).add(c.messageId!);
      }
    }
    for (final entry in channelMap.entries) {
      try {
        await telegram.sendRequest({
          '@type': 'deleteMessages',
          'chat_id': entry.key,
          'message_ids': entry.value,
          'revoke': true,
        });
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final trashAsync = ref.watch(trashedItemsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Trash',
          style: TextStyle(
            color: AppColors.onSurface,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        backgroundColor: AppColors.surface,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.onSurface),
          tooltip: 'Back to Drive',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/drive');
            }
          },
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: AppColors.onSurfaceVariant),
            tooltip: 'Refresh Trash',
            onPressed: () => ref.invalidate(trashedItemsProvider),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: trashAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err', style: TextStyle(color: AppColors.onSurface))),
        data: (contents) {
          final folders = contents['folders'] as List<FolderData>? ?? [];
          final files = contents['files'] as List<FileData>? ?? [];

          if (folders.isEmpty && files.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.delete_outline_rounded, size: 32, color: AppColors.primary),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Trash is Empty',
                    style: TextStyle(
                      color: AppColors.onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Items moved to Trash are automatically purged after 30 days',
                    style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => context.go('/drive'),
                    icon: const Icon(Icons.folder_rounded, size: 18),
                    label: const Text('Back to My Drive'),
                  ),
                ],
              ),
            );
          }

          final hasSelected = _selectedFolderIds.isNotEmpty || _selectedFileIds.isNotEmpty;

          return Column(
            children: [
              // ── Clean Top Action Banner ──────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.outline.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: AppColors.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Items in trash will be permanently deleted after 30 days.',
                        style: TextStyle(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    if (hasSelected) ...[
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _restoreSelected,
                        icon: const Icon(Icons.restore_rounded, size: 16),
                        label: Text('Restore (${_selectedFolderIds.length + _selectedFileIds.length})'),
                      ),
                      const SizedBox(width: 10),
                    ],
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: const BorderSide(color: Color(0xFFEF4444)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => _emptyTrash(context),
                      icon: const Icon(Icons.delete_forever_rounded, size: 16),
                      label: const Text('Empty Trash'),
                    ),
                  ],
                ),
              ),

              // ── Items List ───────────────────────────────────────
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => ref.invalidate(trashedItemsProvider),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    children: [
                      // Folders Section
                      if (folders.isNotEmpty) ...[
                        Text(
                          'Folders (${folders.length})',
                          style: TextStyle(
                            color: AppColors.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...folders.map((folder) {
                          final daysLeft = 30 - DateTime.now().difference(folder.deletedAt!).inDays;
                          final isSelected = _selectedFolderIds.contains(folder.id);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.surfaceVariant : AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primary
                                    : (Theme.of(context).brightness == Brightness.dark
                                        ? Colors.white.withValues(alpha: 0.04)
                                        : AppColors.outline.withValues(alpha: 0.5)),
                              ),
                              boxShadow: AppColors.cardShadow,
                            ),
                            child: ListTile(
                              leading: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: AppColors.secondary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Icon(Icons.folder_rounded, color: AppColors.secondary, size: 22),
                                ),
                              ),
                              title: Text(
                                folder.name,
                                style: TextStyle(
                                  color: AppColors.onSurface,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                '$daysLeft days left before permanent deletion',
                                style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 11.5),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.restore_rounded, color: AppColors.primary, size: 20),
                                    tooltip: 'Restore Folder',
                                    onPressed: () async {
                                      await ref.read(folderRepositoryProvider).restoreFolder(folder.id);
                                      ref.read(configSyncServiceProvider).syncConfigToChannel();
                                      ref.invalidate(trashedItemsProvider);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Restored "${folder.name}"')),
                                        );
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4444), size: 20),
                                    tooltip: 'Permanently Delete',
                                    onPressed: () => _permanentlyDeleteFolder(context, folder),
                                  ),
                                ],
                              ),
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedFolderIds.remove(folder.id);
                                  } else {
                                    _selectedFolderIds.add(folder.id);
                                  }
                                });
                              },
                            ),
                          );
                        }),
                        const SizedBox(height: 16),
                      ],

                      // Files Section
                      if (files.isNotEmpty) ...[
                        Text(
                          'Files (${files.length})',
                          style: TextStyle(
                            color: AppColors.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...files.map((file) {
                          final daysLeft = 30 - DateTime.now().difference(file.deletedAt!).inDays;
                          final isSelected = _selectedFileIds.contains(file.id);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.surfaceVariant : AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primary
                                    : (Theme.of(context).brightness == Brightness.dark
                                        ? Colors.white.withValues(alpha: 0.04)
                                        : AppColors.outline.withValues(alpha: 0.5)),
                              ),
                              boxShadow: AppColors.cardShadow,
                            ),
                            child: ListTile(
                              leading: SizedBox(
                                width: 38,
                                height: 38,
                                child: FileTypeIcon(mimeType: file.mimeType, fileName: file.name, size: 30),
                              ),
                              title: Text(
                                file.name,
                                style: TextStyle(
                                  color: AppColors.onSurface,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${_formatBytes(file.size ?? 0)} • $daysLeft days left',
                                style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 11.5),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.restore_rounded, color: AppColors.primary, size: 20),
                                    tooltip: 'Restore File',
                                    onPressed: () async {
                                      await ref.read(fileRepositoryProvider).restoreFile(file.id);
                                      ref.read(configSyncServiceProvider).syncConfigToChannel();
                                      ref.invalidate(trashedItemsProvider);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Restored "${file.name}"')),
                                        );
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4444), size: 20),
                                    tooltip: 'Permanently Delete',
                                    onPressed: () => _permanentlyDeleteFile(context, file),
                                  ),
                                ],
                              ),
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedFileIds.remove(file.id);
                                  } else {
                                    _selectedFileIds.add(file.id);
                                  }
                                });
                              },
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
