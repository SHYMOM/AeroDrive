import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logger.dart';
import '../../core/providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../data/db/database.dart';
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

                // Delete Telegram messages permanently before clearing DB
                final files = await (db.select(db.files)..where((f) => f.deletedAt.isNotNull())).get();
                var deletedCount = 0;
                for (final file in files) {
                  final chunks = await (db.select(db.chunks)..where((c) => c.fileId.equals(file.id))).get();
                  for (final chunk in chunks) {
                    if (chunk.channelId == null || chunk.messageId == null) continue;
                    try {
                      final telegram = ref.read(telegramManagerProvider.notifier).getClient('primary');
                      if (telegram.authState == TelegramAuthState.ready) {
                        await telegram.sendRequest({
                          '@type': 'deleteMessages',
                          'chat_id': chunk.channelId,
                          'message_ids': [chunk.messageId],
                          'revoke': true,
                        });
                        deletedCount++;
                      }
                    } catch (e) {
                      AppLogger.error('Failed to delete Telegram message ${chunk.messageId}', e);
                    }
                  }
                }

                await db.transaction(() async {
                  final fileIds = files.map((f) => f.id).toList();
                  final foldersInTrash = await (db.select(db.folders)..where((f) => f.deletedAt.isNotNull())).get();
                  final folderIds = foldersInTrash.map((f) => f.id).toList();

                  if (fileIds.isNotEmpty) {
                    await (db.delete(db.chunks)..where((c) => c.fileId.isIn(fileIds))).go();
                    await (db.delete(db.thumbnails)..where((t) => t.fileId.isIn(fileIds))).go();
                    await (db.delete(db.fileTags)..where((ft) => ft.fileId.isIn(fileIds))).go();
                    await (db.delete(db.photoFaces)..where((pf) => pf.fileId.isIn(fileIds))).go();
                    await (db.delete(db.filePlaces)..where((fp) => fp.fileId.isIn(fileIds))).go();
                    await (db.delete(db.shareLinks)..where((sl) => sl.fileId.isIn(fileIds))).go();
                    await (db.delete(db.files)..where((f) => f.id.isIn(fileIds))).go();
                  }

                  if (folderIds.isNotEmpty) {
                    await (db.delete(db.shareLinks)..where((sl) => sl.folderId.isIn(folderIds))).go();
                    await (db.delete(db.folders)..where((f) => f.id.isIn(folderIds))).go();
                  }
                });
                AppLogger.info('Trash emptied: $deletedCount Telegram messages permanently deleted');
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
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delete_outline, size: 64, color: Colors.white24),
                  SizedBox(height: 16),
                  Text('Trash is empty', style: TextStyle(color: Colors.white54)),
                  SizedBox(height: 8),
                  Text('Items in trash will be permanently deleted after 30 days', style: TextStyle(color: Colors.white30, fontSize: 12)),
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
                  trailing: TextButton(
                    onPressed: () async {
                      await ref.read(folderRepositoryProvider).restoreFolder(folder.id);
                      ref.invalidate(trashedItemsProvider);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Folder Restored')));
                      }
                    },
                    child: const Text('Restore'),
                  ),
                );
              } else {
                final file = files[index - folders.length];
                final daysLeft = 30 - DateTime.now().difference(file.deletedAt!).inDays;

                return ListTile(
                  leading: const Icon(Icons.insert_drive_file, color: Colors.grey),
                  title: Text(file.name),
                  subtitle: Text('${(file.size ?? 0) ~/ 1024} KB  $daysLeft days left'),
                  trailing: TextButton(
                    onPressed: () async {
                      await ref.read(fileRepositoryProvider).restoreFile(file.id);
                      ref.invalidate(trashedItemsProvider);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File Restored')));
                      }
                    },
                    child: const Text('Restore'),
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
}
