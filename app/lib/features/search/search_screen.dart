import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/data/db/database.dart';

import 'package:aerodrive/features/tags/tag_service.dart';
import 'package:aerodrive/features/tags/tag_dialog.dart';

final searchQueryProvider = StateProvider<String>((ref) => '');
final selectedTagProvider = StateProvider<Tag?>((ref) => null);

final searchResultsProvider = FutureProvider<List<FileData>>((ref) async {
  final query = ref.watch(searchQueryProvider).trim();
  final selectedTag = ref.watch(selectedTagProvider);
  if (query.isEmpty && selectedTag == null) return [];

  final db = ref.watch(databaseProvider);
  
  if (selectedTag != null) {
    // Return files that have this tag AND match the query (if any)
    final fileQuery = db.select(db.files).join([
      innerJoin(db.fileTags, db.fileTags.fileId.equalsExp(db.files.id)),
    ])..where(db.fileTags.tagId.equals(selectedTag.id) & db.files.deletedAt.isNull());
    
    if (query.isNotEmpty) {
      fileQuery.where(db.files.name.like('%$query%'));
    }
    
    final results = await fileQuery.get();
    return results.map((row) => row.readTable(db.files)).toList();
  } else {
    // Search file names or tag names
    final fileQuery = db.select(db.files).join([
      leftOuterJoin(db.fileTags, db.fileTags.fileId.equalsExp(db.files.id)),
      leftOuterJoin(db.tags, db.tags.id.equalsExp(db.fileTags.tagId)),
    ])..where((db.files.name.like('%$query%') | db.tags.name.like('%$query%')) & db.files.deletedAt.isNull());

    final results = await fileQuery.get();
    // Use a Set to deduplicate since left join can return multiple rows for the same file
    final uniqueFiles = <String, FileData>{};
    for (final row in results) {
      final file = row.readTable(db.files);
      uniqueFiles[file.id] = file;
    }
    return uniqueFiles.values.toList();
  }
});

class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchResultsAsync = ref.watch(searchResultsProvider);
    final query = ref.watch(searchQueryProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search files or tags...',
            border: InputBorder.none,
            icon: Icon(Icons.search),
          ),
          onChanged: (val) {
            ref.read(searchQueryProvider.notifier).state = val;
          },
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(48),
          child: _TagFilterBar(),
        ),
      ),
      body: searchResultsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (files) {
          if (query.isEmpty) {
            return const Center(child: Text('Type to search for files in your Vault'));
          }
          if (files.isEmpty) {
            return const Center(child: Text('No files found matching your query'));
          }

          return ListView.builder(
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];
              return ListTile(
                leading: const Icon(Icons.insert_drive_file),
                title: Text(file.name),
                subtitle: Text('${(file.size ?? 0) ~/ 1024} KB'),
                onTap: () {
                  // Open file preview
                  // PreviewRouter.openPreview(context, file); // We don't have this import here, maybe skip for now
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _TagFilterBar extends ConsumerWidget {
  const _TagFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsStream = ref.watch(tagServiceProvider).watchAllTags();
    final selectedTag = ref.watch(selectedTagProvider);

    return StreamBuilder<List<Tag>>(
      stream: tagsStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final tags = snapshot.data!;
        return SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: tags.length,
            itemBuilder: (context, index) {
              final tag = tags[index];
              final isSelected = selectedTag?.id == tag.id;
              final color = tag.color != null ? HexColor.fromHex(tag.color!) : Colors.grey;

              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: FilterChip(
                  selected: isSelected,
                  label: Text(tag.name),
                  backgroundColor: color.withOpacity(0.2),
                  selectedColor: color,
                  labelStyle: TextStyle(
                    color: isSelected ? color.contrastColor : Colors.white,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      ref.read(selectedTagProvider.notifier).state = tag;
                    } else {
                      ref.read(selectedTagProvider.notifier).state = null;
                    }
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}
