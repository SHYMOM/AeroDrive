import 'dart:io';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/db/database.dart';
import '../gallery/thumbnail_service.dart';
import '../preview/preview_router.dart';

enum MediaTab { photos, albums, explore }
enum PhotosTimelineView { years, months, days, all }

final mediaSortProvider = StateProvider<bool>((ref) => true); // true = Newest first, false = Oldest first
final mediaColumnCountProvider = StateProvider<int>((ref) => 4);

final allMediaFilesProvider = FutureProvider<List<FileData>>((ref) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.files)
    ..where((f) => (f.mimeType.like('image/%') | f.mimeType.like('video/%')))
    ..where((f) => f.deletedAt.isNull())
    ..orderBy([(t) => drift.OrderingTerm.desc(t.createdAt)])
  ).get();
});

final allMediaFoldersProvider = FutureProvider<List<FolderData>>((ref) async {
  final db = ref.watch(databaseProvider);
  final mediaFiles = await (db.select(db.files)
    ..where((f) => (f.mimeType.like('image/%') | f.mimeType.like('video/%')))
    ..where((f) => f.deletedAt.isNull())
  ).get();
  final folderIds = mediaFiles.map((f) => f.folderId).whereType<String>().toSet().toList();
  if (folderIds.isEmpty) return [];
  return (db.select(db.folders)..where((f) => f.id.isIn(folderIds))..where((f) => f.deletedAt.isNull())).get();
});

// Explore Page data provider (using real database statistics where available)
final exploreDataProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final db = ref.watch(databaseProvider);
  
  // People (unique face clusters)
  final faceClusters = await db.select(db.faceClusters).get();
  final int peopleCount = faceClusters.length;
  
  // Find cover files for People (cropped face files of up to 4 face clusters)
  final List<String> peopleCropPaths = [];
  try {
    final cacheDir = await getApplicationSupportDirectory();
    final facesDir = Directory('${cacheDir.path}/faces');
    if (await facesDir.exists()) {
      final allFaceFiles = facesDir.listSync().whereType<File>().toList();
      for (final cluster in faceClusters.take(4)) {
        final match = allFaceFiles.firstWhereOrNull(
          (f) => f.path.split(Platform.pathSeparator).last.startsWith(cluster.id),
        );
        if (match != null) {
          peopleCropPaths.add(match.path);
        }
      }
    }
  } catch (e) {
    // ignore
  }

  // Places (unique places)
  final places = await db.select(db.places).get();
  final int placesCount = places.length;

  // Find cover files for Places (up to 4 images that have associated places)
  final filePlaces = await db.select(db.filePlaces).get();
  final placeFileIds = filePlaces.map((fp) => fp.fileId).toSet().toList();
  final List<FileData> placeCoverFiles = [];
  if (placeFileIds.isNotEmpty) {
    try {
      final query = await (db.select(db.files)
        ..where((f) => f.id.isIn(placeFileIds.take(4).toList()))
      ).get();
      placeCoverFiles.addAll(query);
    } catch (_) {}
  }
  
  // Smart tags
  final allTags = await db.select(db.tags).get();
  final smartTagsList = allTags.where((t) => t.source != 'USER').toList();
  
  final List<Map<String, dynamic>> smartTags = [];
  if (smartTagsList.isNotEmpty) {
    for (final tag in smartTagsList) {
      final fileTags = await (db.select(db.fileTags)..where((ft) => ft.tagId.equals(tag.id))).get();
      FileData? coverFile;
      if (fileTags.isNotEmpty) {
        final fileQuery = await (db.select(db.files)..where((f) => f.id.equals(fileTags.first.fileId))).getSingleOrNull();
        coverFile = fileQuery;
      }
      smartTags.add({
        'name': tag.name,
        'count': fileTags.length,
        'cover': coverFile,
      });
    }
  } else {
    smartTags.addAll([
      {'name': 'Food', 'count': 0, 'cover': null},
      {'name': 'Buildings', 'count': 0, 'cover': null},
      {'name': 'Ocean', 'count': 0, 'cover': null},
    ]);
  }
  
  // Memory (Throwback featured older file)
  final allFiles = await (db.select(db.files)
    ..where((f) => f.mimeType.like('image/%') | f.mimeType.like('video/%'))
    ..where((f) => f.deletedAt.isNull())
    ..orderBy([(t) => drift.OrderingTerm.desc(t.createdAt)])
    ..limit(15)
  ).get();
  final FileData? memoryFile = allFiles.isNotEmpty ? allFiles.last : null;

  return {
    'peopleCount': peopleCount,
    'placesCount': placesCount,
    'peopleCropPaths': peopleCropPaths,
    'placeCoverFiles': placeCoverFiles,
    'smartTags': smartTags,
    'memoryFile': memoryFile,
  };
});

