import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aerodrive/core/routing/responsive_scaffold.dart';
import 'package:aerodrive/features/auth/auth_screen.dart';
import 'package:aerodrive/features/auth/auth_provider.dart';
import 'package:aerodrive/features/drive/drive_screen.dart';
import 'package:aerodrive/features/search/search_screen.dart';
import 'package:aerodrive/features/settings/settings_screen.dart';
import 'package:aerodrive/features/settings/channels_screen.dart';
import 'package:aerodrive/features/trash/trash_screen.dart';
import 'package:aerodrive/features/media/media_screen.dart';
import 'package:aerodrive/features/transfers/transfers_screen.dart';
import 'package:aerodrive/features/debug/debug_error_screen.dart';
import 'package:aerodrive/core/logger.dart';
import 'package:aerodrive/core/providers/security_providers.dart';
import 'package:aerodrive/features/security/security_setup_screen.dart';
import 'package:aerodrive/features/security/lock_screen.dart';
import 'package:aerodrive/features/settings/proxy_settings_screen.dart';
import 'package:aerodrive/features/settings/appearance_settings_screen.dart';

import 'package:aerodrive/features/settings/accounts_screen.dart';
import 'package:aerodrive/features/settings/session_screen.dart';
import 'package:aerodrive/features/settings/profile_screen.dart';
import 'package:aerodrive/features/settings/load_balancing_screen.dart';
import 'package:aerodrive/features/settings/health_check_screen.dart';
import 'package:aerodrive/features/settings/dropbox_backup_screen.dart';
import 'package:aerodrive/features/settings/about_screen.dart';

/// Top-level navigation destinations used by the responsive scaffold.
enum AppDestination {
  drive(
    label: 'Drive',
    icon: Icons.cloud_outlined,
    selectedIcon: Icons.cloud,
    path: '/drive',
  ),
  media(
    label: 'Media',
    icon: Icons.photo_library_outlined,
    selectedIcon: Icons.photo_library,
    path: '/media',
  ),
  transfers(
    label: 'Transfers',
    icon: Icons.swap_vert_circle_outlined,
    selectedIcon: Icons.swap_vert_circle,
    path: '/transfers',
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
  final isUnlocked = ref.watch(isAppUnlockedProvider);
  final hasPasswordAsync = ref.watch(isMasterPasswordSetupProvider);

  return GoRouter(
    initialLocation: '/auth', // Always start at auth evaluation
    redirect: (context, state) {
      final isAuth = authState == AuthState.authenticated;
      final isGoingToAuth = state.matchedLocation == '/auth';
      
      if (!isAuth && !isGoingToAuth) {
        return '/auth';
      }

      // If authenticated, check security lock
      if (isAuth) {
        final hasPassword = hasPasswordAsync.valueOrNull ?? false;
        final isGoingToLock = state.matchedLocation == '/lock';

        if (hasPassword && !isUnlocked && !isGoingToLock) {
          return '/lock';
        }
        if (isGoingToAuth && (!hasPassword || isUnlocked)) {
          return AppDestination.drive.path;
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/auth',
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: '/lock',
        builder: (context, state) => const LockScreen(),
      ),
      GoRoute(
        path: '/security_setup',
        builder: (context, state) => const SecuritySetupScreen(),
      ),
      GoRoute(
        path: '/diagnostics',
        builder: (context, state) => DebugErrorScreen(
          logs: AppLogger.logs,
        ),
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
            path: AppDestination.media.path,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: MediaScreen(),
            ),
          ),
          GoRoute(
            path: AppDestination.transfers.path,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: TransfersScreen(),
            ),
          ),
          GoRoute(
            path: '/search',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SearchScreen(),
            ),
          ),
          GoRoute(
            path: '/trash',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: TrashScreen(),
            ),
          ),
          GoRoute(
            path: AppDestination.settings.path,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SettingsScreen(),
            ),
            routes: [
              GoRoute(
                path: 'channels',
                builder: (context, state) => const ChannelsScreen(),
              ),
              GoRoute(
                path: 'proxy',
                builder: (context, state) => const ProxySettingsScreen(),
              ),
              GoRoute(
                path: 'appearance',
                builder: (context, state) => const AppearanceSettingsScreen(),
              ),
              GoRoute(
                path: 'accounts',
                builder: (context, state) => const AccountsScreen(),
              ),
              GoRoute(
                path: 'session',
                builder: (context, state) => const SessionScreen(),
              ),
              GoRoute(
                path: 'profile',
                builder: (context, state) => const ProfileScreen(),
              ),
              GoRoute(
                path: 'channels/load_balancing',
                builder: (context, state) => const LoadBalancingScreen(),
              ),
              GoRoute(
                path: 'channels/health',
                builder: (context, state) => const HealthCheckScreen(),
              ),
              GoRoute(
                path: 'backup/dropbox',
                builder: (context, state) => const DropboxBackupScreen(),
              ),
              GoRoute(
                path: 'about',
                builder: (context, state) => const AboutScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
