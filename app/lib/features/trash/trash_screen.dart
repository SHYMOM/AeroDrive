import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/logger.dart';
import '../../core/providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../data/db/database.dart';
import '../../domain/sync/config_sync_service.dart';
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

class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trashAsync = ref.watch(trashedItemsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
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
            icon: const Icon(Icons.delete_forever),
            tooltip: 'Empty Trash',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Empty Trash?'),
                  content: const Text('All items will be permanently deleted. This cannot be undone.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Permanently Delete')),
                  ],
                ),
              );
              if (confirm == true) {
                final db = ref.read(databaseProvider);

                // 1. Collect ALL trashed files (including files inside trashed folders)
                final trashedFiles = await (db.select(db.files)..where((f) => f.deletedAt.isNotNull())).get();
                final trashedFolders = await (db.select(db.folders)..where((f) => f.deletedAt.isNotNull())).get();

                // Also collect files inside trashed folders that might not have deletedAt set individually
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

                // 2. Batch Telegram message deletions by channel ID (much more efficient)
                // Collect: chunk messages, manifest messages, thumbnail messages
                final Map<int, List<int>> channelMessageMap = {};

                void addToDeleteMap(int channelId, int messageId) {
                  channelMessageMap.putIfAbsent(channelId, () => []).add(messageId);
                }

                for (final file in allFilesToDelete) {
                  // Chunk messages
                  final chunks = await (db.select(db.chunks)..where((c) => c.fileId.equals(file.id))).get();
                  for (final chunk in chunks) {
                    if (chunk.channelId != null && chunk.messageId != null) {
                      addToDeleteMap(chunk.channelId!, chunk.messageId!);
                    }
                  }

                  // Manifest message (stored on the file record)
                  if (file.manifestMessageId != null && chunks.isNotEmpty) {
                    final channelId = chunks.first.channelId;
                    if (channelId != null) {
                      addToDeleteMap(channelId, file.manifestMessageId!);
                    }
                  }

                  // Thumbnail message
                  if (file.thumbnailMessageId != null && file.thumbnailChannelId != null) {
                    addToDeleteMap(file.thumbnailChannelId!, file.thumbnailMessageId!);
                  }
                }

                // 3. Delete all collected messages from Telegram, batched by channel
                var deletedCount = 0;
                final telegram = ref.read(telegramManagerProvider.notifier).getClient('primary');
                if (telegram.authState == TelegramAuthState.ready) {
                  for (final entry in channelMessageMap.entries) {
                    final channelId = entry.key;
                    final messageIds = entry.value.toSet().toList(); // deduplicate

                    // TDLib allows max 100 message_ids per deleteMessages call
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

                // 4. Delete all local DB records for trashed items
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
                    // Also delete files still referencing trashed folders (safety net)
                    await (db.delete(db.shareLinks)..where((sl) => sl.folderId.isIn(folderIds.toList()))).go();
                    await (db.delete(db.folders)..where((f) => f.id.isIn(folderIds.toList()))).go();
                  }
                });

                // 5. Clean up local thumbnail cache files
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
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trash emptied!')));
                }
              }
            },
          ),
        ],
      ),
      body: trashAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (contents) {
          final folders = contents['folders'] as List<FolderData>? ?? [];
          final files = contents['files'] as List<FileData>? ?? [];

          if (folders.isEmpty && files.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.delete_outline, size: 64, color: Colors.white24),
                  const SizedBox(height: 16),
                  const Text('Trash is empty', style: TextStyle(color: Colors.white54)),
                  const SizedBox(height: 8),
                  const Text('Items in trash will be permanently deleted after 30 days', style: TextStyle(color: Colors.white30, fontSize: 12)),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/drive'),
                    icon: const Icon(Icons.folder_outlined, size: 18),
                    label: const Text('Back to My Drive'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.cyanAccent,
                      side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.4)),
                    ),
                  ),
                ],
              ),
            );
          }

          final totalItems = folders.length + files.length;

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(trashedItemsProvider);
            },
            child: ListView.builder(
              itemCount: totalItems,
              itemBuilder: (context, index) {
              if (index < folders.length) {
                final folder = folders[index];
                final daysLeft = 30 - DateTime.now().difference(folder.deletedAt!).inDays;
                
                return ListTile(
                  leading: const Icon(Icons.folder, color: Colors.redAccent),
                  title: Text(folder.name),
                  subtitle: Text('$daysLeft days left'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.restore, color: Colors.blueAccent),
                        tooltip: 'Restore',
                        onPressed: () async {
                          await ref.read(folderRepositoryProvider).restoreFolder(folder.id);
                          ref.read(configSyncServiceProvider).syncConfigToChannel();
                          ref.invalidate(trashedItemsProvider);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Folder Restored')));
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                        tooltip: 'Delete Permanently',
                        onPressed: () => _permanentlyDeleteFolder(context, ref, folder),
                      ),
                    ],
                  ),
                );
              } else {
                final file = files[index - folders.length];
                final daysLeft = 30 - DateTime.now().difference(file.deletedAt!).inDays;

                return ListTile(
                  leading: const Icon(Icons.insert_drive_file, color: Colors.grey),
                  title: Text(file.name),
                  subtitle: Text('${(file.size ?? 0) ~/ 1024} KB  $daysLeft days left'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.restore, color: Colors.blueAccent),
                        tooltip: 'Restore',
                        onPressed: () async {
                          await ref.read(fileRepositoryProvider).restoreFile(file.id);
                          ref.read(configSyncServiceProvider).syncConfigToChannel();
                          ref.invalidate(trashedItemsProvider);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File Restored')));
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                        tooltip: 'Delete Permanently',
                        onPressed: () => _permanentlyDeleteFile(context, ref, file),
                      ),
                    ],
                  ),
                );
              }
            },
            ),
          );
        },
      ),
    );
  }

  Future<void> _permanentlyDeleteFile(BuildContext context, WidgetRef ref, FileData file) async {
    final db = ref.read(databaseProvider);

    // Collect all Telegram message IDs to delete
    final Map<int, List<int>> channelMessageMap = {};
    void addToMap(int channelId, int messageId) {
      channelMessageMap.putIfAbsent(channelId, () => []).add(messageId);
    }

    final chunks = await (db.select(db.chunks)..where((c) => c.fileId.equals(file.id))).get();
    for (final chunk in chunks) {
      if (chunk.channelId != null && chunk.messageId != null) {
        addToMap(chunk.channelId!, chunk.messageId!);
      }
    }
    if (file.manifestMessageId != null && chunks.isNotEmpty) {
      final channelId = chunks.first.channelId;
      if (channelId != null) {
        addToMap(channelId, file.manifestMessageId!);
      }
    }
    if (file.thumbnailMessageId != null && file.thumbnailChannelId != null) {
      addToMap(file.thumbnailChannelId!, file.thumbnailMessageId!);
    }

    // Delete from Telegram
    final telegram = ref.read(telegramManagerProvider.notifier).getClient('primary');
    if (telegram.authState == TelegramAuthState.ready) {
      for (final entry in channelMessageMap.entries) {
        final messageIds = entry.value.toSet().toList();
        try {
          await telegram.sendRequest({
            '@type': 'deleteMessages',
            'chat_id': entry.key,
            'message_ids': messageIds,
            'revoke': true,
          });
        } catch (e) {
          AppLogger.error('Failed to delete messages for file ${file.id}', e);
        }
      }
    }

    // Delete from local DB
    await db.transaction(() async {
      await (db.delete(db.chunks)..where((c) => c.fileId.equals(file.id))).go();
      await (db.delete(db.thumbnails)..where((t) => t.fileId.equals(file.id))).go();
      await (db.delete(db.fileTags)..where((ft) => ft.fileId.equals(file.id))).go();
      await (db.delete(db.photoFaces)..where((pf) => pf.fileId.equals(file.id))).go();
      await (db.delete(db.filePlaces)..where((fp) => fp.fileId.equals(file.id))).go();
      await (db.delete(db.shareLinks)..where((sl) => sl.fileId.equals(file.id))).go();
      await (db.delete(db.files)..where((f) => f.id.equals(file.id))).go();
    });

    // Clean up local thumbnail cache
    if (file.thumbnailPath != null) {
      try {
        final thumbFile = File(file.thumbnailPath!);
        if (await thumbFile.exists()) await thumbFile.delete();
      } catch (_) {}
    }

    ref.invalidate(trashedItemsProvider);
    await ref.read(configSyncServiceProvider).recordPermanentDeletion(fileIds: [file.id]);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${file.name} permanently deleted')));
    }
  }

  Future<void> _permanentlyDeleteFolder(BuildContext context, WidgetRef ref, FolderData folder) async {
    final db = ref.read(databaseProvider);

    // Recursively collect all file IDs inside this folder tree
    Future<List<FileData>> getAllFilesInFolderTree(String folderId) async {
      final List<FileData> result = [];
      final files = await (db.select(db.files)..where((f) => f.folderId.equals(folderId))).get();
      result.addAll(files);
      final subfolders = await (db.select(db.folders)..where((f) => f.parentId.equals(folderId))).get();
      for (final sub in subfolders) {
        result.addAll(await getAllFilesInFolderTree(sub.id));
      }
      return result;
    }

    final allFiles = await getAllFilesInFolderTree(folder.id);

    // Delete all files in this folder from Telegram
    for (final file in allFiles) {
      await _permanentlyDeleteFile(context, ref, file);
    }

    // Delete the folder tree from DB
    // Get all subfolder IDs recursively
    Future<List<String>> getAllSubfolderIds(String folderId) async {
      final List<String> ids = [folderId];
      final subfolders = await (db.select(db.folders)..where((f) => f.parentId.equals(folderId))).get();
      for (final sub in subfolders) {
        ids.addAll(await getAllSubfolderIds(sub.id));
      }
      return ids;
    }

    final allFolderIds = await getAllSubfolderIds(folder.id);
    await db.transaction(() async {
      await (db.delete(db.shareLinks)..where((sl) => sl.folderId.isIn(allFolderIds))).go();
      await (db.delete(db.folders)..where((f) => f.id.isIn(allFolderIds))).go();
    });

    ref.invalidate(trashedItemsProvider);
    await ref.read(configSyncServiceProvider).recordPermanentDeletion(
      fileIds: allFiles.map((f) => f.id).toList(),
      folderIds: allFolderIds,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Folder "${folder.name}" permanently deleted')));
    }
  }
}