class MediaScreen extends ConsumerStatefulWidget {
  const MediaScreen({super.key});

  @override
  ConsumerState<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends ConsumerState<MediaScreen> {
  MediaTab _currentTab = MediaTab.photos;
  PhotosTimelineView _timelineView = PhotosTimelineView.all;

  FolderData? _selectedAlbum;
  String _exploreSearchQuery = '';

  int? _filterYear;
  String? _filterMonth;
  String? _mediaTypeFilter;

  @override
  Widget build(BuildContext context) {
    // Intercept hardware/system back button if an album is selected
    return PopScope(
      canPop: _selectedAlbum == null && _mediaTypeFilter == null,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_selectedAlbum != null) {
          setState(() {
            _selectedAlbum = null;
          });
        }
        if (_mediaTypeFilter != null) {
          setState(() {
            _mediaTypeFilter = null;
          });
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              
              if (_filterYear != null || _filterMonth != null || _selectedAlbum != null)
                _buildActiveFiltersHeader(),

              Expanded(
                child: RefreshIndicator(
                  color: AppColors.primary,
                  backgroundColor: AppColors.surfaceElevated,
                  onRefresh: () async {
                    ref.invalidate(allMediaFilesProvider);
                    ref.invalidate(allMediaFoldersProvider);
                    ref.invalidate(exploreDataProvider);
                    await Future.delayed(const Duration(milliseconds: 500));
                  },
                  child: _buildBody(),
                ),
              ),

              _buildBottomSubNavBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    if (_currentTab == MediaTab.photos) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                if (_mediaTypeFilter != null)
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _mediaTypeFilter = null;
                      });
                    },
                  ),
                Text(
                  _mediaTypeFilter == 'image/' ? 'All Images' : _mediaTypeFilter == 'video/' ? 'All Videos' : 'All media',
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Row(
              children: [
                IconButton(
                  icon: Icon(Icons.refresh, color: AppColors.onSurfaceVariant),
                  onPressed: () {
                    ref.invalidate(allMediaFilesProvider);
                    ref.invalidate(allMediaFoldersProvider);
                  },
                ),
                _buildOptionsMenu(),
              ],
            ),
          ],
        ),
      );
    } else if (_currentTab == MediaTab.albums) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _selectedAlbum != null ? _selectedAlbum!.name : 'Albums',
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                if (_selectedAlbum != null)
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _selectedAlbum = null;
                      });
                    },
                  )
                else ...[
                  IconButton(
                    icon: Icon(Icons.refresh, color: AppColors.onSurfaceVariant),
                    onPressed: () {
                      ref.invalidate(allMediaFilesProvider);
                      ref.invalidate(allMediaFoldersProvider);
                    },
                  ),
                  _buildOptionsMenu(),
                ]
              ],
            ),
          ],
        ),
      );
    } else {
      // Explore search bar with trailing popup menu
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Times, places, file names...',
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                    prefixIcon: Icon(Icons.search, color: AppColors.primary),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _exploreSearchQuery = val.trim();
                    });
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: AppColors.onSurfaceVariant),
              color: AppColors.surfaceElevated,
              onSelected: (val) {
                if (val == 'refresh_ai') {
                  ref.invalidate(exploreDataProvider);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Refreshed local AI metadata.')),
                  );
                } else if (val == 'clear_history') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cleared explore history.')),
                  );
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'refresh_ai', child: Text('Refresh Local AI', style: TextStyle(color: Colors.white))),
                const PopupMenuItem(value: 'clear_history', child: Text('Clear History', style: TextStyle(color: Colors.white))),
              ],
            ),
          ],
        ),
      );
    }
  }

  Widget _buildActiveFiltersHeader() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          const Text('Filtered by: ', style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(width: 8),
          if (_filterYear != null)
            Chip(
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              side: const BorderSide(color: AppColors.primary),
              label: Text('$_filterYear', style: const TextStyle(color: AppColors.primary, fontSize: 11)),
              deleteIcon: const Icon(Icons.close, size: 12, color: AppColors.primary),
              onDeleted: () {
                setState(() {
                  _filterYear = null;
                });
              },
            ),
          if (_filterMonth != null)
            Chip(
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              side: const BorderSide(color: AppColors.primary),
              label: Text(_filterMonth!, style: const TextStyle(color: AppColors.primary, fontSize: 11)),
              deleteIcon: const Icon(Icons.close, size: 12, color: AppColors.primary),
              onDeleted: () {
                setState(() {
                  _filterMonth = null;
                });
              },
            ),
          if (_selectedAlbum != null)
            Chip(
              backgroundColor: AppColors.secondary.withValues(alpha: 0.15),
              side: const BorderSide(color: AppColors.secondary),
              label: Text(_selectedAlbum!.name, style: const TextStyle(color: AppColors.secondary, fontSize: 11)),
              deleteIcon: const Icon(Icons.close, size: 12, color: AppColors.secondary),
              onDeleted: () {
                setState(() {
                  _selectedAlbum = null;
                });
              },
            ),
        ],
      ),
    );

  Widget _buildOptionsMenu() {
    final newestFirst = ref.watch(mediaSortProvider);
    final columnsCount = ref.watch(mediaColumnCountProvider);

    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: AppColors.onSurfaceVariant),
      color: AppColors.surfaceElevated,
      onSelected: (value) {
        if (value == 'sort_newest') {
          ref.read(mediaSortProvider.notifier).state = true;
        } else if (value == 'sort_oldest') {
          ref.read(mediaSortProvider.notifier).state = false;
        } else if (value == 'columns_2') {
          ref.read(mediaColumnCountProvider.notifier).state = 2;
        } else if (value == 'columns_3') {
          ref.read(mediaColumnCountProvider.notifier).state = 3;
        } else if (value == 'columns_4') {
          ref.read(mediaColumnCountProvider.notifier).state = 4;
        } else if (value == 'columns_5') {
          ref.read(mediaColumnCountProvider.notifier).state = 5;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'sort_newest',
          child: Row(
            children: [
              Icon(Icons.arrow_downward, color: newestFirst ? AppColors.primary : Colors.white54, size: 18),
              const SizedBox(width: 8),
              Text('Newest First', style: TextStyle(color: newestFirst ? AppColors.primary : Colors.white)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'sort_oldest',
          child: Row(
            children: [
              Icon(Icons.arrow_upward, color: !newestFirst ? AppColors.primary : Colors.white54, size: 18),
              const SizedBox(width: 8),
              Text('Oldest First', style: TextStyle(color: !newestFirst ? AppColors.primary : Colors.white)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'columns_2',
          child: Text('2 Columns', style: TextStyle(color: columnsCount == 2 ? AppColors.primary : Colors.white)),
        ),
        PopupMenuItem(
          value: 'columns_3',
          child: Text('3 Columns', style: TextStyle(color: columnsCount == 3 ? AppColors.primary : Colors.white)),
        ),
        PopupMenuItem(
          value: 'columns_4',
          child: Text('4 Columns', style: TextStyle(color: columnsCount == 4 ? AppColors.primary : Colors.white)),
        ),
        PopupMenuItem(
          value: 'columns_5',
          child: Text('5 Columns', style: TextStyle(color: columnsCount == 5 ? AppColors.primary : Colors.white)),
        ),
      ],
    );
  }

  Widget _buildBody() {
    switch (_currentTab) {
      case MediaTab.photos:
        return _buildPhotosTab();
      case MediaTab.albums:
        return _buildAlbumsTab();
      case MediaTab.explore:
        return _buildExploreTab();
    }
  }

  // --- PHOTOS TIMELINE VIEW ---
  Widget _buildPhotosTab() {
    final mediaAsync = ref.watch(allMediaFilesProvider);

    return mediaAsync.when(
      data: (allFiles) {
        if (allFiles.isEmpty) {
          return _buildEmptyState(Icons.photo_library_outlined, 'No photos or videos found');
        }

        var files = allFiles;
        if (_mediaTypeFilter != null) {
          files = files.where((f) => f.mimeType?.startsWith(_mediaTypeFilter!) == true).toList();
        }
        if (_filterYear != null) {
          files = files.where((f) => f.createdAt != null && f.createdAt!.year == _filterYear).toList();
        }
        if (_filterMonth != null) {
          files = files.where((f) => f.createdAt != null && DateFormat('MMMM yyyy').format(f.createdAt!) == _filterMonth).toList();
        }

        final newestFirst = ref.watch(mediaSortProvider);
        files.sort((a, b) {
          final da = a.createdAt ?? DateTime(0);
          final db = b.createdAt ?? DateTime(0);
          return newestFirst ? db.compareTo(da) : da.compareTo(db);
        });

        return Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 70), 
              child: _buildTimelineContent(files),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildTimelineSelectorPill(),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.white))),
    );
  }

  Widget _buildTimelineContent(List<FileData> files) {
    if (_timelineView == PhotosTimelineView.all || _timelineView == PhotosTimelineView.days) {
      final Map<String, List<FileData>> grouped = {};
      for (final f in files) {
        final date = f.photoTakenAt ?? f.createdAt ?? DateTime.now();
        final key = DateFormat('yMMMMd').format(date);
        grouped.putIfAbsent(key, () => []).add(f);
      }

      final keys = grouped.keys.toList();
      final cols = _timelineView == PhotosTimelineView.all ? ref.watch(mediaColumnCountProvider) : 3;

      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: keys.length,
        itemBuilder: (context, idx) {
          final key = keys[idx];
          final dayFiles = grouped[key]!;
          
          final parsedDate = DateFormat('yMMMMd').parse(key);
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final yesterday = today.subtract(const Duration(days: 1));
          final dateToCheck = DateTime(parsedDate.year, parsedDate.month, parsedDate.day);
          
          String headerText = DateFormat('MMMM d').format(parsedDate);
          if (dateToCheck == today) {
            headerText = 'Today';
          } else if (dateToCheck == yesterday) headerText = 'Yesterday';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(
                  headerText,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: dayFiles.length,
                itemBuilder: (context, index) => _GalleryItem(file: dayFiles[index], siblings: dayFiles),
              ),
            ],
          );
        },
      );
    } else if (_timelineView == PhotosTimelineView.months) {
      final Map<String, List<FileData>> grouped = {};
      for (final f in files) {
        final date = f.photoTakenAt ?? f.createdAt ?? DateTime.now();
        final key = DateFormat('MMMM yyyy').format(date);
        grouped.putIfAbsent(key, () => []).add(f);
      }

      final keys = grouped.keys.toList();

      return GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.8,
        ),
        itemCount: keys.length,
        itemBuilder: (context, idx) {
          final key = keys[idx];
          final monthFiles = grouped[key]!;
          final latestFile = monthFiles.first;

          final parsedDate = DateFormat('MMMM yyyy').parse(key);
          final shortMonth = DateFormat('MMM').format(parsedDate);

          return GestureDetector(
            onTap: () {
              setState(() {
                _filterMonth = key;
                _timelineView = PhotosTimelineView.days;
              });
            },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _ThumbnailOrCover(file: latestFile),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 12,
                    left: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shortMonth,
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${monthFiles.length} photos',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } else {
      final Map<int, List<FileData>> grouped = {};
      for (final f in files) {
        final date = f.photoTakenAt ?? f.createdAt ?? DateTime.now();
        grouped.putIfAbsent(date.year, () => []).add(f);
      }

      final keys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: keys.length,
        itemBuilder: (context, idx) {
          final key = keys[idx];
          final yearFiles = grouped[key]!;
          final latestFile = yearFiles.first;

          return GestureDetector(
            onTap: () {
              setState(() {
                _filterYear = key;
                _timelineView = PhotosTimelineView.months;
              });
            },
            child: Container(
              height: 200,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _ThumbnailOrCover(file: latestFile),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 20,
                    left: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$key',
                          style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${yearFiles.length} items',
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
  }

  Widget _buildTimelineSelectorPill() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: PhotosTimelineView.values.map((view) {
          final isSelected = _timelineView == view;
          return GestureDetector(
            onTap: () {
              setState(() {
                _timelineView = view;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                view.name[0].toUpperCase() + view.name.substring(1),
                style: TextStyle(
                  color: isSelected ? AppColors.primary : Colors.white70,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );

  // --- ALBUMS VIEW ---
  Widget _buildAlbumsTab() {
    if (_selectedAlbum != null) {
      final filesAsync = ref.watch(allMediaFilesProvider);
      return filesAsync.when(
        data: (allFiles) {
          final albumFiles = allFiles.where((f) => f.folderId == _selectedAlbum!.id).toList();
          if (albumFiles.isEmpty) {
            return const Center(child: Text('No media in this album.', style: TextStyle(color: Colors.white54)));
          }

          final cols = ref.watch(mediaColumnCountProvider);
          return GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: albumFiles.length,
            itemBuilder: (context, index) => _GalleryItem(file: albumFiles[index], siblings: albumFiles),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.white))),
      );
    }

    final mediaFilesAsync = ref.watch(allMediaFilesProvider);
    final foldersAsync = ref.watch(allMediaFoldersProvider);

    return mediaFilesAsync.when(
      data: (allFiles) => foldersAsync.when(
          data: (folders) {
            final images = allFiles.where((f) => f.mimeType?.startsWith('image/') == true).toList();
            final videos = allFiles.where((f) => f.mimeType?.startsWith('video/') == true).toList();
            
            final primaryAlbums = <_AlbumItemData>[
              if (images.isNotEmpty) _AlbumItemData(name: 'All Images', files: images),
              if (videos.isNotEmpty) _AlbumItemData(name: 'All Videos', files: videos, isVideosCategory: true),
            ];

            final otherFolders = folders.where((f) => f.name.toLowerCase() != 'camera' && f.name.toLowerCase() != 'screenshots').toList();

            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final album = primaryAlbums[index];
                        return _buildAlbumCard(album.name, album.files, isVideosCategory: album.isVideosCategory);
                      },
                      childCount: primaryAlbums.length,
                    ),
                  ),
                ),
                if (otherFolders.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(
                        'More albums',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 0.75, // Adjust aspect ratio to fit subtitles safely
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final folder = otherFolders[index];
                          final folderFiles = allFiles.where((f) => f.folderId == folder.id).toList();
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedAlbum = folder;
                              });
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AspectRatio(
                                  aspectRatio: 1, // Fixed square aspect ratio prevents covers from shrinking
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: _ThumbnailOrCover(file: folderFiles.isNotEmpty ? folderFiles.first : null),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  folder.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  '${folderFiles.length}',
                                  style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 10),
                                ),
                              ],
                            ),
                          );
                        },
                        childCount: otherFolders.length,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.white))),
        ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.white))),
    );
  }

  Widget _buildAlbumCard(String name, List<FileData> albumFiles, {bool isVideosCategory = false}) {
    final latestFile = albumFiles.isNotEmpty ? albumFiles.first : null;
    return GestureDetector(
      onTap: () {
        if (name == 'All Images') {
          setState(() {
            _currentTab = MediaTab.photos;
            _timelineView = PhotosTimelineView.all;
            _mediaTypeFilter = 'image/';
          });
        } else if (name == 'All Videos' || isVideosCategory) {
          setState(() {
            _currentTab = MediaTab.photos;
            _timelineView = PhotosTimelineView.all;
            _mediaTypeFilter = 'video/';
          });
        }
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _ThumbnailOrCover(file: latestFile),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
              ),
            ),
            Positioned(
              bottom: 12,
              left: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${albumFiles.length}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- EXPLORE VIEW ---
  Widget _buildExploreTab() {
    final mediaAsync = ref.watch(allMediaFilesProvider);
    final exploreAsync = ref.watch(exploreDataProvider);

    return mediaAsync.when(
      data: (allFiles) {
        var files = allFiles;
        if (_exploreSearchQuery.isNotEmpty) {
          files = files.where((f) => f.name.toLowerCase().contains(_exploreSearchQuery.toLowerCase())).toList();
        }

        if (_exploreSearchQuery.isNotEmpty) {
          if (files.isEmpty) {
            return const Center(child: Text('No results matched your search.', style: TextStyle(color: Colors.white54)));
          }
          final cols = ref.watch(mediaColumnCountProvider);
          return GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: files.length,
            itemBuilder: (context, index) => _GalleryItem(file: files[index], siblings: files),
          );
        }

        return exploreAsync.when(
          data: (exploreData) {
            final peopleCount = exploreData['peopleCount'] as int;
            final placesCount = exploreData['placesCount'] as int;
            final peopleCropPaths = exploreData['peopleCropPaths'] as List<String>;
            final placeCoverFiles = exploreData['placeCoverFiles'] as List<FileData>;
            final smartTags = exploreData['smartTags'] as List<Map<String, dynamic>>;
            final memoryFile = exploreData['memoryFile'] as FileData?;

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                // 1. People & Places (Renders grid with overlay texts)
                const Text(
                  'People & places',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => context.push('/media/people'),
                        child: _buildPeoplePlacesCard(
                          title: 'People',
                          count: peopleCount,
                          isPeople: true,
                          peopleCropPaths: peopleCropPaths,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => context.push('/media/places'),
                        child: _buildPeoplePlacesCard(
                          title: 'Places',
                          count: placesCount,
                          isPeople: false,
                          placeCoverFiles: placeCoverFiles,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // 2. Smart Tags
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Smart tags',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    GestureDetector(
                      onTap: () {
                        context.push('/media/smart-tags');
                      },
                      child: const Row(
                        children: [
                          Text('View All', style: TextStyle(color: AppColors.primary, fontSize: 13)),
                          SizedBox(width: 4),
                          Icon(Icons.chevron_right, color: AppColors.primary, size: 16),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 140,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: smartTags.length,
                    itemBuilder: (context, index) {
                      final tag = smartTags[index];
                      final coverFile = tag['cover'] as FileData?;
                      return Container(
                        width: 110,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (coverFile != null) _ThumbnailOrCover(file: coverFile) else _buildSmartTagFallback(tag['name'] as String),
                            
                            // Dark overlay
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                ),
                              ),
                            ),
                            
                            // Overlay Text
                            Positioned(
                              bottom: 8,
                              left: 10,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tag['name'] as String,
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    '${tag['count']}',
                                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 24),

                // 3. Memories
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Memories',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    GestureDetector(
                      onTap: () {
                        context.push('/media/memories');
                      },
                      child: const Row(
                        children: [
                          Text('View All', style: TextStyle(color: AppColors.primary, fontSize: 13)),
                          SizedBox(width: 4),
                          Icon(Icons.chevron_right, color: AppColors.primary, size: 16),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _ThumbnailOrCover(file: memoryFile),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                          ),
                        ),
                      ),
                      const Positioned(
                        bottom: 20,
                        left: 20,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Throwback',
                              style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Relive your special moments',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.flash_on, color: Colors.amber, size: 14),
                              SizedBox(width: 4),
                              Text('Best of 2026', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.white))),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.white))),
    );
  }

  Widget _buildPeoplePlacesCard({
    required String title,
    required int count,
    required bool isPeople,
    List<String>? peopleCropPaths,
    List<FileData>? placeCoverFiles,
  }) => Container(
      height: 150,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 2x2 grid of circles/rounded squares
          Padding(
            padding: const EdgeInsets.all(8),
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              physics: const NeverScrollableScrollPhysics(),
              children: List.generate(4, (index) {
                final shape = isPeople ? BoxShape.circle : BoxShape.rectangle;
                final borderRadius = isPeople ? null : BorderRadius.circular(6);

                Widget? coverWidget;
                if (isPeople) {
                  if (peopleCropPaths != null && index < peopleCropPaths.length) {
                    coverWidget = Image.file(
                      File(peopleCropPaths[index]),
                      fit: BoxFit.cover,
                    );
                  }
                } else {
                  if (placeCoverFiles != null && index < placeCoverFiles.length) {
                    coverWidget = _ThumbnailOrCover(file: placeCoverFiles[index]);
                  }
                }

                return Container(
                  decoration: BoxDecoration(
                    shape: shape,
                    borderRadius: borderRadius,
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: coverWidget ?? _buildMiniFallbackItem(isPeople, index),
                );
              }),
            ),
          ),
          
          // Dark linear gradient overlay for readability
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
            ),
          ),
          
          // Overlay Text & Count aligned at the bottom left
          Positioned(
            bottom: 12,
            left: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                Text(
                  '$count',
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );

  Widget _buildMiniFallbackItem(bool isPeople, int index) {
    final emojisPeople = ['👨‍💻', '👩‍🎨', '🧑‍🚀', '👨‍💼'];
    final emojisPlaces = ['🏖️', '🏔️', '🏙️', '🏛️'];
    return Center(
      child: Text(
        isPeople ? emojisPeople[index % 4] : emojisPlaces[index % 4],
        style: const TextStyle(fontSize: 16),
      ),
    );
  }

  Widget _buildSmartTagFallback(String tagName) {
    IconData icon;
    Color color;
    switch (tagName.toLowerCase()) {
      case 'food':
        icon = Icons.restaurant;
        color = Colors.orangeAccent;
      case 'buildings':
        icon = Icons.apartment;
        color = Colors.lightBlueAccent;
      case 'ocean':
        icon = Icons.waves;
        color = Colors.blue;
      default:
        icon = Icons.local_offer_outlined;
        color = AppColors.primary;
    }
    return ColoredBox(
      color: color.withValues(alpha: 0.1),
      child: Center(
        child: Icon(icon, color: color, size: 28),
      ),
    );
  }

  Widget _buildBottomSubNavBar() => DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.outlineVariant, width: 0.5)),
      ),
      child: BottomNavigationBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        currentIndex: _currentTab.index,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Colors.white60,
        onTap: (index) {
          setState(() {
            _currentTab = MediaTab.values[index];
            _filterYear = null;
            _filterMonth = null;
            _selectedAlbum = null;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.image_outlined),
            activeIcon: Icon(Icons.image, color: AppColors.primary),
            label: 'All media',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.photo_album_outlined),
            activeIcon: Icon(Icons.photo_album, color: AppColors.primary),
            label: 'Albums',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.explore_outlined),
            activeIcon: Icon(Icons.explore, color: AppColors.primary),
            label: 'Explore',
          ),
        ],
      ),
    );

  Widget _buildEmptyState(IconData icon, String message) => Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: AppColors.outline),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
}

