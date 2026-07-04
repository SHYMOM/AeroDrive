import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/db/database.dart';

class FolderPickerDialog extends ConsumerStatefulWidget { // Don't allow picking a folder or its nested subfolders

  const FolderPickerDialog({
    super.key,
    required this.title,
    this.initialFolderId,
    this.excludeFolderId,
  });
  final String title;
  final String? initialFolderId;
  final String? excludeFolderId;

  @override
  ConsumerState<FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends ConsumerState<FolderPickerDialog> {
  String? _currentFolderId;
  List<FolderData> _breadcrumbs = [];
  List<FolderData> _subfolders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _currentFolderId = widget.initialFolderId;
    _loadCurrentFolderContents();
  }

  Future<void> _loadCurrentFolderContents() async {
    setState(() => _isLoading = true);
    final db = ref.read(databaseProvider);
    
    // 1. Build breadcrumbs
    final List<FolderData> crumbs = [];
    String? iterId = _currentFolderId;
    while (iterId != null) {
      final folder = await (db.select(db.folders)..where((f) => f.id.equals(iterId!))).getSingleOrNull();
      if (folder == null) break;
      crumbs.insert(0, folder);
      iterId = folder.parentId;
    }
    
    // 2. Fetch subfolders
    final subQuery = db.select(db.folders)..where((f) => f.deletedAt.isNull());
    if (_currentFolderId == null) {
      subQuery.where((f) => f.parentId.isNull());
    } else {
      subQuery.where((f) => f.parentId.equals(_currentFolderId!));
    }
    
    var subs = await subQuery.get();
    
    // Exclude folder if defined
    if (widget.excludeFolderId != null) {
      // Find all recursively nested subfolders of excludeFolderId
      final Set<String> excludedIds = {widget.excludeFolderId!};
      await _findNestedFolderIds(widget.excludeFolderId!, excludedIds, db);
      subs = subs.where((f) => !excludedIds.contains(f.id)).toList();
    }
    
    subs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (mounted) {
      setState(() {
        _breadcrumbs = crumbs;
        _subfolders = subs;
        _isLoading = false;
      });
    }
  }

  Future<void> _findNestedFolderIds(String parentId, Set<String> excludedIds, AeroDriveDatabase db) async {
    final subfolders = await (db.select(db.folders)..where((f) => f.parentId.equals(parentId) & f.deletedAt.isNull())).get();
    for (final folder in subfolders) {
      excludedIds.add(folder.id);
      await _findNestedFolderIds(folder.id, excludedIds, db);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(16),
        height: 450,
        child: Column(
          children: [
            // Title
            Text(
              widget.title,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            
            // Breadcrumbs path
            _buildBreadcrumbs(),
            const Divider(color: Colors.white10),
            
            // Folder List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _subfolders.isEmpty
                      ? const Center(
                          child: Text('No subfolders found.', style: TextStyle(color: Colors.white38, fontSize: 13)),
                        )
                      : ListView.builder(
                          itemCount: _subfolders.length,
                          itemBuilder: (context, index) {
                            final folder = _subfolders[index];
                            final color = folder.color != null ? Color(int.parse(folder.color!)) : Colors.blueAccent;
                            
                            return ListTile(
                              leading: Icon(Icons.folder, color: color),
                              title: Text(folder.name, style: const TextStyle(color: Colors.white, fontSize: 14)),
                              trailing: const Icon(Icons.chevron_right, color: Colors.white24),
                              onTap: () {
                                setState(() {
                                  _currentFolderId = folder.id;
                                });
                                _loadCurrentFolderContents();
                              },
                            );
                          },
                        ),
            ),
            
            const Divider(color: Colors.white10),
            
            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    // Return the picked directory ID. We use '__root__' if root is picked.
                    Navigator.pop(context, _currentFolderId ?? '__root__');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Select folder', style: TextStyle(color: Colors.black)),
                ),
              ],
            ),
          ],
        ),
      ),
    );

  Widget _buildBreadcrumbs() => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Root Button
          InkWell(
            onTap: () {
              setState(() {
                _currentFolderId = null;
              });
              _loadCurrentFolderContents();
            },
            child: const Text('My Drive', style: TextStyle(color: AppColors.primary, fontSize: 13)),
          ),
          for (final crumb in _breadcrumbs) ...[
            const Icon(Icons.chevron_right, color: Colors.white38, size: 16),
            InkWell(
              onTap: () {
                setState(() {
                  _currentFolderId = crumb.id;
                });
                _loadCurrentFolderContents();
              },
              child: Text(crumb.name, style: const TextStyle(color: AppColors.primary, fontSize: 13)),
            ),
          ]
        ],
      ),
    );
}
