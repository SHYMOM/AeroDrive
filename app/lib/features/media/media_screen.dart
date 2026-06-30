import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/features/gallery/thumbnail_service.dart';
import 'package:aerodrive/features/preview/preview_router.dart';
import 'package:drift/drift.dart' as drift;

enum MediaType { photo, video }

final currentMediaFolderProvider = StateProvider<String?>((ref) => null);
final mediaFolderStackProvider = StateProvider<List<String?>>((ref) => []);

final allMediaFoldersProvider = FutureProvider<List<FolderData>>((ref) async {
  final db = ref.watch(databaseProvider);
  final mediaIds = await (db.select(db.files)
    ..where((f) => (f.mimeType.like('image/%') | f.mimeType.like('video/%')))
    ..where((f) => f.deletedAt.isNull())
  ).get();
  final folderIds = mediaIds.map((f) => f.folderId).whereType<String>().toSet().toList();
  if (folderIds.isEmpty) return [];
  final folders = await (db.select(db.folders)..where((f) => f.id.isIn(folderIds))..where((f) => f.deletedAt.isNull())).get();
  folders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return folders;
});

final recentMediaProvider = FutureProvider<List<FileData>>((ref) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.files)
    ..where((f) => (f.mimeType.like('image/%') | f.mimeType.like('video/%')))
    ..where((f) => f.deletedAt.isNull())
    ..orderBy([(t) => drift.OrderingTerm.desc(t.createdAt)])
    ..limit(50)
  ).get();
});

final mediaFilesByFolderProvider = FutureProvider.family<List<FileData>, String?>((ref, folderId) async {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.files)
    ..where((f) => (f.mimeType.like('image/%') | f.mimeType.like('video/%')))
    ..where((f) => f.deletedAt.isNull())
    ..orderBy([(t) => drift.OrderingTerm.desc(t.createdAt)]);
  if (folderId == null) {
    query.where((f) => f.folderId.isNull());
  } else {
    query.where((f) => f.folderId.equals(folderId));
  }
  return query.get();
});

class MediaScreen extends ConsumerStatefulWidget {
  const MediaScreen({super.key});

  @override
  ConsumerState<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends ConsumerState<MediaScreen> {
  @override
  Widget build(BuildContext context) {
    final currentFolderId = ref.watch(currentMediaFolderProvider);
    final theme = Theme.of(context);

    if (currentFolderId != null) {
      return _buildFolderMediaView(currentFolderId);
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Media'),
          bottom: TabBar(
            tabs: const [
              Tab(text: 'Photos', icon: Icon(Icons.photo_outlined)),
              Tab(text: 'Videos', icon: Icon(Icons.videocam_outlined)),
            ],
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
            indicatorColor: theme.colorScheme.primary,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: () {
                ref.invalidate(recentMediaProvider);
                ref.invalidate(allMediaFoldersProvider);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Media refreshed'), duration: Duration(seconds: 1)),
                  );
                }
              },
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _MediaTimeline(type: MediaType.photo),
            _MediaTimeline(type: MediaType.video),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderMediaView(String folderId) {
    final actualId = folderId == '__root__' ? null : folderId;
    return Scaffold(
      appBar: AppBar(
        title: _FolderBreadcrumb(folderId: folderId),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            final stack = ref.read(mediaFolderStackProvider);
            if (stack.isNotEmpty) {
              final prev = stack.removeLast();
              ref.read(currentMediaFolderProvider.notifier).state = prev;
              ref.read(mediaFolderStackProvider.notifier).update((s) => s);
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(mediaFilesByFolderProvider);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Media refreshed'), duration: Duration(seconds: 1)),
                );
              }
            },
          ),
        ],
      ),
      body: _buildMediaGrid(actualId),
    );
  }

  Widget _buildMediaGrid(String? folderId) {
    final filesAsync = ref.watch(mediaFilesByFolderProvider(folderId));
    return filesAsync.when(
      data: (mediaFiles) {
        if (mediaFiles.isEmpty) {
          return const Center(child: Text('No media in this folder.'));
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(mediaFilesByFolderProvider);
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
              return _GalleryItem(file: mediaFiles[index]);
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }
}

class _MediaTimeline extends ConsumerWidget {
  final MediaType type;
  const _MediaTimeline({required this.type});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentAsync = ref.watch(recentMediaProvider);
    final foldersAsync = ref.watch(allMediaFoldersProvider);
    final theme = Theme.of(context);

    return recentAsync.when(
      data: (allRecent) {
        final filtered = allRecent.where((f) {
          if (type == MediaType.photo) return f.mimeType?.startsWith('image/') == true;
          return f.mimeType?.startsWith('video/') == true;
        }).toList();

        return foldersAsync.when(
          data: (folders) {
            if (filtered.isEmpty && folders.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      type == MediaType.photo ? Icons.photo_outlined : Icons.videocam_outlined,
                      size: 64,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No ${type == MediaType.photo ? 'photos' : 'videos'} yet',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Upload media files to see them here',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(mediaFilesByFolderProvider);
              },
              child: CustomScrollView(
                slivers: [
                if (filtered.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        'Recent',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: 4,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _GalleryItem(file: filtered[index]),
                      childCount: filtered.length,
                    ),
                  ),
                ],
                if (folders.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                      child: Text(
                        'Folders',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final folder = folders[index];
                        return ListTile(
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.folder_rounded, color: theme.colorScheme.primary, size: 24),
                          ),
                          title: Text(folder.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500)),
                          trailing: Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
                          onTap: () {
                            final stack = ref.read(mediaFolderStackProvider);
                            final currentFid = ref.read(currentMediaFolderProvider);
                            ref.read(mediaFolderStackProvider.notifier).state = [...stack, currentFid];
                            ref.read(currentMediaFolderProvider.notifier).state = folder.id;
                          },
                        );
                      },
                      childCount: folders.length,
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          );
        },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Error: $err')),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }
}

final currentMediaFolderNameProvider = FutureProvider<String?>((ref) async {
  final folderId = ref.watch(currentMediaFolderProvider);
  if (folderId == '__root__' || folderId == null) return null;
  final db = ref.read(databaseProvider);
  final results = await (db.select(db.folders)..where((f) => f.id.equals(folderId))).get();
  return results.isNotEmpty ? results.first.name : null;
});

class _FolderBreadcrumb extends ConsumerWidget {
  final String? folderId;
  const _FolderBreadcrumb({required this.folderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (folderId == '__root__' || folderId == null) {
      return const Text('Media');
    }
    final nameAsync = ref.watch(currentMediaFolderNameProvider);
    return nameAsync.when(
      data: (name) => Text(name ?? 'Media'),
      loading: () => const Text('Media'),
      error: (_, __) => const Text('Media'),
    );
  }
}

class _GalleryItem extends ConsumerStatefulWidget {
  final FileData file;
  const _GalleryItem({required this.file});

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
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => PreviewRouter.openPreview(context, widget.file),
      child: Container(
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
}
