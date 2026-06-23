import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/theme/aerodrive_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/routing/app_router.dart';
import 'domain/streaming/streaming_server.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:aerodrive/features/sharing/share_service.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:aerodrive/features/drive/providers/drive_providers.dart';
import 'package:media_kit/media_kit.dart';
import 'package:workmanager/workmanager.dart';

import 'core/logger.dart';
import 'features/debug/debug_error_screen.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    return true;
  });
}

/// AeroDrive application entry point.
void main() {
  // Initialize AppLogger first to capture all startup logs.
  AppLogger.init();

  // 1. (Moved inside runZonedGuarded)

  // 2. Allow google_fonts to fetch at runtime for now since the local TTF assets aren't bundled.
  GoogleFonts.config.allowRuntimeFetching = true;

  // 3. Set up global error handlers AFTER binding is initialized.
  FlutterError.onError = (FlutterErrorDetails details) {
    AppLogger.error('Flutter Error', details.exception, details.stack);
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[AeroDrive] Platform Error: $error\n$stack');
    _handleGlobalError(error, stack);
    return true; // Mark as handled to prevent crash
  };

  // Handle errors that occur during widget tree builds.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return DebugErrorScreen(
      error: details.exception,
      stack: details.stack ?? StackTrace.current,
      logs: AppLogger.logs,
    );
  };

  // 4. Run initialization in a guarded zone so any async error shows a crash
  //    screen instead of silently closing the app.
  runZonedGuarded(() async {
    // 1. MUST initialize binding FIRST, inside the same zone as runApp.
    WidgetsFlutterBinding.ensureInitialized();
    
    // --- MediaKit ---
    try {
      MediaKit.ensureInitialized();
    } catch (e, s) {
      debugPrint('[AeroDrive] MediaKit init failed (non-fatal): $e\n$s');
    }

    // --- DotEnv ---
    try {
      await dotenv.load(fileName: ".env");
    } catch (e, s) {
      debugPrint('[AeroDrive] dotenv load failed (non-fatal): $e\n$s');
    }

    // --- Workmanager (mobile only) ---
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        Workmanager().initialize(callbackDispatcher);
      } catch (e) {
        debugPrint('[AeroDrive] Workmanager init skipped: $e');
      }
    }

    // --- Launch App ---
    runApp(const ProviderScope(child: AeroDriveApp()));
  }, (error, stack) {
    debugPrint('[AeroDrive] FATAL Zone Error: $error\n$stack');
    _handleGlobalError(error, stack);
  });
}

/// Root application widget.
class AeroDriveApp extends ConsumerStatefulWidget {
  const AeroDriveApp({super.key});

  @override
  ConsumerState<AeroDriveApp> createState() => _AeroDriveAppState();
}

class _AeroDriveAppState extends ConsumerState<AeroDriveApp> {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    // Handle incoming links while app is running
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleIncomingUri(uri);
    });

    // Handle the initial link if app was closed
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        // Slight delay to ensure Riverpod and DB are fully ready
        Future.delayed(const Duration(seconds: 2), () {
          _handleIncomingUri(initialUri);
        });
      }
    } catch (e) {
      AppLogger.error('Failed to get initial link', e);
    }
  }

  void _handleIncomingUri(Uri uri) async {
    if (uri.scheme == 'aerodrive' && uri.host == 'share') {
      try {
        await ref.read(shareServiceProvider).importShareLink(uri.toString());
        ref.invalidate(folderContentsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File imported successfully from deep link!')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import deep link: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeProvider);
    final router = ref.watch(routerProvider);

    // Initialize background services
    ref.watch(uploadQueueServiceProvider);
    ref.watch(downloadQueueServiceProvider);
    
    // Start local proxy server for media streaming
    ref.read(streamingServerProvider).start();

    return MaterialApp.router(
      title: 'AeroDrive',
      theme: AeroDriveTheme.getLight(themeState),
      darkTheme: AeroDriveTheme.getDark(themeState),
      themeMode: themeState.themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Safely logs a critical/global error and presents the DebugErrorScreen.
void _handleGlobalError(Object error, StackTrace stack) {
  AppLogger.saveCrashLog(error, stack);

  try {
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData.dark(useMaterial3: true),
        home: DebugErrorScreen(
          error: error,
          stack: stack,
          logs: AppLogger.logs,
        ),
      ),
    );
  } catch (e, s) {
    debugPrint('[AeroDrive] Fail-safe crash navigation failed: $e\n$s');
  }
}
