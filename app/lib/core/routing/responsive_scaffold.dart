import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/drive/providers/drive_providers.dart';
import '../../features/drive/widgets/create_or_upload_sheet.dart';
import '../../features/drive/widgets/file_info_inspector.dart';
import '../../features/transfers/widgets/floating_transfer_card.dart';
import '../../features/transfers/widgets/global_progress_bar.dart';
import '../constants.dart';
import '../providers/security_providers.dart';
import '../theme/app_colors.dart';
import 'app_router.dart';

final isSidebarCollapsedProvider = StateProvider<bool>((ref) => false);

class ResponsiveScaffold extends ConsumerStatefulWidget {
  const ResponsiveScaffold({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ResponsiveScaffold> createState() => _ResponsiveScaffoldState();
}

class _ResponsiveScaffoldState extends ConsumerState<ResponsiveScaffold> {
  final _rootPaths = AppDestination.values.map((d) => d.path).toSet();

  bool _isRootRoute(String path) => _rootPaths.any((root) => path == root || path == '$root/');

  Future<bool> _onPopInvoked() async {
    if (!mounted) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exit AeroDrive?'),
        content: const Text('Are you sure you want to exit the application?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final index = AppDestination.values.indexWhere(
      (d) => location.startsWith(d.path),
    );
    return index < 0 ? 0 : index;
  }

  void _onDestinationSelected(BuildContext context, int index) {
    context.go(AppDestination.values[index].path);
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final isRoot = _isRootRoute(location);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;

        if (location.startsWith(AppDestination.drive.path)) {
          final isFavOnly = ref.read(isFavoriteOnlyProvider);
          if (isFavOnly) {
            ref.read(isFavoriteOnlyProvider.notifier).state = false;
            return;
          }

          final isOfflineOnly = ref.read(isOfflineOnlyProvider);
          if (isOfflineOnly) {
            ref.read(isOfflineOnlyProvider.notifier).state = false;
            return;
          }

          final navStack = ref.read(navigationStackProvider);
          if (navStack.isNotEmpty) {
            final parentId = navStack.last;
            ref.read(navigationStackProvider.notifier).update(
              (state) => [...state]..removeLast(),
            );
            ref.read(currentFolderIdProvider.notifier).state = parentId;
            return;
          }
          final currentFolder = ref.read(currentFolderIdProvider);
          if (currentFolder != null) {
            ref.read(currentFolderIdProvider.notifier).state = null;
            return;
          }
        } else {
          // If we are on another root tab (media, transfers, settings), navigate back to drive tab!
          if (isRoot) {
            context.go(AppDestination.drive.path);
            return;
          }
        }

        if (!isRoot) {
          if (context.mounted) GoRouter.of(context).pop();
          return;
        }

        final shouldExit = await _onPopInvoked();
        if (shouldExit && context.mounted) {
          if (Platform.isAndroid || Platform.isIOS) {
            SystemNavigator.pop();
          } else {
            SystemChannels.platform.invokeMethod('SystemNavigator.pop');
          }
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          final animatedChild = widget.child.animate(key: ValueKey(location))
              .fadeIn(duration: 250.ms)
              .slideX(begin: 0.03, end: 0, duration: 250.ms, curve: Curves.easeOut);

          if (width >= AppConstants.desktopBreakpoint) {
            return _DesktopLayout(
              selectedIndex: _currentIndex(context),
              onDestinationSelected: (i) => _onDestinationSelected(context, i),
              child: animatedChild,
            );
          } else if (width >= AppConstants.mobileBreakpoint) {
            return _TabletLayout(
              selectedIndex: _currentIndex(context),
              onDestinationSelected: (i) => _onDestinationSelected(context, i),
              child: animatedChild,
            );
          }
          return _MobileLayout(
            selectedIndex: _currentIndex(context),
            onDestinationSelected: (i) => _onDestinationSelected(context, i),
            child: animatedChild,
          );
        },
      ),
    );
  }
}

