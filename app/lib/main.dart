import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;

import 'core/theme/aerodrive_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/routing/app_router.dart';
import 'domain/streaming/streaming_server.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:aerodrive/features/sharing/share_service.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:aerodrive/core/providers/security_providers.dart';
import 'package:aerodrive/features/drive/providers/drive_providers.dart';
import 'package:aerodrive/domain/recovery/recovery_scanner.dart';
import 'package:aerodrive/domain/saved_messages_sync.dart';
import 'package:media_kit/media_kit.dart';
import 'package:workmanager/workmanager.dart';
import 'package:cryptography/cryptography.dart';

import 'core/logger.dart';
import 'domain/notification_service.dart';
import 'features/debug/debug_error_screen.dart';
import 'domain/boot_service.dart';
import 'domain/backup_service.dart';
import 'domain/auto_backup_watcher.dart';
import 'domain/auto_lock_service.dart';
import 'data/repositories/settings_repository.dart';
import 'data/db/database.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == 'aero_drive_scheduled_backup') {
      try {
        final db = AeroDriveDatabase();
        final settingsRepo = SettingsRepository(db);

        final enabled = await settingsRepo.getSetting('master_autobackup_enabled');
        if (enabled != 'true') return true;

        final raw = await settingsRepo.getSetting('tracked_backup_folders');
        if (raw == null || raw.isEmpty) return true;

        final List<dynamic> profiles;
        try {
          profiles = jsonDecode(raw) as List<dynamic>;
        } catch (_) {
          return true;
        }

        final uuid = const Uuid();
        int queuedCount = 0;

        for (final p in profiles) {
          final profile = p as Map<String, dynamic>;
          final path = profile['path'] as String?;
          if (path == null || path.isEmpty) continue;

          // Bug 10 fix: read destination folder ID from profile; treat missing/null as
          // empty string which the upload service interprets as root (SQL NULL folder).
          // Previously this was hardcoded as the literal string "null" which broke FK
          // constraints in the Drift database.
          final destinationFolderId = profile['destinationFolderId'] as String?;
          final folderIdPart = (destinationFolderId == null || destinationFolderId.isEmpty)
              ? '' // empty = root
              : destinationFolderId;

          final dir = Directory(path);
          if (!await dir.exists()) continue;

          await for (final entity in dir.list(recursive: true, followLinks: false)) {
            if (entity is! File) continue;
            final ext = entity.path.split('.').last.toLowerCase();

            bool matches = profile['include_all'] == true;
            if (!matches && profile['include_images'] == true) {
              matches = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg', 'heic', 'heif'].contains(ext);
            }
            if (!matches && profile['include_videos'] == true) {
              matches = ['mp4', 'mkv', 'mov', 'avi', 'wmv', 'flv', 'webm', 'm4v', '3gp'].contains(ext);
            }
            if (!matches && profile['include_documents'] == true) {
              matches = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv', 'json', 'xml', 'md'].contains(ext);
            }

            if (!matches) continue;
            final fileSize = await entity.length();
            await db.into(db.transferQueue).insert(
              TransferQueueCompanion.insert(
                id: uuid.v4(),
                type: const drift.Value('UPLOAD_FILE'),
                status: const drift.Value('PENDING'),
                priority: const drift.Value(1),
                totalBytes: drift.Value(fileSize),
                // Format: "localFilePath|destinationFolderId"
                // Empty string after | means root folder (SQL NULL).
                fileId: drift.Value('${entity.path}|$folderIdPart'),
                createdAt: drift.Value(DateTime.now()),
              ),
            );
            queuedCount++;
          }
        }

        await settingsRepo.setSetting('last_backup_check', DateTime.now().toIso8601String());
        await db.close();
        debugPrint('[AeroDrive] Background backup queued $queuedCount files');
        return true;
      } catch (e) {
        debugPrint('[AeroDrive] Background backup error: $e');
        return false;
      }
    }
    return true;
  });
}

