import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/drive_providers.dart';

class QuickAccessCategory {

  QuickAccessCategory(this.title, this.icon, this.iconColor);
  final String title;
  final IconData icon;
  final Color iconColor;
}

class QuickAccessRow extends ConsumerWidget {
  QuickAccessRow({super.key});

  final List<QuickAccessCategory> categories = [
    QuickAccessCategory('Favorites', Icons.star, Colors.amber),
    QuickAccessCategory('Offline', Icons.offline_pin_rounded, Colors.tealAccent),
    QuickAccessCategory('Images', Icons.image, AppColors.fileImage),
    QuickAccessCategory('Videos', Icons.play_circle_fill, AppColors.fileVideo),
    QuickAccessCategory('Documents', Icons.description, AppColors.fileDocument),
    QuickAccessCategory('Audios', Icons.music_note, AppColors.fileAudio),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(quickAccessStatsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Quick Access',
                style: TextStyle(
                  color: AppColors.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextButton(
                onPressed: () {
                  context.push('/drive/quick-access');
                },
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
          child: statsAsync.when(
            data: (stats) => ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final cat = categories[index];
                  final count = stats[cat.title] ?? 0;
                  final countText = count == 1 ? '1 item' : '$count items';
                  
                  return Container(
                    width: 95,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: InkWell(
                      onTap: () {
                        if (cat.title == 'Favorites') {
                          ref.read(currentFolderIdProvider.notifier).state = null;
                          ref.read(navigationStackProvider.notifier).state = [];
                          ref.read(isOfflineOnlyProvider.notifier).state = false;
                          ref.read(isFavoriteOnlyProvider.notifier).state = true;
                        } else if (cat.title == 'Offline') {
                          ref.read(currentFolderIdProvider.notifier).state = null;
                          ref.read(navigationStackProvider.notifier).state = [];
                          ref.read(isFavoriteOnlyProvider.notifier).state = false;
                          ref.read(isOfflineOnlyProvider.notifier).state = true;
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
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(cat.icon, color: cat.iconColor, size: 32),
                            const SizedBox(height: 12),
                            Text(
                              cat.title,
                              style: TextStyle(
                                color: AppColors.onSurface,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              countText,
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
            loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.white, fontSize: 10))),
          ),
        ),
      ],
    );
  }
}