class _AlbumItemData {
  _AlbumItemData({required this.name, required this.files, this.isVideosCategory = false});
  final String name;
  final List<FileData> files;
  final bool isVideosCategory;
}

class _ThumbnailOrCover extends ConsumerStatefulWidget {
  const _ThumbnailOrCover({required this.file});
  final FileData? file;

  @override
  ConsumerState<_ThumbnailOrCover> createState() => _ThumbnailOrCoverState();
}

class _ThumbnailOrCoverState extends ConsumerState<_ThumbnailOrCover> {
  File? _thumbnail;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant _ThumbnailOrCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file?.id != widget.file?.id) {
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    if (widget.file == null) {
      setState(() {
        _isLoading = false;
        _thumbnail = null;
      });
      return;
    }
    final thumb = await ref.read(thumbnailServiceProvider).getThumbnail(widget.file!);
    if (mounted) {
      setState(() {
        _thumbnail = thumb;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.file == null) {
      return ColoredBox(
        color: Colors.white.withValues(alpha: 0.05),
        child: const Icon(Icons.image_outlined, color: Colors.white24, size: 28),
      );
    }
    if (_thumbnail != null) {
      return Image.file(_thumbnail!, fit: BoxFit.cover);
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return ColoredBox(
      color: Colors.white.withValues(alpha: 0.05),
      child: const Icon(Icons.image_outlined, color: Colors.white24, size: 28),
    );
  }
}

class _GalleryItem extends ConsumerStatefulWidget {

  const _GalleryItem({required this.file, this.siblings});
  final FileData file;
  final List<FileData>? siblings;

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
      onTap: () => PreviewRouter.openPreview(context, widget.file, siblings: widget.siblings),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(4),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_thumbnail != null)
              Image.file(_thumbnail!, fit: BoxFit.cover)
            else if (widget.file.mimeType?.startsWith('video/') == true)
              const Icon(Icons.videocam, color: Colors.white, size: 28)
            else if (_isLoading)
              const Center(child: CircularProgressIndicator(strokeWidth: 1.5))
            else
              const Icon(Icons.image_not_supported, color: Colors.grey, size: 20),
            if (widget.file.mimeType?.startsWith('video/') == true)
              const Positioned(
                bottom: 4,
                left: 4,
                child: Icon(Icons.play_circle_outline, color: Colors.white, size: 16),
              ),
          ],
        ),
      ),
    );
}
