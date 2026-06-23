import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/data/db/database.dart';

final trashedItemsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final db = ref.watch(databaseProvider);
  
  // Get soft-deleted folders
  final folders = await (db.select(db.folders)
    ..where((f) => f.deletedAt.isNotNull()))
    .get();

  // Get soft-deleted files
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
            onPressed: () {
              // TODO: Execute Hard Delete Purge manually
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

          return ListView.builder(
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
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Folder Restored')));
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
                  subtitle: Text('${(file.size ?? 0) ~/ 1024} KB • $daysLeft days left'),
                  trailing: TextButton(
                    onPressed: () async {
                      // TODO: fileRepo.restoreFile(file.id)
                    },
                    child: const Text('Restore'),
                  ),
                );
              }
            },
          );
        },
      ),
    );
  }
}
