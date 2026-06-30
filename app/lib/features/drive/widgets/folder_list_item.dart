import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/features/drive/providers/drive_providers.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:go_router/go_router.dart';

class FolderListItem extends ConsumerWidget {
  final FolderData folder;
  
  const FolderListItem({super.key, required this.folder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = folder.color != null ? Color(int.parse(folder.color!)) : Colors.blueAccent;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.folder, color: color, size: 28),
        ),
        title: Text(folder.name, style: const TextStyle(fontWeight: FontWeight.w500)),
        trailing: IconButton(
          icon: const Icon(Icons.more_vert, color: Colors.white54),
          onPressed: () {
            // Context menu logic
            final folderRepo = ref.read(folderRepositoryProvider);
          },
        ),
        onTap: () {
          final current = ref.read(currentFolderIdProvider);
          ref.read(navigationStackProvider.notifier).update((state) => [...state, current]);
          ref.read(currentFolderIdProvider.notifier).state = folder.id;
          
          final loc = GoRouterState.of(context).uri.path;
          if (loc.startsWith('/search')) {
            context.go('/drive');
          }
        },
      ),
    );
  }
}
