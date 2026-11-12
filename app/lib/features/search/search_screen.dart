import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/db/database.dart';
import '../drive/widgets/file_list_item.dart';
import '../drive/widgets/folder_grid_item.dart';

final searchQueryProvider = StateProvider<String>((ref) => '');

enum SearchSortBy { name, date, size, type }
enum SearchFilterType { all, folders, images, videos, documents, audio, dateModified }

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
    if (filterType == SearchFilterType.dateModified || sortBy == SearchSortBy.date) {
      matchedFolders.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    } else {
      matchedFolders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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
    }

    if (filterType == SearchFilterType.dateModified || sortBy == SearchSortBy.date) {
      matchedFiles.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    } else {
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
  }

  return {'folders': matchedFolders, 'files': matchedFiles};
});

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(searchQueryProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchResultsAsync = ref.watch(searchResultsProvider);
    final query = ref.watch(searchQueryProvider);
    final filterType = ref.watch(searchFilterTypeProvider);
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.onSurface),
          tooltip: 'Back to Drive',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/drive');
            }
          },
        ),
        title: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.outline.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: AppColors.onSurfaceVariant, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  style: TextStyle(color: AppColors.onSurface, fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'Search files, folders, or types...',
                    hintStyle: TextStyle(color: AppColors.onSurfaceVariant.withValues(alpha: 0.7)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (val) {
                    ref.read(searchQueryProvider.notifier).state = val;
                  },
                ),
              ),
              if (query.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.close_rounded, size: 18, color: AppColors.onSurfaceVariant),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    _controller.clear();
                    ref.read(searchQueryProvider.notifier).state = '';
                  },
                ),
            ],
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Container(
            height: 52,
            color: AppColors.surface,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _buildFilterChip('All', SearchFilterType.all, filterType),
                const SizedBox(width: 8),
                _buildFilterChip('Folders', SearchFilterType.folders, filterType),
                const SizedBox(width: 8),
                _buildFilterChip('Images', SearchFilterType.images, filterType),
                const SizedBox(width: 8),
                _buildFilterChip('Videos', SearchFilterType.videos, filterType),
                const SizedBox(width: 8),
                _buildFilterChip('Documents', SearchFilterType.documents, filterType),
                const SizedBox(width: 8),
                _buildFilterChip('Audio', SearchFilterType.audio, filterType),
                const SizedBox(width: 8),
                _buildFilterChip('Date Modified', SearchFilterType.dateModified, filterType),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: searchResultsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(
            child: Text('Error: $err', style: TextStyle(color: AppColors.onSurface)),
          ),
          data: (results) {
            final folders = results['folders'] as List<FolderData>;
            final files = results['files'] as List<FileData>;

            if (query.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.search_rounded, size: 32, color: AppColors.secondary),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Search your Drive',
                      style: TextStyle(
                        color: AppColors.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Find files, encrypted folders, or #tags across Telegram storage',
                      style: TextStyle(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 12.5,
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
                    Icon(Icons.search_off_rounded, size: 48, color: AppColors.onSurfaceVariant.withValues(alpha: 0.4)),
                    const SizedBox(height: 14),
                    Text(
                      'No matching items found',
                      style: TextStyle(
                        color: AppColors.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Try different keywords or filters',
                      style: TextStyle(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(searchResultsProvider),
              child: CustomScrollView(
                slivers: [
                  if (folders.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                        child: Text(
                          'Folders (${folders.length})',
                          style: TextStyle(
                            color: AppColors.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverGrid(
                        gridDelegate: isMobile
                            ? SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: MediaQuery.of(context).size.width < 420 ? 1 : 2,
                                mainAxisExtent: 68,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 12,
                              )
                            : const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 260,
                                mainAxisExtent: 68,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                              ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => FolderGridItem(folder: folders[index]),
                          childCount: folders.length,
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  ],
                  if (files.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                        child: Text(
                          'Files (${files.length})',
                          style: TextStyle(
                            color: AppColors.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => FileListItem(file: files[index], siblings: files),
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
    );
  }

  Widget _buildFilterChip(String label, SearchFilterType type, SearchFilterType currentType) {
    final isSelected = type == currentType;
    return InkWell(
      onTap: () {
        ref.read(searchFilterTypeProvider.notifier).state = type;
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surfaceVariant.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.outline.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : AppColors.onSurfaceVariant,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
