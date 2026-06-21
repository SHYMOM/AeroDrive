import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aerodrive/core/routing/responsive_scaffold.dart';
import 'package:aerodrive/features/auth/auth_screen.dart';
import 'package:aerodrive/features/auth/auth_provider.dart';
import 'package:aerodrive/features/drive/drive_screen.dart';
import 'package:aerodrive/features/search/search_screen.dart';
import 'package:aerodrive/features/settings/settings_screen.dart';
import 'package:aerodrive/features/trash/trash_screen.dart';
import 'package:aerodrive/features/upload_queue/upload_queue_screen.dart';

/// Top-level navigation destinations used by the responsive scaffold.
enum AppDestination {
  drive(
    label: 'Drive',
    icon: Icons.cloud_outlined,
    selectedIcon: Icons.cloud,
    path: '/drive',
  ),
  uploadQueue(
    label: 'Uploads',
    icon: Icons.upload_outlined,
    selectedIcon: Icons.upload,
    path: '/uploads',
  ),
  search(
    label: 'Search',
    icon: Icons.search_outlined,
    selectedIcon: Icons.search,
    path: '/search',
  ),
  trash(
    label: 'Trash',
    icon: Icons.delete_outline,
    selectedIcon: Icons.delete,
    path: '/trash',
  ),
  settings(
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    path: '/settings',
  );

  const AppDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.path,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String path;
}

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/auth', // Always start at auth evaluation
    redirect: (context, state) {
      final isAuth = authState == AuthState.authenticated;
      final isGoingToAuth = state.matchedLocation == '/auth';

      if (!isAuth && !isGoingToAuth) {
        return '/auth';
      }
      if (isAuth && isGoingToAuth) {
        return AppDestination.drive.path;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/auth',
        builder: (context, state) => const AuthScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) {
          return ResponsiveScaffold(child: child);
        },
        routes: [
          GoRoute(
            path: AppDestination.drive.path,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: DriveScreen(),
            ),
          ),
          GoRoute(
            path: AppDestination.uploadQueue.path,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: UploadQueueScreen(),
            ),
          ),
          GoRoute(
            path: AppDestination.search.path,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SearchScreen(),
            ),
          ),
          GoRoute(
            path: AppDestination.trash.path,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: TrashScreen(),
            ),
          ),
          GoRoute(
            path: AppDestination.settings.path,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SettingsScreen(),
            ),
          ),
        ],
      ),
    ],
  );
});
