import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/features/drive/providers/drive_providers.dart';
import 'package:aerodrive/core/theme/app_colors.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

class FolderGridItem extends ConsumerWidget {
  final FolderData folder;
  
  const FolderGridItem({super.key, required this.folder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Color folderColor = AppColors.folderDefault;
    if (folder.color != null && folder.color!.isNotEmpty) {
      try {
        folderColor = Color(int.parse(folder.color!.replaceFirst('#', '0xFF')));
      } catch (e) {
        // Fallback to default
      }
    }
    
    // Format date similar to reference image (MM/DD/YYYY)
    final dateString = folder.createdAt != null 
        ? DateFormat('MM/dd/yyyy').format(folder.createdAt!)
        : DateFormat('MM/dd/yyyy').format(DateTime.now());

    return InkWell(
      onTap: () {
        final current = ref.read(currentFolderIdProvider);
        ref.read(navigationStackProvider.notifier).update((state) => [...state, current]);
        ref.read(currentFolderIdProvider.notifier).state = folder.id;
        
        final loc = GoRouterState.of(context).uri.path;
        if (loc.startsWith('/search')) {
          context.go('/drive');
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: folderColor.withValues(alpha: 0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              Icons.folder_rounded,
              size: 85,
              color: folderColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            folder.name, 
            textAlign: TextAlign.center, 
            maxLines: 1, 
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$dateString\n—', // Folder size calculation would normally go here
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.onSurfaceVariant,
              fontSize: 10,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
