import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:aerodrive/features/preview/preview_router.dart';
import 'package:aerodrive/features/sharing/share_dialog.dart';
import 'package:aerodrive/features/tags/tag_dialog.dart';
import 'package:aerodrive/features/drive/widgets/file_type_icon.dart';
import 'package:aerodrive/features/gallery/thumbnail_service.dart';
import 'package:drift/drift.dart' as drift;
import 'package:aerodrive/core/theme/app_colors.dart';

class FileListItem extends ConsumerWidget {
  final FileData file;
  const FileListItem({super.key, required this.file});

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateString = file.createdAt != null 
        ? DateFormat('MMM dd, yyyy hh:mm a').format(file.createdAt!)
        : 'Unknown Date';
    final sizeString = _formatBytes(file.size ?? 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: SizedBox(
          width: 56,
          height: 56,
          child: (file.mimeType?.startsWith('image/') == true || file.mimeType?.startsWith('video/') == true)
            ? FutureBuilder<File?>(
                future: ref.read(thumbnailServiceProvider).getThumbnail(file),
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data != null) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(snapshot.data!, fit: BoxFit.cover),
                          if (file.mimeType?.startsWith('video/') == true)
                            const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 28)),
                        ],
                      ),
                    );
                  }
                  return FileTypeIcon(mimeType: file.mimeType, fileName: file.name, size: 56);
                },
              )
            : FileTypeIcon(mimeType: file.mimeType, fileName: file.name, size: 56),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                file.name, 
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.onSurface, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (file.isFavorite)
              const Padding(
                padding: EdgeInsets.only(left: 8.0),
                child: Icon(Icons.star_border, color: AppColors.onSurfaceVariant, size: 16),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6.0),
          child: Text(
            '$sizeString • $dateString', 
            style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant),
          ),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: AppColors.onSurfaceVariant),
          color: AppColors.surfaceElevated,
          onSelected: (value) async {
            if (value == 'download') {
              final db = ref.read(databaseProvider);
              await db.into(db.transferQueue).insert(
                TransferQueueCompanion.insert(
                  id: const Uuid().v4(),
                  fileId: drift.Value(file.id),
                  type: const drift.Value('DOWNLOAD_FILE'),
                  status: const drift.Value('PENDING'),
                  priority: const drift.Value(1),
                  createdAt: drift.Value(DateTime.now()),
                )
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Queued ${file.name} for download...')));
              }
            } else if (value == 'share') {
              showDialog(
                context: context,
                builder: (context) => ShareDialog(file: file),
              );
            } else if (value == 'tags') {
              TagDialog.show(context, file);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'download', child: Text('Download', style: TextStyle(color: AppColors.onSurface))),
            const PopupMenuItem(value: 'share', child: Text('Share Link', style: TextStyle(color: AppColors.onSurface))),
            const PopupMenuItem(value: 'tags', child: Text('Tags', style: TextStyle(color: AppColors.onSurface))),
            const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.error))),
          ],
        ),
        onTap: () {
          PreviewRouter.openPreview(context, file);
        },
      ),
    );
  }
}
