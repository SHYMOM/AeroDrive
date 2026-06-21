import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../constants.dart';
import '../theme/app_colors.dart';
import 'app_router.dart';
import '../../widgets/aerodrive_logo.dart';

/// A responsive scaffold that adapts navigation based on screen width.
///
/// - **Desktop** (≥ 1024px): persistent sidebar with logo + nav items.
/// - **Tablet** (600–1023px): collapsible [NavigationRail].
/// - **Mobile** (< 600px): [NavigationBar] at the bottom.
class ResponsiveScaffold extends StatelessWidget {
  const ResponsiveScaffold({super.key, required this.child});

  /// The routed content page to display.
  final Widget child;

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        if (width >= AppConstants.desktopBreakpoint) {
          return _DesktopLayout(
            selectedIndex: _currentIndex(context),
            onDestinationSelected: (i) => _onDestinationSelected(context, i),
            child: child,
          );
        } else if (width >= AppConstants.mobileBreakpoint) {
          return _TabletLayout(
            selectedIndex: _currentIndex(context),
            onDestinationSelected: (i) => _onDestinationSelected(context, i),
            child: child,
          );
        } else {
          return _MobileLayout(
            selectedIndex: _currentIndex(context),
            onDestinationSelected: (i) => _onDestinationSelected(context, i),
            child: child,
          );
        }
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Desktop: Persistent sidebar + content
// ─────────────────────────────────────────────────────────────────────

class _DesktopLayout extends StatelessWidget {
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
    final theme = Theme.of(context);

    return Scaffold(
      body: Row(
        children: [
          // ── Sidebar ───────────────────────────────────────────
          Container(
            width: 240,
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(
                right: BorderSide(
                  color: AppColors.outline.withValues(alpha: 0.5),
                  width: 0.5,
                ),
              ),
            ),
            child: Column(
              children: [
                // Logo section
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 24, 20, 24),
                  child: AeroDriveLogo(size: AeroDriveLogoSize.medium),
                ),
                Divider(
                  color: AppColors.outline.withValues(alpha: 0.3),
                  height: 1,
                ),
                const SizedBox(height: 12),

                // Nav items
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: AppDestination.values.length,
                    itemBuilder: (context, index) {
                      final dest = AppDestination.values[index];
                      final isSelected = index == selectedIndex;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Material(
                          color: isSelected
                              ? AppColors.primary.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => onDestinationSelected(index),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected
                                        ? dest.selectedIcon
                                        : dest.icon,
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.onSurfaceVariant,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 14),
                                  Text(
                                    dest.label,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.onSurfaceVariant,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Version info at bottom
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'v${AppConstants.appVersion}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Content ───────────────────────────────────────────
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Tablet: Navigation Rail + content
// ─────────────────────────────────────────────────────────────────────

class _TabletLayout extends StatelessWidget {
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
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: AeroDriveLogo(size: AeroDriveLogoSize.small),
            ),
            destinations: AppDestination.values.map((dest) {
              return NavigationRailDestination(
                icon: Icon(dest.icon),
                selectedIcon: Icon(dest.selectedIcon),
                label: Text(dest.label),
              );
            }).toList(),
          ),
          VerticalDivider(
            width: 1,
            thickness: 0.5,
            color: AppColors.outline.withValues(alpha: 0.5),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Mobile: Bottom Navigation Bar + content
// ─────────────────────────────────────────────────────────────────────

class _MobileLayout extends StatelessWidget {
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
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: AppDestination.values.map((dest) {
          return NavigationDestination(
            icon: Icon(dest.icon),
            selectedIcon: Icon(dest.selectedIcon),
            label: dest.label,
          );
        }).toList(),
      ),
    );
  }
}
