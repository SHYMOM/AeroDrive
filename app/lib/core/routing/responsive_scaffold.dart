import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/drive/providers/drive_providers.dart';
import '../../features/sharing/import_link_dialog.dart';
import '../../features/transfers/widgets/global_progress_bar.dart';
import '../constants.dart';
import '../theme/app_colors.dart';
import 'app_router.dart';

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
              .fadeIn(duration: 300.ms)
              .slideX(begin: 0.05, end: 0, duration: 300.ms, curve: Curves.easeOut);

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

final class _DesktopLayout extends StatelessWidget {
  _DesktopLayout({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.child,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          SidebarContent(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
          ),
          Expanded(
            child: Column(
              children: [
                Expanded(child: child),
                GlobalProgressBar(),
              ],
            ),
          ),
        ],
      ),
    );
}

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
  Widget build(BuildContext context) => _DesktopLayout(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      child: child,
    );
}

final class _MobileLayout extends StatelessWidget {
  _MobileLayout({
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
    
    // Hide bottom navigation bar when inside settings screens
    final location = GoRouterState.of(context).uri.path;
    final isSettings = location.startsWith('/settings');
    final hideNavBar = isKeyboardVisible || isSettings;

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: Drawer(
        backgroundColor: AppColors.surface,
        child: SidebarContent(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
        ),
      ),
      body: child,
      extendBody: true, // Required for floating glassmorphic nav bar
      bottomNavigationBar: hideNavBar
          ? GlobalProgressBar() // still show progress bar even if nav is hidden
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GlobalProgressBar(),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    border: Border(top: BorderSide(color: AppColors.outlineVariant)),
                  ),
                  child: NavigationBar(
                backgroundColor: AppColors.background,
                elevation: 0,
                selectedIndex: () {
                  final mobileItems = AppDestination.values.where((d) => d != AppDestination.settings).toList();
                  final idx = mobileItems.indexWhere((d) => selectedIndex == AppDestination.values.indexOf(d));
                  return idx < 0 ? 0 : idx;
                }(),
                onDestinationSelected: (i) {
                  final items = AppDestination.values.where((d) => d != AppDestination.settings).toList();
                  final dest = items[i];
                  onDestinationSelected(AppDestination.values.indexOf(dest));
                },
                indicatorColor: Colors.transparent, // Disable default pill indicator
                animationDuration: Duration(milliseconds: 400),
                destinations: AppDestination.values.where((d) => d != AppDestination.settings).map((d) {
                  final isSelected = selectedIndex == AppDestination.values.indexOf(d);
                  return NavigationDestination(
                    icon: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelected)
                          Container(
                            width: 32,
                            height: 2,
                            margin: EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              boxShadow: [BoxShadow(color: AppColors.glowCyan, blurRadius: 4)],
                              borderRadius: BorderRadius.circular(2),
                            ),
                          )
                        else
                          SizedBox(height: 8),
                        Icon(d.icon, color: isSelected ? AppColors.primary : AppColors.onSurfaceVariant),
                      ],
                    ),
                    selectedIcon: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 32,
                          height: 2,
                          margin: EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            boxShadow: [BoxShadow(color: AppColors.glowCyan, blurRadius: 4)],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Icon(d.selectedIcon, color: AppColors.primary),
                      ],
                    ),
                    label: d.label,
                  );
                }).toList(),
              ),
            ),
          ],
        ),
    );
  }
}

