import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import 'providers/drive_providers.dart';

class QuickAccessToolsScreen extends ConsumerWidget {
  const QuickAccessToolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(quickAccessStatsProvider);

    final List<Map<String, dynamic>> categories = [
      {
        'title': 'My Files',
        'icon': Icons.folder_rounded,
        'color': AppColors.fileFolder,
        'route': '/drive',
      },
      {
        'title': 'Images',
        'icon': Icons.image_rounded,
        'color': AppColors.fileImage,
        'route': '/media/images',
      },
      {
        'title': 'Videos',
        'icon': Icons.play_circle_fill_rounded,
        'color': AppColors.fileVideo,
        'route': '/media/videos',
      },
      {
        'title': 'Documents',
        'icon': Icons.description_rounded,
        'color': AppColors.fileDocument,
        'route': '/media/documents',
      },
      {
        'title': 'Audios',
        'icon': Icons.music_note_rounded,
        'color': AppColors.fileAudio,
        'route': '/media/audios',
      },
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Quick Access Tools',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.3),
            radius: 1.8,
            colors: [
              const Color(0xFF7C3AED).withValues(alpha: 0.15),
              const Color(0xFF00E5FF).withValues(alpha: 0.05),
              AppColors.background,
              AppColors.background,
            ],
          ),
        ),
        child: statsAsync.when(
          data: (stats) => GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.1,
              ),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final cat = categories[index];
                final count = stats[cat['title']] ?? 0;
                final countText = count == 1 ? '1 item' : '$count items';

                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: InkWell(
                    onTap: () {
                      if (cat['title'] == 'My Files') {
                        ref.read(currentFolderIdProvider.notifier).state = null;
                        ref.read(navigationStackProvider.notifier).state = [];
                        context.go(cat['route']);
                      } else {
                        context.push(cat['route']);
                      }
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Align(
                            alignment: Alignment.topRight,
                            child: CircleAvatar(
                              backgroundColor: (cat['color'] as Color).withValues(alpha: 0.1),
                              radius: 20,
                              child: Icon(cat['icon'] as IconData, color: cat['color'] as Color, size: 22),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            cat['title'] as String,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            countText,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.white))),
        ),
      ),
    );
  }
}
