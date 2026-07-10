import 'dart:io';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/db/database.dart';
import '../drive/providers/drive_providers.dart';
import '../drive/widgets/press_and_hold_preview.dart';
import '../gallery/thumbnail_service.dart';
import '../preview/preview_router.dart';

class AudiosScreen extends ConsumerWidget {
  const AudiosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentFolderId = ref.watch(currentFolderIdProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Audios'),
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ref.watch(audiosProvider(currentFolderId)).when(
        data: (result) {
          final audios = result['files'] as List<FileData>;

          if (audios.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.audiotrack_outlined, size: 48, color: AppColors.fileAudio),
                  const SizedBox(height: 16),
                  Text('No audio files found', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.onSurface)),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: audios.length,
            itemBuilder: (context, index) {
              final file = audios[index];
              return _AudioItem(file: file);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }
}

class _AudioItem extends ConsumerWidget {

  const _AudioItem({required this.file});
  final FileData file;

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
                    color: AppColors.fileAudio.withValues(alpha: 0.1),
                    child: Icon(Icons.audiotrack_outlined, color: AppColors.fileAudio, size: 22),
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
          onTap: () => PreviewRouter.openPreview(context, file),
        ),
      );

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

final audiosProvider = FutureProvider.family<Map<String, dynamic>, String?>((ref, folderId) async {
  final db = ref.watch(databaseProvider);

  final List<FileData> audioFiles = [];

  if (folderId == null) {
    final files = await (db.select(db.files)..where((f) => f.deletedAt.isNull())).get();
    for (final file in files) {
      if (file.mimeType?.startsWith('audio/') == true) {
        audioFiles.add(file);
      }
    }
  } else {
    final files = await (db.select(db.files)..where((f) => f.folderId.equals(folderId) & f.deletedAt.isNull())).get();
    for (final file in files) {
      if (file.mimeType?.startsWith('audio/') == true) {
        audioFiles.add(file);
      }
    }
  }

  return {'files': audioFiles};
});
