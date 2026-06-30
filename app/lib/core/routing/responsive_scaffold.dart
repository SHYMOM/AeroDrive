import 'dart:io';
import 'dart:ui' as ui;
import 'package:aerodrive/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../constants.dart';
import 'app_router.dart';
import '../../widgets/aerodrive_logo.dart';
import '../../features/drive/providers/drive_providers.dart';
import '../../features/sharing/import_link_dialog.dart';

class ResponsiveScaffold extends ConsumerStatefulWidget {
  const ResponsiveScaffold({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ResponsiveScaffold> createState() => _ResponsiveScaffoldState();
}

class _ResponsiveScaffoldState extends ConsumerState<ResponsiveScaffold> {
  final _rootPaths = AppDestination.values.map((d) => d.path).toSet();

  bool _isRootRoute(String path) {
    return _rootPaths.any((root) => path == root || path == '$root/');
  }

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
  const _DesktopLayout({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.child,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          SidebarContent(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
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
  Widget build(BuildContext context) {
    return _DesktopLayout(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      child: child,
    );
  }
}

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
      bottomNavigationBar: isKeyboardVisible
          ? null
          : Container(
              decoration: const BoxDecoration(
                color: AppColors.background,
                border: Border(top: BorderSide(color: AppColors.outlineVariant, width: 1)),
              ),
              child: NavigationBar(
                backgroundColor: AppColors.background,
                elevation: 0,
                selectedIndex: selectedIndex,
                onDestinationSelected: onDestinationSelected,
                indicatorColor: Colors.transparent, // Disable default pill indicator
                animationDuration: const Duration(milliseconds: 400),
                destinations: AppDestination.values.map((d) {
                  final isSelected = selectedIndex == AppDestination.values.indexOf(d);
                  return NavigationDestination(
                    icon: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelected)
                          Container(
                            width: 32,
                            height: 2,
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              boxShadow: const [BoxShadow(color: AppColors.glowCyan, blurRadius: 4)],
                              borderRadius: BorderRadius.circular(2),
                            ),
                          )
                        else
                          const SizedBox(height: 8),
                        Icon(d.icon, color: isSelected ? AppColors.primary : AppColors.onSurfaceVariant),
                      ],
                    ),
                    selectedIcon: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 32,
                          height: 2,
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            boxShadow: const [BoxShadow(color: AppColors.glowCyan, blurRadius: 4)],
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
    );
  }
}

class SidebarContent extends StatelessWidget {
  const SidebarContent({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          right: BorderSide(color: AppColors.outline.withOpacity(0.5), width: 1),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 48),
          // User Profile
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.secondary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 12)
                    ],
                  ),
                  child: const Center(
                    child: Text('A', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Aero User',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
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
            child: _buildStorageCard(context),
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
                    padding: const EdgeInsets.only(bottom: 8),
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
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: isSelected ? AppColors.primary.withOpacity(0.15) : Colors.transparent,
                            border: isSelected ? Border.all(color: AppColors.primary.withOpacity(0.5)) : null,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? dest.selectedIcon : dest.icon,
                                color: isSelected ? AppColors.primary : Colors.white70,
                                size: 24,
                              ),
                              const SizedBox(width: 16),
                              Text(
                                dest.label,
                                style: TextStyle(
                                  color: isSelected ? AppColors.primary : Colors.white70,
                                  fontSize: 15,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                
                const Divider(color: Colors.white12, height: 24),
                
                // Import Shared Link Option
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
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
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: const Row(
                          children: [
                            Icon(Icons.link, color: AppColors.secondary, size: 24),
                            SizedBox(width: 16),
                            Text(
                              'Import Shared Link',
                              style: TextStyle(
                                color: Colors.white70,
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
                  padding: const EdgeInsets.only(bottom: 8),
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
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: const Row(
                          children: [
                            Icon(Icons.delete_outline, color: AppColors.error, size: 24),
                            SizedBox(width: 16),
                            Text(
                              'Trash',
                              style: TextStyle(
                                color: Colors.white70,
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
        ],
      ),
    );
  }

  Widget _buildStorageCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withOpacity(0.2), blurRadius: 16)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withOpacity(0.2),
                ),
                child: const Icon(Icons.all_inclusive, color: AppColors.primary, size: 16),
              ),
              const SizedBox(width: 10),
              const Text(
                'Storage',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Unlimited', style: TextStyle(color: Colors.white, fontSize: 13)),
              Text('∞', style: TextStyle(color: AppColors.secondary, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: const LinearProgressIndicator(
              value: 1.0,
              minHeight: 4,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.secondary),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: AppColors.secondary.withOpacity(0.15),
              border: Border.all(color: AppColors.secondary.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shield_rounded, size: 12, color: AppColors.secondary),
                const SizedBox(width: 4),
                const Text(
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
