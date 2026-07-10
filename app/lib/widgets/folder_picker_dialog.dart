import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/theme/app_colors.dart';
import '../data/db/database.dart';

class FolderPickerResult {
  const FolderPickerResult({this.folderId, required this.folderName});
  final String? folderId;
  final String folderName;
}

class FolderPickerDialog extends ConsumerStatefulWidget {

  const FolderPickerDialog({
    super.key,
    this.excludeFolderId,
    this.currentFolderId,
  });
  final String? excludeFolderId;
  final String? currentFolderId;

  @override
  ConsumerState<FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends ConsumerState<FolderPickerDialog> {
  List<FolderData> _allFolders = [];
  Set<String> _excludedIds = {};
  bool _isLoading = true;
  final Set<String> _expandedIds = {};
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<Set<String>> _collectDescendantIds(String folderId) async {
    final db = ref.read(databaseProvider);
    final Set<String> descendants = {};
    final queue = <String>[folderId];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      descendants.add(current);
      final children = await (db.select(db.folders)
        ..where((f) => f.parentId.equals(current))
        ..where((f) => f.deletedAt.isNull())
      ).get();
      for (final child in children) {
        queue.add(child.id);
      }
    }
    return descendants;
  }

  Future<void> _loadFolders() async {
    try {
      final db = ref.read(databaseProvider);
      _allFolders = await (db.select(db.folders)
        ..where((f) => f.deletedAt.isNull())
        ..orderBy([(f) => drift.OrderingTerm.asc(f.name)])
      ).get();

      Set<String> excluded = {};
      if (widget.excludeFolderId != null) {
        excluded = await _collectDescendantIds(widget.excludeFolderId!);
      }
      if (widget.currentFolderId != null) {
        excluded.add(widget.currentFolderId!);
      }

      if (mounted) {
        setState(() {
          _excludedIds = excluded;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Map<String?, List<FolderData>> _buildTree() {
    final map = <String?, List<FolderData>>{};
    for (final f in _allFolders) {
      if (_excludedIds.contains(f.id)) continue;
      map.putIfAbsent(f.parentId, () => []).add(f);
    }
    return map;
  }

  List<_TreeEntry> _flattenTree(Map<String?, List<FolderData>> tree) {
    final result = <_TreeEntry>[];
    final stack = <_TreeEntry>[
      for (final root in tree[null] ?? [])
        _TreeEntry(root, 0),
    ];

    while (stack.isNotEmpty) {
      final entry = stack.removeAt(0);
      result.add(entry);

      if (_expandedIds.contains(entry.folder.id)) {
        final children = tree[entry.folder.id] ?? [];
        for (final child in children) {
          stack.insert(result.length - 1 - stack.length + 1, _TreeEntry(child, entry.depth + 1));
        }
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tree = _buildTree();
    final flat = _flattenTree(tree);

    final filtered = _filter.isEmpty
        ? flat
        : flat.where((e) =>
            e.folder.name.toLowerCase().contains(_filter.toLowerCase())).toList();

    return AlertDialog(
      title: const Text('Select Destination Folder'),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.55,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Filter folders...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onChanged: (v) => setState(() => _filter = v),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: 1 + filtered.length,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Column(
                            children: [
                              _buildRootTile(theme),
                              const Divider(height: 1),
                            ],
                          );
                        }
                        final entry = filtered[index - 1];
                        return _buildFolderTile(theme, entry, tree[entry.folder.id]?.isNotEmpty ?? false);
                      },
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildRootTile(ThemeData theme) {
    final isCurrent = widget.currentFolderId == null;
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.fileFolder.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.home_rounded, color: AppColors.fileFolder, size: 22),
      ),
      title: const Text('Root Directory', style: TextStyle(fontWeight: FontWeight.w500)),
      subtitle: const Text('Top level of your vault', style: TextStyle(fontSize: 12)),
      trailing: isCurrent ? Icon(Icons.check, color: theme.colorScheme.primary, size: 20) : null,
      onTap: () => Navigator.pop(context, const FolderPickerResult(folderName: 'Root Directory')),
    );
  }

  Widget _buildFolderTile(ThemeData theme, _TreeEntry entry, bool hasChildren) {
    final folder = entry.folder;
    final isCurrent = widget.currentFolderId == folder.id;
    final isExpanded = _expandedIds.contains(folder.id);

    return ListTile(
      contentPadding: EdgeInsets.only(left: 16.0 + entry.depth * 24.0, right: 16),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.fileFolder.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.folder_rounded, color: AppColors.fileFolder, size: 22),
      ),
      title: Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCurrent)
            Icon(Icons.check, color: theme.colorScheme.primary, size: 20),
          if (hasChildren)
            IconButton(
              icon: Icon(isExpanded ? Icons.expand_less : Icons.chevron_right, size: 20),
              onPressed: () {
                setState(() {
                  if (isExpanded) {
                    _expandedIds.remove(folder.id);
                  } else {
                    _expandedIds.add(folder.id);
                  }
                });
              },
            ),
        ],
      ),
      onTap: () => Navigator.pop(context, FolderPickerResult(folderId: folder.id, folderName: folder.name)),
    );
  }
}

class _TreeEntry {
  const _TreeEntry(this.folder, this.depth);
  final FolderData folder;
  final int depth;
}
