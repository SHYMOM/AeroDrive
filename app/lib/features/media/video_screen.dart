import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/features/drive/providers/drive_providers.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/core/theme/app_colors.dart';
import 'package:aerodrive/features/preview/preview_router.dart';

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
          icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
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
                  Icon(Icons.videocam_outlined, size: 48, color: AppColors.fileVideo),
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

class _VideoItem extends StatelessWidget {
  final FileData file;
  final List<FileData> siblings;

  const _VideoItem({required this.file, required this.siblings});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.fileVideo.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.videocam_outlined, color: AppColors.fileVideo, size: 22),
      ),
      title: Text(file.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.onSurface)),
      subtitle: Text(
        file.size != null ? '\${_formatFileSize(file.size!)}' : 'Unknown size',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant),
      ),
      onTap: () => PreviewRouter.openPreview(context, file, siblings: siblings),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '\$bytes B';
    if (bytes < 1024 * 1024) return '\${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '\${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '\${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

final videosProvider = FutureProvider.family<Map<String, dynamic>, String?>((ref, folderId) async {
  final db = ref.watch(databaseProvider);

  List<FileData> videoFiles = [];

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