import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/db/database.dart';
import '../drive/widgets/file_list_item.dart';
import '../drive/widgets/folder_grid_item.dart';

final searchQueryProvider = StateProvider<String>((ref) => '');

enum SearchSortBy { name, date, size, type }
enum SearchFilterType { all, files, folders, images, videos, documents, audio, archives }

final searchSortByProvider = StateProvider<SearchSortBy>((ref) => SearchSortBy.name);
final searchFilterTypeProvider = StateProvider<SearchFilterType>((ref) => SearchFilterType.all);

class _ParsedSearchQuery {

  const _ParsedSearchQuery({required this.textQuery, this.tagName});
  final String textQuery;
  final String? tagName;
}

_ParsedSearchQuery _parseSearchQuery(String rawQuery) {
  final regExp = RegExp(r'#([^\s#]+)');
  final matches = regExp.allMatches(rawQuery);
  if (matches.isEmpty) {
    return _ParsedSearchQuery(textQuery: rawQuery.trim());
  }

  final firstMatch = matches.first;
  final tagName = firstMatch.group(1);
  final textQuery = rawQuery.replaceFirst(firstMatch.group(0)!, '').replaceAll(RegExp(r'\s+'), ' ').trim();
  return _ParsedSearchQuery(textQuery: textQuery, tagName: tagName);
}

final searchResultsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) return {'folders': <FolderData>[], 'files': <FileData>[]};

  final db = ref.watch(databaseProvider);
  final sortBy = ref.watch(searchSortByProvider);
  final filterType = ref.watch(searchFilterTypeProvider);

  final parsed = _parseSearchQuery(query);
  final textQuery = parsed.textQuery;
  final tagName = parsed.tagName;

  Tag? targetTag;
  if (tagName != null) {
    final tags = await (db.select(db.tags)..where((t) => t.name.like(tagName))).get();
    if (tags.isNotEmpty) {
      targetTag = tags.first;
    }
  }

  List<FolderData> matchedFolders = [];

  // Search folders
  if (filterType == SearchFilterType.all || filterType == SearchFilterType.folders) {
    final folderQuery = db.select(db.folders)
      ..where((f) => f.name.like('%$textQuery%') & f.deletedAt.isNull());
    matchedFolders = await folderQuery.get();
    switch (sortBy) {
      case SearchSortBy.name:
        matchedFolders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case SearchSortBy.date:
        matchedFolders.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
      default:
        break;
    }
  }

  List<FileData> matchedFiles = [];

  // Search files
  if (filterType != SearchFilterType.folders) {
    if (tagName != null && targetTag != null) {
      final fileQuery = db.select(db.files).join([
        innerJoin(db.fileTags, db.fileTags.fileId.equalsExp(db.files.id)),
      ])..where(db.fileTags.tagId.equals(targetTag.id) & db.files.deletedAt.isNull());
      
      if (textQuery.isNotEmpty) {
        fileQuery.where(db.files.name.like('%$textQuery%'));
      }
      final results = await fileQuery.get();
      matchedFiles = results.map((row) => row.readTable(db.files)).toList();
    } else {
      final searchQueryText = (targetTag == null && tagName != null) ? query : textQuery;

      final fileQuery = db.select(db.files).join([
        leftOuterJoin(db.fileTags, db.fileTags.fileId.equalsExp(db.files.id)),
        leftOuterJoin(db.tags, db.tags.id.equalsExp(db.fileTags.tagId)),
      ])..where((db.files.name.like('%$searchQueryText%') | db.tags.name.like('%$searchQueryText%')) & db.files.deletedAt.isNull());

      final results = await fileQuery.get();
      final uniqueFiles = <String, FileData>{};
      for (final row in results) {
        final file = row.readTable(db.files);
        uniqueFiles[file.id] = file;
      }
      matchedFiles = uniqueFiles.values.toList();
    }

    if (filterType == SearchFilterType.images) {
      matchedFiles = matchedFiles.where((f) => f.mimeType?.startsWith('image/') == true).toList();
    } else if (filterType == SearchFilterType.videos) {
      matchedFiles = matchedFiles.where((f) => f.mimeType?.startsWith('video/') == true).toList();
    } else if (filterType == SearchFilterType.documents) {
      matchedFiles = matchedFiles.where((f) {
        final m = f.mimeType ?? '';
        return m.contains('pdf') || m.startsWith('text/') || m.contains('document') || m.contains('msword') || m.contains('spreadsheet') || m.contains('presentation');
      }).toList();
    } else if (filterType == SearchFilterType.audio) {
      matchedFiles = matchedFiles.where((f) => f.mimeType?.startsWith('audio/') == true).toList();
    } else if (filterType == SearchFilterType.archives) {
      matchedFiles = matchedFiles.where((f) {
        final m = f.mimeType ?? '';
        return m.contains('zip') || m.contains('rar') || m.contains('tar') || m.contains('7z') || m.contains('compress');
      }).toList();
    }

    switch (sortBy) {
      case SearchSortBy.name:
        matchedFiles.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case SearchSortBy.date:
        matchedFiles.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
      case SearchSortBy.size:
        matchedFiles.sort((a, b) => (b.size ?? 0).compareTo(a.size ?? 0));
      case SearchSortBy.type:
        matchedFiles.sort((a, b) => (a.mimeType ?? '').compareTo(b.mimeType ?? ''));
    }
  }

  return {'folders': matchedFolders, 'files': matchedFiles};
});

