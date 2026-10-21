import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_provider.dart';
import '../../features/auth/auth_screen.dart';
import '../../features/auth/infrastructure_setup_screen.dart';
import '../../features/debug/debug_error_screen.dart';
import '../../features/drive/drive_screen.dart';
import '../../features/drive/quick_access_tools_screen.dart';
import '../../features/faces/faces_screen.dart';
import '../../features/media/audio_screen.dart';
import '../../features/media/document_screen.dart';
import '../../features/media/image_screen.dart';
import '../../features/media/media_screen.dart';
import '../../features/media/memories_screen.dart';
import '../../features/media/smart_tags_screen.dart';
import '../../features/media/video_screen.dart';
import '../../features/places/places_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/settings/about_screen.dart';
import '../../features/settings/accounts_screen.dart';
import '../../features/settings/appearance_settings_screen.dart';
import '../../features/settings/channels_screen.dart';
import '../../features/settings/dropbox_backup_screen.dart';
import '../../features/settings/health_check_screen.dart';
import '../../features/settings/load_balancing_screen.dart';
import '../../features/settings/profile_screen.dart';
import '../../features/settings/proxy_settings_screen.dart';
import '../../features/settings/session_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/settings/shared_links_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/transfers/transfers_screen.dart';
import '../../features/trash/trash_screen.dart';
import '../logger.dart';
import '../providers.dart';
import 'responsive_scaffold.dart';

/// Top-level navigation destinations used by the responsive scaffold.
enum AppDestination {
  drive(
    label: 'Drive',
    icon: Icons.folder_outlined,
    selectedIcon: Icons.folder,
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
    icon: Icons.swap_vert_outlined,
    selectedIcon: Icons.swap_vert,
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

class AppRouterNotifier extends ChangeNotifier {
  final Ref _ref;

  AppRouterNotifier(this._ref) {
    _ref.listen<AuthState>(
      authProvider,
      (_, __) => notifyListeners(),
    );
    _ref.listen<bool>(
      hasNavigatedPastSplashProvider,
      (_, __) => notifyListeners(),
    );
  }
}

final routerNotifierProvider = Provider<AppRouterNotifier>((ref) {
  final notifier = AppRouterNotifier(ref);
  ref.onDispose(notifier.dispose);
  return notifier;
});

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(routerNotifierProvider);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final authState = ref.read(authProvider);
      final hasNavigatedPastSplash = ref.read(hasNavigatedPastSplashProvider);

      // Allow splash screen to proceed without redirect.
      if (location == '/splash') {
        // If the user navigates BACK to splash (e.g., after auth), block it
        // by sending them to drive or auth instead.
        if (hasNavigatedPastSplash && context.mounted) {
          final isAuth = authState == AuthState.authenticated;
          return isAuth ? AppDestination.drive.path : '/auth';
        }
        return null;
      }

      // Mark that we've left the splash screen
      if (!hasNavigatedPastSplash) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(hasNavigatedPastSplashProvider.notifier).state = true;
        });
      }

      final isAuth = authState == AuthState.authenticated;
      final isAuthLoading = authState == AuthState.loading;
      final isGoingToAuth = location == '/auth';
      final isGoingToSetup = location == '/setup';

      // If auth is still loading, do not redirect to /setup; stay on current/splash route
      if (isAuthLoading) {
        return null;
      }

      // If not authenticated and not heading to auth → redirect to auth
      if (!isAuth && !isGoingToAuth) {
        return '/auth';
      }

      // If authenticated and on auth or setup → go to drive
      if (isAuth && (isGoingToAuth || isGoingToSetup)) {
        return AppDestination.drive.path;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/auth',
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: '/setup',
        builder: (context, state) => const InfrastructureSetupScreen(),
      ),
      GoRoute(
        path: '/diagnostics',
        builder: (context, state) => DebugErrorScreen(
          logs: AppLogger.logs,
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => ResponsiveScaffold(child: child),
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
            path: '/media/images',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ImagesScreen(),
            ),
          ),
          GoRoute(
            path: '/media/videos',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: VideosScreen(),
            ),
          ),
          GoRoute(
            path: '/media/documents',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: DocumentsScreen(),
            ),
          ),
          GoRoute(
            path: '/media/audios',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: AudiosScreen(),
            ),
          ),
          GoRoute(
            path: '/drive/quick-access',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: QuickAccessToolsScreen(),
            ),
          ),
          GoRoute(
            path: '/media/smart-tags',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SmartTagsScreen(),
            ),
          ),
          GoRoute(
            path: '/media/memories',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: MemoriesScreen(),
            ),
          ),
          GoRoute(
            path: '/media/people',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: FacesScreen(),
            ),
          ),
          GoRoute(
            path: '/media/places',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: PlacesScreen(),
            ),
          ),
          GoRoute(
            path: '/transfers',
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
                path: 'shared_links',
                builder: (context, state) => const SharedLinksScreen(),
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