class SidebarContent extends ConsumerWidget {
  SidebarContent({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
      width: 280,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          right: BorderSide(color: AppColors.outline.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 48),
          // User Profile
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppColors.primary, AppColors.secondary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 12)
                    ],
                  ),
                  child: Center(
                    child: Text('A', style: TextStyle(color: AppColors.onPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Aero User',
                        style: TextStyle(color: AppColors.onSurface, fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Zero-Knowledge',
                        style: TextStyle(color: AppColors.secondary, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          // Storage Widget moved to top!
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _buildStorageCard(context, ref),
          ),
          const SizedBox(height: 24),
          
          // Navigation Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                ...AppDestination.values.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final dest = entry.value;
                  final isSelected = selectedIndex == idx;
                  return Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          if (Scaffold.of(context).isDrawerOpen) {
                            Navigator.pop(context);
                          }
                          onDestinationSelected(idx);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
                            border: isSelected ? Border.all(color: AppColors.primary.withValues(alpha: 0.5)) : null,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? dest.selectedIcon : dest.icon,
                                color: isSelected ? AppColors.primary : AppColors.onSurfaceVariant,
                                size: 24,
                              ),
                              SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  dest.label,
                                  style: TextStyle(
                                    color: isSelected ? AppColors.primary : AppColors.onSurfaceVariant,
                                    fontSize: 15,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (dest == AppDestination.transfers)
                                _TransferBadge(),
                            ],
                          ),
                      ),
                    ),
                  ),
                );
                }),
                
                Divider(color: AppColors.outline, height: 24),
                
                // Import Shared Link Option
                Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        if (Scaffold.of(context).isDrawerOpen) {
                          Navigator.pop(context);
                        }
                        showDialog(context: context, builder: (context) => const ImportLinkDialog());
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Icon(Icons.link, color: AppColors.secondary, size: 24),
                            SizedBox(width: 16),
                            Text(
                              'Import Shared Link',
                              style: TextStyle(
                                color: AppColors.onSurfaceVariant,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // My Shared Links Option
                Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        if (Scaffold.of(context).isDrawerOpen) {
                          Navigator.pop(context);
                        }
                        context.push('/settings/shared_links');
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Icon(Icons.share_outlined, color: AppColors.primary, size: 24),
                            SizedBox(width: 16),
                            Text(
                              'My Shared Links',
                              style: TextStyle(
                                color: AppColors.onSurfaceVariant,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Trash Option
                Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        if (Scaffold.of(context).isDrawerOpen) {
                          Navigator.pop(context);
                        }
                        context.push('/trash');
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, color: AppColors.error, size: 24),
                            SizedBox(width: 16),
                            Text(
                              'Trash',
                              style: TextStyle(
                                color: AppColors.onSurfaceVariant,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // About Option
                Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        if (Scaffold.of(context).isDrawerOpen) {
                          Navigator.pop(context);
                        }
                        context.push('/settings/about');
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: AppColors.onSurfaceVariant, size: 24),
                            SizedBox(width: 16),
                            Text(
                              'About',
                              style: TextStyle(
                                color: AppColors.onSurfaceVariant,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // ── Bottom Credit Signature ───────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [Theme.of(context).colorScheme.surfaceContainerHighest, Theme.of(context).colorScheme.surface],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  Text(
                    'Made With ❤️ In 🇧🇩',
                    style: TextStyle(color: AppColors.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 9, letterSpacing: 1),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 3),
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.tertiary],
                    ).createShader(bounds),
                    child: Text(
                      'SHEIKH SHYMOM ISLAM',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Widget _buildStorageCard(BuildContext context, WidgetRef ref) {
    final storageUsedAsync = ref.watch(totalStorageProvider);
    
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3), Theme.of(context).colorScheme.surfaceContainerHighest],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.2), blurRadius: 16)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.2),
                ),
                child: Icon(Icons.all_inclusive, color: AppColors.primary, size: 16),
              ),
              SizedBox(width: 10),
              Text(
                'Storage',
                style: TextStyle(color: AppColors.onSurface, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SizedBox(height: 12),
          storageUsedAsync.when(
            data: (bytes) {
              // Just a visual representation since we have unlimited storage
              // Fills up relative to 10GB tiers
              final visualValue = bytes == 0 ? 0.0 : (bytes % (10 * 1024 * 1024 * 1024)) / (10 * 1024 * 1024 * 1024);
              final boundedValue = visualValue < 0.05 && bytes > 0 ? 0.05 : visualValue;
              
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${_formatBytes(bytes)} used', style: TextStyle(color: AppColors.onSurface, fontSize: 13)),
                      Text('∞', style: TextStyle(color: AppColors.secondary, fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: boundedValue,
                      minHeight: 4,
                      backgroundColor: AppColors.outline.withValues(alpha: 0.3),
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.secondary),
                    ),
                  ),
                ]
              );
            },
            loading: () => LinearProgressIndicator(minHeight: 4, color: AppColors.secondary),
            error: (_, _) => Text('Error loading storage', style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12)),
          ),
          SizedBox(height: 12),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: AppColors.secondary.withValues(alpha: 0.15),
              border: Border.all(color: AppColors.secondary.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_rounded, size: 12, color: AppColors.secondary),
                SizedBox(width: 4),
                Text(
                  'Zero-Knowledge',
                  style: TextStyle(color: AppColors.secondary, fontSize: 9, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A small badge in the sidebar that shows the number of active transfers.
class _TransferBadge extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressState = ref.watch(aggregateTransferProgressProvider);
    return progressState.when(
      data: (data) {
        final active = (data['uploads'] as int) + (data['downloads'] as int);
        if (active <= 0) return SizedBox.shrink();
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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

