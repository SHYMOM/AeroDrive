import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../data/db/database.dart';
import '../../domain/cleaner/duplicate_cleaner_service.dart';
import '../gallery/thumbnail_service.dart';
import '../preview/preview_router.dart';

final cleanerDuplicatesProvider = FutureProvider<List<DuplicateGroup>>((ref) async {
  return ref.watch(duplicateCleanerServiceProvider).getDuplicateGroups();
});

final cleanerLargeFilesProvider = FutureProvider<List<FileData>>((ref) async {
  return ref.watch(duplicateCleanerServiceProvider).getLargeFiles();
});

final cleanerScreenshotsProvider = FutureProvider<List<FileData>>((ref) async {
  return ref.watch(duplicateCleanerServiceProvider).getScreenshots();
});

class CleanerScreen extends ConsumerStatefulWidget {
  const CleanerScreen({super.key});

  @override
  ConsumerState<CleanerScreen> createState() => _CleanerScreenState();
}

class _CleanerScreenState extends ConsumerState<CleanerScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Set<String> _selectedFilesToDelete = {};
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _deleteSelected() async {
    if (_selectedFilesToDelete.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move to Trash?'),
        content: Text('Move ${_selectedFilesToDelete.length} selected files to Trash? You can restore them anytime.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Move to Trash'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);
    final cleaner = ref.read(duplicateCleanerServiceProvider);
    await cleaner.moveToTrash(_selectedFilesToDelete.toList());

    ref.invalidate(cleanerDuplicatesProvider);
    ref.invalidate(cleanerLargeFilesProvider);
    ref.invalidate(cleanerScreenshotsProvider);

    if (mounted) {
      setState(() {
        _selectedFilesToDelete.clear();
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected files moved to Trash.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final duplicatesAsync = ref.watch(cleanerDuplicatesProvider);
    final largeFilesAsync = ref.watch(cleanerLargeFilesProvider);
    final screenshotsAsync = ref.watch(cleanerScreenshotsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Storage Cleaner', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'Duplicates'),
            Tab(text: 'Large Files'),
            Tab(text: 'Screenshots'),
          ],
        ),
      ),
      bottomNavigationBar: _selectedFilesToDelete.isNotEmpty
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: AppColors.surfaceElevated,
              child: SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_selectedFilesToDelete.length} files selected',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                      onPressed: _isProcessing ? null : _deleteSelected,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Clean Up'),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: [
          // 1. Duplicates Tab
          duplicatesAsync.when(
            data: (groups) {
              if (groups.isEmpty) {
                return _buildEmptyTab(Icons.check_circle_outline, 'No duplicate files found! Your drive is clean.');
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: groups.length,
                itemBuilder: (context, idx) {
                  final group = groups[idx];
                  return Card(
                    color: AppColors.surfaceElevated.withValues(alpha: 0.6),
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${group.files.length} Duplicates • Wasting ${_formatBytes(group.totalWastedBytes)}',
                                style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    // Keep first (newest), select the rest for deletion
                                    for (int i = 1; i < group.files.length; i++) {
                                      _selectedFilesToDelete.add(group.files[i].id);
                                    }
                                  });
                                },
                                child: const Text('Select Duplicates', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                          const Divider(height: 12, color: Colors.white10),
                          ...group.files.map((file) {
                            final isSelected = _selectedFilesToDelete.contains(file.id);
                            return CheckboxListTile(
                              value: isSelected,
                              contentPadding: EdgeInsets.zero,
                              activeColor: Colors.redAccent,
                              title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                              subtitle: Text(
                                '${_formatBytes(file.size ?? 0)} • ${file.createdAt != null ? DateFormat.yMMMd().format(file.createdAt!) : ""}',
                                style: const TextStyle(fontSize: 11, color: Colors.white54),
                              ),
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedFilesToDelete.add(file.id);
                                  } else {
                                    _selectedFilesToDelete.remove(file.id);
                                  }
                                });
                              },
                            );
                          }),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),

          // 2. Large Files Tab
          largeFilesAsync.when(
            data: (files) {
              if (files.isEmpty) {
                return _buildEmptyTab(Icons.video_library_outlined, 'No large files (>50MB) found.');
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: files.length,
                itemBuilder: (context, idx) {
                  final file = files[idx];
                  final isSelected = _selectedFilesToDelete.contains(file.id);
                  return Card(
                    color: AppColors.surfaceElevated.withValues(alpha: 0.6),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: CheckboxListTile(
                      value: isSelected,
                      activeColor: Colors.redAccent,
                      title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(_formatBytes(file.size ?? 0), style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                      secondary: IconButton(
                        icon: const Icon(Icons.remove_red_eye_outlined),
                        onPressed: () => PreviewRouter.openPreview(context, file),
                      ),
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedFilesToDelete.add(file.id);
                          } else {
                            _selectedFilesToDelete.remove(file.id);
                          }
                        });
                      },
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),

          // 3. Screenshots Tab
          screenshotsAsync.when(
            data: (files) {
              if (files.isEmpty) {
                return _buildEmptyTab(Icons.screenshot_outlined, 'No screenshot clutter detected.');
              }
              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: files.length,
                itemBuilder: (context, idx) {
                  final file = files[idx];
                  final isSelected = _selectedFilesToDelete.contains(file.id);
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedFilesToDelete.remove(file.id);
                        } else {
                          _selectedFilesToDelete.add(file.id);
                        }
                      });
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _CleanerThumbnail(file: file),
                        if (isSelected)
                          Container(
                            color: Colors.redAccent.withValues(alpha: 0.4),
                            child: const Center(child: Icon(Icons.check_circle, color: Colors.white, size: 28)),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTab(IconData icon, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _CleanerThumbnail extends ConsumerWidget {
  const _CleanerThumbnail({required this.file});
  final FileData file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref.read(thumbnailServiceProvider).getThumbnail(file),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(snapshot.data!, fit: BoxFit.cover),
          );
        }
        return Container(
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.image, color: Colors.white30),
        );
      },
    );
  }
}
