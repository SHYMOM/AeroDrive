import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/db/database.dart';
import '../providers/drive_providers.dart';

final pinnedQuickAccessFoldersProvider = FutureProvider<List<FolderData>>((ref) async {
  ref.watch(settingsUpdateProvider);
  final settings = ref.watch(settingsRepositoryProvider);
  final raw = await settings.getSetting('pinned_quick_access_folders');
  if (raw == null || raw.isEmpty) return [];

  try {
    final List<dynamic> ids = jsonDecode(raw) as List<dynamic>;
    if (ids.isEmpty) return [];

    final db = ref.watch(databaseProvider);
    final allFolders = await (db.select(db.folders)..where((f) => f.deletedAt.isNull())).get();
    final idSet = ids.map((e) => e.toString()).toSet();
    return allFolders.where((f) => idSet.contains(f.id)).toList();
  } catch (_) {
    return [];
  }
});

class QuickAccessItem {
  const QuickAccessItem({
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  final String title;
  final int count;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;
}

class QuickAccessRow extends ConsumerStatefulWidget {
  const QuickAccessRow({super.key});

  @override
  ConsumerState<QuickAccessRow> createState() => _QuickAccessRowState();
}

class _QuickAccessRowState extends ConsumerState<QuickAccessRow> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollLeft() {
    if (!_scrollController.hasClients) return;
    final target = (_scrollController.offset - 240).clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollRight() {
    if (!_scrollController.hasClients) return;
    final target = (_scrollController.offset + 240).clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildScrollButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        icon: Icon(icon, color: AppColors.onSurfaceVariant, size: 16),
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        splashRadius: 14,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pinnedFoldersAsync = ref.watch(pinnedQuickAccessFoldersProvider);
    final pinnedFolders = pinnedFoldersAsync.valueOrNull ?? [];
    final countsAsync = ref.watch(categoryCountsProvider);
    final counts = countsAsync.valueOrNull ?? {};

    final defaultCategories = [
      QuickAccessItem(
        title: 'Favorites',
        count: counts['Favorites'] ?? 0,
        icon: Icons.star_rounded,
        color: const Color(0xFFF59E0B),
        bgColor: const Color(0xFFF59E0B).withValues(alpha: 0.12),
        onTap: () {
          ref.read(isFavoriteOnlyProvider.notifier).state = true;
        },
      ),
      QuickAccessItem(
        title: 'Offline',
        count: counts['Offline'] ?? 0,
        icon: Icons.offline_pin_rounded,
        color: AppColors.categoryOffline,
        bgColor: AppColors.categoryOfflineBg,
        onTap: () {
          ref.read(isOfflineOnlyProvider.notifier).update((v) => !v);
        },
      ),
      QuickAccessItem(
        title: 'Images',
        count: counts['Images'] ?? 0,
        icon: Icons.image_rounded,
        color: AppColors.categoryImages,
        bgColor: AppColors.categoryImagesBg,
        onTap: () => context.push('/media/images'),
      ),
      QuickAccessItem(
        title: 'Videos',
        count: counts['Videos'] ?? 0,
        icon: Icons.play_arrow_rounded,
        color: AppColors.categoryVideos,
        bgColor: AppColors.categoryVideosBg,
        onTap: () => context.push('/media/videos'),
      ),
      QuickAccessItem(
        title: 'Documents',
        count: counts['Documents'] ?? 0,
        icon: Icons.description_rounded,
        color: AppColors.categoryDocuments,
        bgColor: AppColors.categoryDocumentsBg,
        onTap: () => context.push('/media/documents'),
      ),
      QuickAccessItem(
        title: 'Audio',
        count: counts['Audios'] ?? 0,
        icon: Icons.music_note_rounded,
        color: AppColors.categoryAudio,
        bgColor: AppColors.categoryAudioBg,
        onTap: () => context.push('/media/audios'),
      ),
    ];

    // Combine defaults + pinned folders + Add button
    final totalCount = defaultCategories.length + pinnedFolders.length + 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
            children: [
              Text(
                'Quick Access',
                style: TextStyle(
                  color: AppColors.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: 10),
              _buildScrollButton(
                icon: Icons.chevron_left_rounded,
                tooltip: 'Scroll left',
                onPressed: _scrollLeft,
              ),
              const SizedBox(width: 4),
              _buildScrollButton(
                icon: Icons.chevron_right_rounded,
                tooltip: 'Scroll right',
                onPressed: _scrollRight,
              ),
              const Spacer(),
              InkWell(
                onTap: () => _showPinFolderDialog(context, ref),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    'Customize',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 118,
          child: ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            scrollDirection: Axis.horizontal,
            itemCount: totalCount,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              // 1. Built-in Categories
              if (index < defaultCategories.length) {
                final item = defaultCategories[index];
                return _buildCard(
                  context: context,
                  title: item.title,
                  countText: '${item.count} items',
                  icon: item.icon,
                  color: item.color,
                  bgColor: item.bgColor,
                  onTap: item.onTap,
                );
              }

              // 2. User-Pinned Folders
              final pinnedIndex = index - defaultCategories.length;
              if (pinnedIndex < pinnedFolders.length) {
                final folder = pinnedFolders[pinnedIndex];
                final folderColor = AppColors.resolveFolderColor(folder.color);
                return Consumer(
                  builder: (context, innerRef, _) {
                    final countAsync = innerRef.watch(folderItemsCountProvider(folder.id));
                    final count = countAsync.valueOrNull ?? 0;
                    return _buildCard(
                      context: context,
                      title: folder.name,
                      countText: '$count items',
                      icon: Icons.folder_rounded,
                      color: folderColor,
                      bgColor: folderColor.withValues(alpha: 0.12),
                      onTap: () {
                        final current = innerRef.read(currentFolderIdProvider);
                        innerRef.read(navigationStackProvider.notifier).update((state) => [...state, current]);
                        innerRef.read(currentFolderIdProvider.notifier).state = folder.id;
                      },
                      onLongPress: () => _confirmUnpin(context, innerRef, folder),
                    );
                  },
                );
              }

              // 3. "+ Add / Pin" Tile at the end
              return _buildAddTile(context, ref);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCard({
    required BuildContext context,
    required String title,
    required String countText,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 115,
          height: 110,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF151D2A) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.06) : AppColors.outline.withValues(alpha: 0.5),
              width: 1.0,
            ),
            boxShadow: isDark ? null : AppColors.cardShadow,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Icon(
                    icon,
                    color: color,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  color: AppColors.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                countText,
                style: TextStyle(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddTile(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showPinFolderDialog(context, ref),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 115,
          height: 110,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF151D2A) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.08) : AppColors.outline.withValues(alpha: 0.7),
              style: BorderStyle.solid,
              width: 1.2,
            ),
            boxShadow: isDark ? null : AppColors.cardShadow,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Icon(
                    Icons.add_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pin Folder',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                'Shortcut',
                style: TextStyle(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPinFolderDialog(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final allFolders = await (db.select(db.folders)..where((f) => f.deletedAt.isNull())).get();
    final raw = await settingsRepo.getSetting('pinned_quick_access_folders');

    List<String> pinnedIds = [];
    if (raw != null && raw.isNotEmpty) {
      try {
        pinnedIds = (jsonDecode(raw) as List<dynamic>).map((e) => e.toString()).toList();
      } catch (_) {}
    }

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                'Customize Quick Access',
                style: TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.bold, fontSize: 17),
              ),
              content: SizedBox(
                width: 360,
                height: 320,
                child: allFolders.isEmpty
                    ? Center(
                        child: Text(
                          'No folders created yet.\nCreate folders to pin them here!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        itemCount: allFolders.length,
                        itemBuilder: (context, i) {
                          final f = allFolders[i];
                          final isPinned = pinnedIds.contains(f.id);
                          return CheckboxListTile(
                            secondary: Icon(Icons.folder_rounded, color: AppColors.secondary),
                            title: Text(
                              f.name,
                              style: TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.w500),
                            ),
                            value: isPinned,
                            activeColor: AppColors.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  if (!pinnedIds.contains(f.id)) pinnedIds.add(f.id);
                                } else {
                                  pinnedIds.remove(f.id);
                                }
                              });
                            },
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
                ),
                FilledButton(
                  onPressed: () async {
                    await settingsRepo.setSetting('pinned_quick_access_folders', jsonEncode(pinnedIds));
                    ref.read(settingsUpdateProvider.notifier).update((v) => v + 1);
                    ref.invalidate(pinnedQuickAccessFoldersProvider);
                    if (context.mounted) {
                      Navigator.pop(ctx);
                    }
                  },
                  child: const Text('Save Pins'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmUnpin(BuildContext context, WidgetRef ref, FolderData folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Unpin Folder?', style: TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.bold)),
        content: Text('Remove "${folder.name}" from Quick Access?', style: TextStyle(color: AppColors.onSurfaceVariant)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unpin'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final settingsRepo = ref.read(settingsRepositoryProvider);
      final raw = await settingsRepo.getSetting('pinned_quick_access_folders');
      if (raw != null) {
        try {
          final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
          list.remove(folder.id);
          await settingsRepo.setSetting('pinned_quick_access_folders', jsonEncode(list));
          ref.read(settingsUpdateProvider.notifier).update((v) => v + 1);
          ref.invalidate(pinnedQuickAccessFoldersProvider);
        } catch (_) {}
      }
    }
  }
}
