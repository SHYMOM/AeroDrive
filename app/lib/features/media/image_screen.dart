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

class ImagesScreen extends ConsumerWidget {
  const ImagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentFolderId = ref.watch(currentFolderIdProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Images'),
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ref.watch(imagesProvider(currentFolderId)).when(
        data: (result) {
          final images = result['files'] as List<FileData>;

          if (images.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.image_outlined, size: 48, color: AppColors.fileImage),
                  const SizedBox(height: 16),
                  Text('No images found', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.onSurface)),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: images.length,
            itemBuilder: (context, index) {
              final file = images[index];
              return _ImageItem(file: file, siblings: images);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => const Center(child: Text(r'Error: $err')),
      ),
    );
  }
}

class _ImageItem extends ConsumerWidget {

  const _ImageItem({required this.file, required this.siblings});
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
                    return Image.file(snapshot.data!, fit: BoxFit.cover);
                  }
                  return Container(
                    color: AppColors.fileImage.withValues(alpha: 0.1),
                    child: Icon(Icons.image_outlined, color: AppColors.fileImage, size: 22),
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

final imagesProvider = FutureProvider.family<Map<String, dynamic>, String?>((ref, folderId) async {
  final db = ref.watch(databaseProvider);

  final List<FileData> imageFiles = [];

  if (folderId == null) {
    // Get all images from root level
    final files = await (db.select(db.files)..where((f) => f.deletedAt.isNull())).get();
    for (final file in files) {
      if (file.mimeType?.startsWith('image/') == true) {
        imageFiles.add(file);
      }
    }
  } else {
    // Get images from specific folder
    final files = await (db.select(db.files)..where((f) => f.folderId.equals(folderId))).get();
    for (final file in files) {
      if (file.mimeType?.startsWith('image/') == true) {
        imageFiles.add(file);
      }
    }
  }

  return {'files': imageFiles};
});