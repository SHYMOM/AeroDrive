import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/db/database.dart';
import '../drive/providers/drive_providers.dart';
import '../drive/widgets/press_and_hold_preview.dart';
import '../gallery/thumbnail_service.dart';
import '../preview/preview_router.dart';

class VideosScreen extends ConsumerWidget {
  const VideosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentFolderId = ref.watch(currentFolderIdProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Videos'),
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ref.watch(videosProvider(currentFolderId)).when(
        data: (result) {
          final videos = result['files'] as List<FileData>;

          if (videos.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.videocam_outlined, size: 48, color: AppColors.fileVideo),
                  const SizedBox(height: 16),
                  Text('No videos found', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.onSurface)),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: videos.length,
            itemBuilder: (context, index) {
              final file = videos[index];
              return _VideoItem(file: file, siblings: videos);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }
}

class _VideoItem extends ConsumerWidget {

  const _VideoItem({required this.file, required this.siblings});
  final FileData file;
  final List<FileData> siblings;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PressAndHoldPreview(
        file: file,
        child: ListTile(
          leading: SizedBox(
            width: 44,
            height: 44,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: FutureBuilder<File?>(
                future: ref.read(thumbnailServiceProvider).getThumbnail(file),
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data != null) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(snapshot.data!, fit: BoxFit.cover),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.black45,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return Container(
                    color: AppColors.fileVideo.withValues(alpha: 0.1),
                    child: const Icon(Icons.videocam_outlined, color: AppColors.fileVideo, size: 22),
                  );
                },
              ),
            ),
          ),
          title: Text(file.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.onSurface)),
          subtitle: Text(
            file.size != null ? _formatFileSize(file.size!) : 'Unknown size',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant),
          ),
          onTap: () => PreviewRouter.openPreview(context, file, siblings: siblings),
        ),
      );

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

final videosProvider = FutureProvider.family<Map<String, dynamic>, String?>((ref, folderId) async {
  final db = ref.watch(databaseProvider);

  final List<FileData> videoFiles = [];

  if (folderId == null) {
    // Get all videos from root level
    final files = await (db.select(db.files)..where((f) => f.deletedAt.isNull())).get();
    for (final file in files) {
      if (file.mimeType?.startsWith('video/') == true) {
        videoFiles.add(file);
      }
    }
  } else {
    // Get videos from specific folder
    final files = await (db.select(db.files)..where((f) => f.folderId.equals(folderId))).get();
    for (final file in files) {
      if (file.mimeType?.startsWith('video/') == true) {
        videoFiles.add(file);
      }
    }
  }

  return {'files': videoFiles};
});