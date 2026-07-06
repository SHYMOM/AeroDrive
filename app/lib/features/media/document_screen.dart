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

class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentFolderId = ref.watch(currentFolderIdProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Documents'),
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ref.watch(documentsProvider(currentFolderId)).when(
        data: (result) {
          final documents = result['files'] as List<FileData>;

          if (documents.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.description_outlined, size: 48, color: AppColors.fileDocument),
                  const SizedBox(height: 16),
                  Text('No documents found', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.onSurface)),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: documents.length,
            itemBuilder: (context, index) {
              final file = documents[index];
              return _DocumentItem(file: file);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }
}

class _DocumentItem extends ConsumerWidget {

  const _DocumentItem({required this.file});
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
                    color: AppColors.fileDocument.withValues(alpha: 0.1),
                    child: const Icon(Icons.description_outlined, color: AppColors.fileDocument, size: 22),
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

// Provider to fetch documents (PDF, text, etc.)
final documentsProvider = FutureProvider.family<Map<String, dynamic>, String?>((ref, folderId) async {
  final db = ref.watch(databaseProvider);

  final List<FileData> documentFiles = [];

  if (folderId == null) {
    // Get all documents from root level
    final files = await (db.select(db.files)..where((f) => f.deletedAt.isNull())).get();
    for (final file in files) {
      final mime = file.mimeType ?? '';
      if (mime.contains('pdf') ||
          mime.startsWith('text/') ||
          mime.contains('document') ||
          mime.contains('msword') ||
          mime.contains('spreadsheet') ||
          mime.contains('presentation')) {
        documentFiles.add(file);
      }
    }
  } else {
    // Get documents from specific folder
    final files = await (db.select(db.files)..where((f) => f.folderId.equals(folderId) & f.deletedAt.isNull())).get();
    for (final file in files) {
      final mime = file.mimeType ?? '';
      if (mime.contains('pdf') ||
          mime.startsWith('text/') ||
          mime.contains('document') ||
          mime.contains('msword') ||
          mime.contains('spreadsheet') ||
          mime.contains('presentation')) {
        documentFiles.add(file);
      }
    }
  }

  return {'files': documentFiles};
});