/// ── Desktop 3-Pane Layout ───────────────────────────────────────────
/// Left Pane: 250px pure white surface with logo, nav items & storage card
/// Center Pane: Recessed cool alabaster (#F4F7FE) workspace + floating transfer popover
/// Right Pane: 300px contextual File Info Inspector
final class _DesktopLayout extends ConsumerWidget {
  const _DesktopLayout({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.child,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isInspectorOpen = ref.watch(isInspectorOpenProvider);
    final isSidebarCollapsed = ref.watch(isSidebarCollapsedProvider);
    final isConfigChecked = ref.watch(configCheckedProvider);
    final isAppUnlocked = ref.watch(isAppUnlockedProvider);
    final width = MediaQuery.of(context).size.width;
    final showInspector = isInspectorOpen && width >= 1080 && isConfigChecked && isAppUnlocked;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Row(
        children: [
          ClipRect(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: isSidebarCollapsed ? 0 : 250,
              child: OverflowBox(
                minWidth: 250,
                maxWidth: 250,
                alignment: Alignment.topLeft,
                child: SidebarContent(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onDestinationSelected,
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              color: AppColors.background,
              child: Stack(
                children: [
                  Positioned.fill(child: child),
                  const Positioned(
                    bottom: 24,
                    right: 24,
                    child: FloatingTransferCard(),
                  ),
                ],
              ),
            ),
          ),
          if (showInspector)
            const FileInfoInspector(),
        ],
      ),
    );
  }
}

/// ── Tablet Layout ───────────────────────────────────────────────────
final class _TabletLayout extends StatelessWidget {
  const _TabletLayout({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.child,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.surface,
    body: Row(
      children: [
        SidebarContent(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
        ),
        Expanded(
          child: Container(
            color: AppColors.background,
            child: Stack(
              children: [
                Positioned.fill(child: child),
                const Positioned(
                  bottom: 24,
                  right: 24,
                  child: FloatingTransferCard(),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// ── Mobile Single-Sheet View ────────────────────────────────────────
/// No hamburger drawer. Single frosted-glass bottom bar with 4 destinations.
final class _MobileLayout extends StatelessWidget {
  const _MobileLayout({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.child,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    final location = GoRouterState.of(context).uri.path;
    final isSettingsSubpage = location.startsWith('/settings/') && location != '/settings';
    final hideNavBar = isKeyboardVisible || isSettingsSubpage;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: child,
      extendBody: true,
      bottomNavigationBar: hideNavBar
          ? null
          : Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.outline.withValues(alpha: 0.6),
                  width: 1,
                ),
                boxShadow: AppColors.floatingShadow,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: AppDestination.values.map((d) {
                    final idx = AppDestination.values.indexOf(d);
                    final isSelected = selectedIndex == idx;
                    return InkWell(
                      onTap: () => onDestinationSelected(idx),
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.surfaceVariant : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isSelected ? d.selectedIcon : d.icon,
                              color: isSelected ? AppColors.primary : AppColors.onSurfaceVariant,
                              size: 20,
                            ),
                            if (isSelected) ...[
                              const SizedBox(width: 8),
                              Text(
                                d.label,
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
    );
  }
}

/// ── Desktop & Tablet Sidebar ────────────────────────────────────────
class SidebarContent extends ConsumerWidget {
  const SidebarContent({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          right: BorderSide(
            color: AppColors.outline.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),
          // ── App Brand Header (Cloud Mark + Bold Title) ──────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.cloud_rounded,
                      color: AppColors.secondary,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'AeroDrive',
                  style: TextStyle(
                    color: AppColors.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Prominent Full-Width Primary + New / Upload Button ─
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => showCreateOrUploadOptions(context, ref),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.add_rounded, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'New / Upload',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // ── Navigation Items List ────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                // 1. My Drive
                _buildNavItem(
                  context: context,
                  icon: Icons.home_rounded,
                  label: 'My Drive',
                  isSelected: selectedIndex == 0,
                  onTap: () => onDestinationSelected(0),
                ),
                // 2. Media
                _buildNavItem(
                  context: context,
                  icon: Icons.photo_library_rounded,
                  label: 'Media',
                  isSelected: selectedIndex == 1,
                  onTap: () => onDestinationSelected(1),
                ),
                // 3. Transfers
                _buildNavItem(
                  context: context,
                  icon: Icons.swap_vert_rounded,
                  label: 'Transfers',
                  isSelected: selectedIndex == 2,
                  badge: _TransferBadge(),
                  onTap: () => onDestinationSelected(2),
                ),
                // 4. Shared Links
                _buildNavItem(
                  context: context,
                  icon: Icons.link_rounded,
                  label: 'Shared Links',
                  isSelected: false,
                  onTap: () => context.push('/settings/shared_links'),
                ),
                // 5. Settings
                _buildNavItem(
                  context: context,
                  icon: Icons.settings_rounded,
                  label: 'Settings',
                  isSelected: selectedIndex == 3,
                  onTap: () => onDestinationSelected(3),
                ),
                // 6. Trash
                _buildNavItem(
                  context: context,
                  icon: Icons.delete_outline_rounded,
                  label: 'Trash',
                  isSelected: false,
                  onTap: () => context.push('/trash'),
                ),
              ],
            ),
          ),

          // ── Bottom Zero-Knowledge Storage Card ───────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildStorageCard(context, ref),
          ),
          const SizedBox(height: 12),

          // ── Bottom Author Attribution Signature ─────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                Text(
                  'Made With ❤️ In 🇧🇩',
                  style: TextStyle(
                    color: AppColors.onSurfaceVariant.withValues(alpha: 0.6),
                    fontSize: 8.5,
                    letterSpacing: 0.8,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 3),
                Text(
                  'SHEIKH SHYMOM ISLAM',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    Widget? badge,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isSelected ? AppColors.surfaceVariant : Colors.transparent,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isSelected ? AppColors.primary : AppColors.onSurfaceVariant,
                  size: 20,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? AppColors.onSurface : AppColors.onSurfaceVariant,
                      fontSize: 13.5,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (badge != null) badge,
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Widget _buildStorageCard(BuildContext context, WidgetRef ref) {
    final storageUsedAsync = ref.watch(totalStorageProvider);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.background,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Zero-Knowledge Storage',
            style: TextStyle(
              color: AppColors.onSurface,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          storageUsedAsync.when(
            data: (bytes) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Aero User',
                          style: TextStyle(
                            color: AppColors.onSurfaceVariant,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '${_formatBytes(bytes)} used',
                          style: TextStyle(
                            color: AppColors.onSurface,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      width: 32,
                      height: 32,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.secondary.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.all_inclusive_rounded,
                          size: 16,
                          color: AppColors.secondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: bytes > 0 ? ((bytes / (1024 * 1024 * 1024 * 10)).clamp(0.02, 1.0)) : 0.05,
                    minHeight: 4,
                    backgroundColor: AppColors.outline.withValues(alpha: 0.3),
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.secondary),
                  ),
                ),
              ],
            ),
            loading: () => const LinearProgressIndicator(minHeight: 3),
            error: (_, _) => Text(
              'Aero User • Unlimited',
              style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

/// Active transfers badge
class _TransferBadge extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressState = ref.watch(aggregateTransferProgressProvider);
    return progressState.when(
      data: (data) {
        final active = (data['uploads'] as int) + (data['downloads'] as int);
        if (active <= 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$active',
            style: TextStyle(
              color: AppColors.onPrimary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