/// AeroDrive application entry point.
void main() {
  // Initialize AppLogger first to capture all startup logs.
  AppLogger.init();

  // 1. (Moved inside runZonedGuarded)

  // 2. Allow google_fonts to fetch at runtime (fonts not bundled as assets).
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
    
    // --- Notification Service ---
    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await NotificationService.instance.initialize();
        await NotificationService.instance.requestPermissions();
      }
    } catch (e, s) {
      debugPrint('[AeroDrive] NotificationService init failed: $e\n$s');
    }

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
        await Workmanager().initialize(callbackDispatcher);
        await Workmanager().registerPeriodicTask(
          'aero_drive_backup',
          'aero_drive_scheduled_backup',
          frequency: const Duration(minutes: 15),
          constraints: Constraints(
            networkType: NetworkType.connected,
            requiresBatteryNotLow: true,
            requiresCharging: true,
          ),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
        );
      } catch (e) {
        debugPrint('[AeroDrive] Workmanager init skipped: $e');
      }
    }

    // --- Ensure Application Folder Exists ---
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final aerodriveDir = Directory('${appDir.path}${Platform.pathSeparator}AeroDrive');
      if (!await aerodriveDir.exists()) {
        await aerodriveDir.create(recursive: true);
        AppLogger.info('Created application folder: ${aerodriveDir.path}');
      }
    } catch (e) {
      AppLogger.error('Failed to create application folder', e);
    }

    // --- Ensure Public AeroDrive Folder Tree (Downloads/AeroDrive/) ---
    if (!kIsWeb && Platform.isAndroid) {
      final folderError = await BackupService.ensurePublicFolders();
      if (folderError != null) {
        AppLogger.error('Public folder setup: $folderError');
      } else {
        AppLogger.info('Public AeroDrive folders ready at Download/AeroDrive/');
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
  AutoLockService? _autoLock;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
    _checkScheduledBackup();
    Future.microtask(() {
      try {
        ref.read(autoBackupWatcherProvider).start();
      } catch (e) {
        AppLogger.error('Failed to start auto-backup watcher', e);
      }
    });

    // Start auto-lock service
    _autoLock = AutoLockService(ref);
    _autoLock!.start();

    // If launched from BOOT_COMPLETED, trigger immediate sync
    _handleBootLaunch();
  }

  /// Runs sync operations after the user unlocks (master key becomes available).
  void _syncAfterUnlock() {
    _runSavedMessagesSync();
    _runChannelCaptionSync();
  }

  Future<void> _runSavedMessagesSync() async {
    try {
      final masterKeyList = ref.read(masterKeyProvider);
      if (masterKeyList == null) return;
      final settings = ref.read(settingsRepositoryProvider);
      final enabled = await settings.getSetting('saved_messages_sync_enabled');
      if (enabled != 'true') return;

      final cipher = AesGcm.with256bits();
      final masterKey = await cipher.newSecretKeyFromBytes(masterKeyList);
      final sync = ref.read(savedMessagesSyncProvider);
      final restored = await sync.restoreFromSavedMessages(masterKey);
      if (restored) {
        ref.read(dbRebuildVersionProvider.notifier).state++;
        AppLogger.info('Post-unlock sync: merged Saved Messages data');
      }
    } catch (e, s) {
      AppLogger.error('Post-unlock Saved Messages sync failed', e, s);
    }
  }

  Future<void> _runChannelCaptionSync() async {
    try {
      final masterKeyList = ref.read(masterKeyProvider);
      if (masterKeyList == null) return;
      final settings = ref.read(settingsRepositoryProvider);
      final enabled = await settings.getSetting('channel_caption_sync_enabled');
      if (enabled != 'true') return;

      final activeChannelStr = await settings.getSetting('active_channel_id');
      if (activeChannelStr == null) return;

      final cipher = AesGcm.with256bits();
      final masterKey = await cipher.newSecretKeyFromBytes(masterKeyList);
      final scanner = ref.read(recoveryServiceProvider);
      await scanner.runDisasterRecovery(
        masterKey: masterKey,
        channelId: int.parse(activeChannelStr),
      );
      ref.read(dbRebuildVersionProvider.notifier).state++;
      AppLogger.info('Post-unlock sync: merged channel caption data');
    } catch (e, s) {
      AppLogger.error('Post-unlock channel caption sync failed', e, s);
    }
  }

  Future<void> _handleBootLaunch() async {
    try {
      final fromBoot = await BootService.isBootCompleted();
      if (!fromBoot) return;
      AppLogger.info('App launched from BOOT_COMPLETED, running immediate sync');

      final backupService = ref.read(backupServiceProvider);
      await backupService.runScheduledBackup();
    } catch (e, s) {
      AppLogger.error('Boot launch sync failed', e, s);
    }
  }

  Future<void> _checkScheduledBackup() async {
    Future.delayed(const Duration(seconds: 10), () async {
      try {
        final settingsRepo = ref.read(settingsRepositoryProvider);
        final enabled = await settingsRepo.getSetting('master_autobackup_enabled');
        if (enabled != 'true') return;

        final schedule = await settingsRepo.getSetting('auto_backup_schedule') ?? 'weekly';
        final lastBackupStr = await settingsRepo.getSetting('last_backup_at');

        Duration interval;
        switch (schedule) {
          case 'daily':
            interval = const Duration(hours: 24);
            break;
          case 'monthly':
            interval = const Duration(days: 30);
            break;
          default:
            interval = const Duration(days: 7);
        }

        if (lastBackupStr != null) {
          final lastBackup = DateTime.tryParse(lastBackupStr);
          if (lastBackup != null && DateTime.now().difference(lastBackup) < interval) {
            AppLogger.info('Scheduled backup not due yet. Last: $lastBackup');
            return;
          }
        }

        AppLogger.info('Scheduled backup is due. Running...');
        final backupService = ref.read(backupServiceProvider);
        await backupService.runScheduledBackup();

        await settingsRepo.setSetting('last_backup_at', DateTime.now().toIso8601String());

        final notifyEnabled = await settingsRepo.getSetting('notify_backup_complete');
        if (notifyEnabled == 'true' && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Auto-backup completed successfully!')),
          );
        }
      } catch (e, s) {
        AppLogger.error('Scheduled backup check failed', e, s);
      }
    });
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
    _autoLock?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeProvider);
    final router = ref.watch(routerProvider);

    // Trigger sync when the master key becomes available (user unlocks).
    ref.listen(masterKeyProvider, (prev, next) {
      if (prev == null && next != null) {
        _syncAfterUnlock();
      }
    });

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
