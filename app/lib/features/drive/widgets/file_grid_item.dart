import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:aerodrive/features/preview/preview_router.dart';
import 'package:aerodrive/features/sharing/share_dialog.dart';
import 'package:aerodrive/features/tags/tag_dialog.dart';
import 'package:aerodrive/features/drive/widgets/file_type_icon.dart';
import 'package:aerodrive/features/drive/widgets/file_tags_row.dart';
import 'package:aerodrive/features/gallery/thumbnail_service.dart';
import 'package:drift/drift.dart' as drift;

class FileGridItem extends ConsumerWidget {
  final FileData file;
  
  const FileGridItem({super.key, required this.file});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () {
        PreviewRouter.openPreview(context, file);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              // Background Image if available
              if (file.mimeType?.startsWith('image/') == true)
                Positioned.fill(
                  child: FutureBuilder<File?>(
                    future: ref.read(thumbnailServiceProvider).getThumbnail(file),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data != null) {
                        return Image.file(
                          snapshot.data!,
                          fit: BoxFit.cover,
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                
              // Gradient Overlay for readability
              if (file.mimeType?.startsWith('image/') == true)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.7),
                        ],
                      ),
                    ),
                  ),
                ),

              // Content
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 20, color: Colors.white),
                      padding: EdgeInsets.zero,
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
                        const PopupMenuItem(value: 'download', child: Text('Download')),
                        const PopupMenuItem(value: 'share', child: Text('Share Link')),
                        const PopupMenuItem(value: 'tags', child: Text('Tags')),
                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (file.mimeType?.startsWith('image/') != true)
                    FileTypeIcon(
                      mimeType: file.mimeType,
                      fileName: file.name,
                      size: 48,
                    ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      file.name, 
                      textAlign: TextAlign.center, 
                      maxLines: 2, 
                      overflow: TextOverflow.ellipsis, 
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 4),
                  FileTagsRow(fileId: file.id),
                  const SizedBox(height: 8),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
