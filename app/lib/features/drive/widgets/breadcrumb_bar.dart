import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/database.dart';
import '../providers/drive_providers.dart';

class BreadcrumbBar extends ConsumerStatefulWidget {
  const BreadcrumbBar({super.key});

  @override
  ConsumerState<BreadcrumbBar> createState() => _BreadcrumbBarState();
}

class _BreadcrumbBarState extends ConsumerState<BreadcrumbBar> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _navigateToRoot() {
    ref.read(navigationStackProvider.notifier).state = [];
    ref.read(currentFolderIdProvider.notifier).state = null;
  }

  void _navigateToFolder(FolderData folder, List<FolderData> breadcrumbs) {
    final index = breadcrumbs.indexOf(folder);
    final newStack = ref.read(navigationStackProvider).take(index + 1).toList();
    ref.read(navigationStackProvider.notifier).state = newStack;
    ref.read(currentFolderIdProvider.notifier).state = folder.id;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentFolderId = ref.watch(currentFolderIdProvider);
    final breadcrumbsAsync = ref.watch(breadcrumbsProvider);
    final isRoot = currentFolderId == null;

    final breadcrumbs = breadcrumbsAsync.valueOrNull ?? [];

    // Trigger auto-scroll on path changes
    if (breadcrumbs.isNotEmpty) {
      _scrollToEnd();
    }

    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Root / My Drive Segment ──────────────────────────────
          _buildSegment(
            context: context,
            label: 'My Drive',
            icon: Icons.cloud_outlined,
            isActive: isRoot,
            onTap: isRoot ? null : _navigateToRoot,
          ),

          // ── Ancestor & Leaf Folder Segments ───────────────────────
          for (var i = 0; i < breadcrumbs.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: colorScheme.outlineVariant.withValues(alpha: 0.8),
              ),
            ),
            _buildSegment(
              context: context,
              label: breadcrumbs[i].name,
              icon: i == breadcrumbs.length - 1
                  ? Icons.folder_open_rounded
                  : Icons.folder_outlined,
              isActive: breadcrumbs[i].id == currentFolderId,
              onTap: breadcrumbs[i].id == currentFolderId
                  ? null
                  : () => _navigateToFolder(breadcrumbs[i], breadcrumbs),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSegment({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool isActive,
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    final textColor = isActive
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    final iconColor = isActive
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.8);
    final backgroundColor = isActive
        ? colorScheme.primary.withValues(alpha: 0.12)
        : Colors.transparent;

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        mouseCursor: isActive ? SystemMouseCursors.basic : SystemMouseCursors.click,
        hoverColor: colorScheme.primary.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
