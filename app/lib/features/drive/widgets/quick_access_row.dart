import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:aerodrive/core/theme/app_colors.dart';
import 'package:aerodrive/features/drive/providers/drive_providers.dart';

class QuickAccessCategory {
  final String title;
  final String countText;
  final IconData icon;
  final Color iconColor;

  QuickAccessCategory(this.title, this.countText, this.icon, this.iconColor);
}

class QuickAccessRow extends ConsumerWidget {
  QuickAccessRow({super.key});

  final List<QuickAccessCategory> categories = [
    QuickAccessCategory('My Files', '152 items', Icons.folder, AppColors.fileFolder),
    QuickAccessCategory('Images', '342 items', Icons.image, AppColors.fileImage),
    QuickAccessCategory('Videos', '96 items', Icons.play_circle_fill, AppColors.fileVideo),
    QuickAccessCategory('Documents', '128 items', Icons.description, AppColors.fileDocument),
    QuickAccessCategory('Audios', '72 items', Icons.music_note, AppColors.fileAudio),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Quick Access',
                style: TextStyle(
                  color: AppColors.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('View all', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 110,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final cat = categories[index];
              return Container(
                width: 90,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: InkWell(
                  onTap: () {
                    if (cat.title == 'My Files') {
                      ref.read(currentFolderIdProvider.notifier).state = null;
                      ref.read(navigationStackProvider.notifier).state = [];
                    } else if (cat.title == 'Images') {
                      context.push('/media/images');
                    } else if (cat.title == 'Videos') {
                      context.push('/media/videos');
                    } else if (cat.title == 'Documents') {
                      context.push('/media/documents');
                    } else if (cat.title == 'Audios') {
                      context.push('/media/audios');
                    }
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(cat.icon, color: cat.iconColor, size: 32),
                        const SizedBox(height: 12),
                        Text(
                          cat.title,
                          style: const TextStyle(
                            color: AppColors.onSurface,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          cat.countText,
                          style: TextStyle(
                            color: AppColors.onSurfaceVariant.withValues(alpha: 0.8),
                            fontSize: 10,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