class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchResultsAsync = ref.watch(searchResultsProvider);
    final query = ref.watch(searchQueryProvider);
    final sortBy = ref.watch(searchSortByProvider);
    final filterType = ref.watch(searchFilterTypeProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: TextField(
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Search files, folders or #tags...',
            hintStyle: TextStyle(color: Colors.white38),
            border: InputBorder.none,
            icon: Icon(Icons.search, color: AppColors.primary),
          ),
          onChanged: (val) {
            ref.read(searchQueryProvider.notifier).state = val;
          },
        ),
        actions: [
          PopupMenuButton<SearchSortBy>(
            icon: Icon(Icons.sort, color: AppColors.onSurfaceVariant),
            tooltip: 'Sort',
            color: AppColors.surfaceElevated,
            onSelected: (value) {
              ref.read(searchSortByProvider.notifier).state = value;
            },
            itemBuilder: (context) => [
              CheckedPopupMenuItem<SearchSortBy>(
                value: SearchSortBy.name,
                checked: sortBy == SearchSortBy.name,
                child: const Text('Name', style: TextStyle(color: Colors.white)),
              ),
              CheckedPopupMenuItem<SearchSortBy>(
                value: SearchSortBy.date,
                checked: sortBy == SearchSortBy.date,
                child: const Text('Date', style: TextStyle(color: Colors.white)),
              ),
              CheckedPopupMenuItem<SearchSortBy>(
                value: SearchSortBy.size,
                checked: sortBy == SearchSortBy.size,
                child: const Text('Size', style: TextStyle(color: Colors.white)),
              ),
              CheckedPopupMenuItem<SearchSortBy>(
                value: SearchSortBy.type,
                checked: sortBy == SearchSortBy.type,
                child: const Text('Type', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
          PopupMenuButton<SearchFilterType>(
            icon: Icon(Icons.filter_list, color: AppColors.onSurfaceVariant),
            tooltip: 'Filter',
            color: AppColors.surfaceElevated,
            onSelected: (value) {
              ref.read(searchFilterTypeProvider.notifier).state = value;
            },
            itemBuilder: (context) => [
              CheckedPopupMenuItem<SearchFilterType>(
                value: SearchFilterType.all,
                checked: filterType == SearchFilterType.all,
                child: const Text('All', style: TextStyle(color: Colors.white)),
              ),
              CheckedPopupMenuItem<SearchFilterType>(
                value: SearchFilterType.files,
                checked: filterType == SearchFilterType.files,
                child: const Text('Files', style: TextStyle(color: Colors.white)),
              ),
              CheckedPopupMenuItem<SearchFilterType>(
                value: SearchFilterType.folders,
                checked: filterType == SearchFilterType.folders,
                child: const Text('Folders', style: TextStyle(color: Colors.white)),
              ),
              CheckedPopupMenuItem<SearchFilterType>(
                value: SearchFilterType.images,
                checked: filterType == SearchFilterType.images,
                child: const Text('Images', style: TextStyle(color: Colors.white)),
              ),
              CheckedPopupMenuItem<SearchFilterType>(
                value: SearchFilterType.videos,
                checked: filterType == SearchFilterType.videos,
                child: const Text('Videos', style: TextStyle(color: Colors.white)),
              ),
              CheckedPopupMenuItem<SearchFilterType>(
                value: SearchFilterType.documents,
                checked: filterType == SearchFilterType.documents,
                child: const Text('Documents', style: TextStyle(color: Colors.white)),
              ),
              CheckedPopupMenuItem<SearchFilterType>(
                value: SearchFilterType.audio,
                checked: filterType == SearchFilterType.audio,
                child: const Text('Audio', style: TextStyle(color: Colors.white)),
              ),
              CheckedPopupMenuItem<SearchFilterType>(
                value: SearchFilterType.archives,
                checked: filterType == SearchFilterType.archives,
                child: const Text('Archives', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.3),
            radius: 1.8,
            colors: [
              const Color(0xFF7C3AED).withValues(alpha: 0.15),
              const Color(0xFF00E5FF).withValues(alpha: 0.05),
              AppColors.background,
              AppColors.background,
            ],
          ),
        ),
        child: Column(
          children: [
            if (query.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'Sort: ${sortBy.name}',
                      style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 11),
                    ),
                    const SizedBox(width: 8),
                    if (filterType != SearchFilterType.all)
                      Chip(
                        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                        labelStyle: const TextStyle(color: AppColors.primary, fontSize: 11),
                        side: const BorderSide(color: AppColors.primary),
                        label: Text(filterType.name),
                        deleteIcon: const Icon(Icons.close, size: 14, color: AppColors.primary),
                        onDeleted: () => ref.read(searchFilterTypeProvider.notifier).state = SearchFilterType.all,
                      ),
                  ],
                ),
              ),
            Expanded(
              child: searchResultsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.white))),
                data: (results) {
                  final theme = Theme.of(context);
                  final folders = results['folders'] as List<FolderData>;
                  final files = results['files'] as List<FileData>;
                  if (query.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search, size: 48, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                          const SizedBox(height: 16),
                          Text(
                            'Search your Vault',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Type to search for files, folders, and tags',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  if (folders.isEmpty && files.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, size: 48, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                          const SizedBox(height: 16),
                          Text(
                            'No results found',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Try a different search term or filter',
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
                      ref.invalidate(searchResultsProvider);
                    },
                    child: CustomScrollView(
                      slivers: [
                        if (folders.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              child: Text(
                                'Folders',
                                style: TextStyle(color: AppColors.onSurface, fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            sliver: SliverGrid(
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 140,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 16,
                                childAspectRatio: 0.8,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final child = FolderGridItem(folder: folders[index]);
                                  return child.animate()
                                      .fadeIn(duration: 250.ms, delay: (index % 10 * 30).ms)
                                      .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1), duration: 250.ms);
                                },
                                childCount: folders.length,
                              ),
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 24)),
                        ],
                        if (files.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              child: Text(
                                'Files',
                                style: TextStyle(color: AppColors.onSurface, fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final child = FileListItem(file: files[index]);
                                  return child.animate()
                                      .fadeIn(duration: 250.ms, delay: (index % 10 * 30).ms)
                                      .slideY(begin: 0.05, end: 0, duration: 250.ms, curve: Curves.easeOutQuad);
                                },
                                childCount: files.length,
                              ),
                            ),
                          ),
                        ],
                        const SliverToBoxAdapter(child: SizedBox(height: 48)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
