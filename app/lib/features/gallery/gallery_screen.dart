import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/db/database.dart';
import '../preview/preview_router.dart';
import 'thumbnail_service.dart';

final mediaFilesProvider = FutureProvider<List<FileData>>((ref) async {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.files)
    ..where((f) => f.mimeType.like('image/%') | f.mimeType.like('video/%'))
    ..where((f) => f.deletedAt.isNull())
    ..orderBy([(t) => drift.OrderingTerm.desc(t.createdAt)]);
  return query.get();
});

class GalleryScreenContent extends ConsumerWidget {
  const GalleryScreenContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaAsync = ref.watch(mediaFilesProvider);

    return mediaAsync.when(
        data: (mediaFiles) {
          if (mediaFiles.isEmpty) {
            return const Center(child: Text('No photos or videos yet.'));
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(mediaFilesProvider);
            },
            child: GridView.builder(
              padding: const EdgeInsets.all(4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: mediaFiles.length,
              itemBuilder: (context, index) {
                final file = mediaFiles[index];
                return _GalleryItem(file: file);
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }
}

class _GalleryItem extends ConsumerStatefulWidget {
  const _GalleryItem({required this.file});
  final FileData file;

  @override
  ConsumerState<_GalleryItem> createState() => _GalleryItemState();
}

class _GalleryItemState extends ConsumerState<_GalleryItem> {
  File? _thumbnail;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    final thumb = await ref.read(thumbnailServiceProvider).getThumbnail(widget.file);
    if (mounted) {
      setState(() {
        _thumbnail = thumb;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: () {
        PreviewRouter.openPreview(context, widget.file);
      },
      child: ColoredBox(
        color: Colors.black12,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_thumbnail != null)
              Image.file(_thumbnail!, fit: BoxFit.cover)
            else if (widget.file.mimeType?.startsWith('video/') == true)
              const Icon(Icons.videocam, color: Colors.white, size: 48)
            else if (_isLoading)
              const Center(child: CircularProgressIndicator(strokeWidth: 2))
            else
              const Icon(Icons.image_not_supported, color: Colors.grey),
            if (widget.file.mimeType?.startsWith('video/') == true)
              const Positioned(
                bottom: 4,
                left: 4,
                child: Icon(Icons.play_circle_outline, color: Colors.white),
              ),
          ],
        ),
      ),
    );
}
