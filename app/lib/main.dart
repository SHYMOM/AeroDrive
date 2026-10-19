import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:app_links/app_links.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:workmanager/workmanager.dart';

import 'core/logger.dart';
import 'core/providers/repository_providers.dart';
import 'core/routing/app_router.dart';
import 'core/theme/aerodrive_theme.dart';
import 'core/theme/theme_provider.dart';
import 'data/db/database.dart';
import 'data/repositories/settings_repository.dart';
import 'domain/auto_backup_watcher.dart';
import 'domain/backup_service.dart';
import 'domain/background_service_manager.dart';
import 'domain/boot_service.dart';
import 'domain/notification_service.dart';
import 'domain/upload_queue_service.dart';
import 'domain/download_queue_service.dart';
import 'domain/folder_scanner.dart';
import 'domain/streaming/streaming_server.dart';
import 'domain/upload_crash_debugger.dart' as crash;
import 'domain/sync/realtime_sync_service.dart';
import 'features/debug/debug_error_screen.dart';
import 'features/drive/providers/drive_providers.dart';
import 'features/sharing/share_service.dart';
import 'core/providers.dart';
import 'features/telegram/telegram_manager.dart';
import 'features/telegram/telegram_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == 'aero_drive_scheduled_backup') {
      try {
        // 1. Check if main app is active
        final mainIsolateActive = IsolateNameServer.lookupPortByName('aerodrive_main_isolate') != null;
        if (mainIsolateActive) {
          debugPrint('[AeroDrive] Background task: Main app is active, skipping background processing.');
          return true;
        }

        // 2. Headless Mode: Initialize ProviderContainer
        final container = ProviderContainer();
        final db = container.read(databaseProvider);
        final settingsRepo = container.read(settingsRepositoryProvider);

        final enabled = await settingsRepo.getSetting('master_autobackup_enabled');
        if (enabled != 'true') {
          container.dispose();
          return true;
        }

        final raw = await settingsRepo.getSetting('tracked_backup_folders');
        if (raw == null || raw.isEmpty) {
          container.dispose();
          return true;
        }

        final List<dynamic> profiles;
        try {
          profiles = jsonDecode(raw) as List<dynamic>;
        } catch (_) {
          container.dispose();
          return true;
        }

        // 3. Wait for Telegram client to restore and be ready
        var ready = false;
        for (var i = 0; i < 30; i++) {
          final readyClients = container.read(telegramManagerProvider)
              .where((c) => c.authState == TelegramAuthState.ready)
              .toList();
          if (readyClients.isNotEmpty) {
            ready = true;
            break;
          }
          await Future.delayed(const Duration(seconds: 1));
        }

        if (!ready) {
          debugPrint('[AeroDrive] Background task: No Telegram client became ready. Exiting.');
          container.dispose();
          return false;
        }

        const uuid = Uuid();
        var queuedCount = 0;

        for (final pProfile in profiles) {
          final profile = pProfile as Map<String, dynamic>;
          final path = profile['path'] as String?;
          if (path == null || path.isEmpty) continue;

          // Background Wi-Fi only constraint check (as a fallback)
          if (profile['wifiOnly'] == true) {
            try {
              final interfaces = await NetworkInterface.list();
              var cellularActive = false;
              var wifiActive = false;

              for (final interface in interfaces) {
                final name = interface.name.toLowerCase();
                if (name.contains('wlan') || name.contains('en') || name.contains('eth') || name.contains('wifi')) {
                  wifiActive = true;
                }
                if (name.contains('rmnet') || name.contains('pdp') || name.contains('ccmni') || name.contains('cellular')) {
                  cellularActive = true;
                }
              }

              if (cellularActive && !wifiActive) {
                debugPrint('[AeroDrive] Background backup: Skipping wifiOnly profile on cellular');
                continue;
              }
            } catch (_) {}
          }

          final destinationFolderId = (profile['destinationFolderId'] == null || profile['destinationFolderId'] == 'null' || profile['destinationFolderId'] == '__root__')
              ? null
              : profile['destinationFolderId'] as String?;
          final folderIdPart = destinationFolderId ?? '';

          final mode = profile['backupMode'] as String? ?? 'local_to_drive';
          final deleteBehavior = profile['deleteBehavior'] as String? ?? 'dont_delete';

          final dir = Directory(path);
          if (!await dir.exists()) continue;

          // 1. Upload files
          if (mode == 'local_to_drive' || mode == 'both') {
            await for (final entity in dir.list(recursive: true, followLinks: false)) {
              if (entity is! File) continue;
              final ext = entity.path.split('.').last.toLowerCase();

              var matches = profile['include_all'] == true;
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
              final fileName = entity.path.contains('/') ? entity.path.split('/').last : entity.path.split('\\').last;

              // Check if file is already in the transfer queue (PENDING, PROCESSING, or ENCRYPTING)
              final normalizedFilePath = entity.path.replaceAll('\\', '/');
              final activeTransfers = await (db.select(db.transferQueue)
                ..where((q) => q.type.equals('UPLOAD_FILE') &
                    (q.status.equals('PENDING') | q.status.equals('PROCESSING') | q.status.equals('ENCRYPTING')))
              ).get();

              final alreadyQueued = activeTransfers.any((task) {
                final queuedRaw = task.fileId?.split('|').firstOrNull ?? '';
                final queuedNormalized = queuedRaw.replaceAll('\\', '/');
                return queuedNormalized.toLowerCase() == normalizedFilePath.toLowerCase();
              });

              if (alreadyQueued) {
                continue;
              }

              // Resolve target folder hierarchy
              final resolvedFolderId = await _resolveBackupFolderIdInDispatcher(container, db, entity.path, path, destinationFolderId);
              final targetFolderIdPart = resolvedFolderId ?? '';

              // Check if file already exists in target folder with same name and size
              final existing = await (db.select(db.files)
                ..where((f) => f.name.equals(fileName) & f.size.equals(fileSize) & (resolvedFolderId == null ? f.folderId.isNull() : f.folderId.equals(resolvedFolderId)) & f.deletedAt.isNull())
              ).get();

              if (existing.isEmpty) {
                final targetFileId = '${entity.path}|$targetFolderIdPart';
                await db.into(db.transferQueue).insert(
                  TransferQueueCompanion.insert(
                    id: uuid.v4(),
                    type: const drift.Value('UPLOAD_FILE'),
                    status: const drift.Value('PENDING'),
                    priority: const drift.Value(1),
                    totalBytes: drift.Value(fileSize),
                    fileId: drift.Value(targetFileId),
                    createdAt: drift.Value(DateTime.now()),
                  ),
                );
                queuedCount++;
              }
            }
          }

          // 2. Sync deletions from Local to Drive
          if (deleteBehavior == 'sync_deletions' && (mode == 'local_to_drive' || mode == 'both')) {
            final dbFiles = await (db.select(db.files)
              ..where((f) => destinationFolderId == null ? f.folderId.isNull() : f.folderId.equals(destinationFolderId))
              ..where((f) => f.deletedAt.isNull())
            ).get();

            for (final dbFile in dbFiles) {
              final localFilePath = p.join(path, dbFile.name);
              final localFile = File(localFilePath);
              if (!await localFile.exists()) {
                // Deleted locally, so soft delete on Drive
                await (db.update(db.files)..where((f) => f.id.equals(dbFile.id))).write(
                  FilesCompanion(deletedAt: drift.Value(DateTime.now())),
                );
              }
            }
          }
        }

        await settingsRepo.setSetting('last_backup_check', DateTime.now().toIso8601String());
        debugPrint('[AeroDrive] Background backup queued $queuedCount files');

        // 4. Initialize Queue Services and process background uploads
        if (queuedCount > 0) {
          final uploadService = container.read(uploadQueueServiceProvider);
          final downloadService = container.read(downloadQueueServiceProvider);

          final startTime = DateTime.now();
          while (DateTime.now().difference(startTime).inMinutes < 8) {
            final pendingCount = await (db.select(db.transferQueue)
              ..where((q) => q.status.equals('PENDING') | q.status.equals('PROCESSING'))
            ).get().then((list) => list.length);

            if (pendingCount == 0) {
              debugPrint('[AeroDrive] Background task: Queue processing complete.');
              break;
            }
            await Future.delayed(const Duration(seconds: 5));
          }
        }

        container.dispose();
        return true;
      } catch (e) {
        debugPrint('[AeroDrive] Background backup error: $e');
        return false;
      }
    }
    return true;
  });
}

Future<String?> _resolveBackupFolderIdInDispatcher(
  ProviderContainer container,
  AeroDriveDatabase db,
  String filePath,
  String trackedFolderPath,
  String? destinationFolderId,
) async {
  const uuid = Uuid();
  final normalizedFilePath = filePath.replaceAll('\\', '/');
  final normalizedTrackedPath = trackedFolderPath.replaceAll('\\', '/');
  
  final relativePath = normalizedFilePath.substring(normalizedTrackedPath.length);
  final parts = relativePath.split('/').where((p) => p.isNotEmpty).toList();

  if (destinationFolderId != null) {
    String? currentFolderId = destinationFolderId;
    if (parts.length > 1) {
      for (final folderName in parts.sublist(0, parts.length - 1)) {
        var folder = await (db.select(db.folders)
          ..where((f) => f.name.equals(folderName) & 
              (currentFolderId == null ? f.parentId.isNull() : f.parentId.equals(currentFolderId)) & 
              f.deletedAt.isNull())
        ).getSingleOrNull();

        if (folder == null) {
          final newId = uuid.v4();
          await db.into(db.folders).insert(
            FoldersCompanion.insert(
              id: newId,
              name: folderName,
              parentId: drift.Value(currentFolderId),
              createdAt: drift.Value(DateTime.now()),
            )
          );
          try {
            final folderScanner = container.read(folderScannerProvider);
            unawaited(folderScanner.uploadFolderManifest(newId, folderName, currentFolderId));
          } catch (e) {
            debugPrint('Failed to upload folder manifest in background: $e');
          }
          currentFolderId = newId;
        } else {
          currentFolderId = folder.id;
        }
      }
    }
    return currentFolderId;
  }

  final String deviceName = Platform.isAndroid 
      ? "Android Device" 
      : Platform.isIOS 
          ? "iOS Device" 
          : Platform.isWindows 
              ? "Windows PC" 
              : Platform.isMacOS 
                  ? "Mac" 
                  : "Linux Device";

  final trackedFolderName = trackedFolderPath.contains('/') 
      ? trackedFolderPath.split('/').lastWhere((s) => s.isNotEmpty, orElse: () => "Backup") 
      : trackedFolderPath.split('\\').lastWhere((s) => s.isNotEmpty, orElse: () => "Backup");

  final List<String> folderHierarchy = ["Backups", deviceName, trackedFolderName];
  if (parts.length > 1) {
    folderHierarchy.addAll(parts.sublist(0, parts.length - 1));
  }

  String? currentFolderId;
  for (final folderName in folderHierarchy) {
    var folder = await (db.select(db.folders)
      ..where((f) => f.name.equals(folderName) & 
          (currentFolderId == null ? f.parentId.isNull() : f.parentId.equals(currentFolderId)) & 
          f.deletedAt.isNull())
    ).getSingleOrNull();

    if (folder == null) {
      final newId = uuid.v4();
      await db.into(db.folders).insert(
        FoldersCompanion.insert(
          id: newId,
          name: folderName,
          parentId: drift.Value(currentFolderId),
          createdAt: drift.Value(DateTime.now()),
        )
      );
      try {
        final folderScanner = container.read(folderScannerProvider);
        unawaited(folderScanner.uploadFolderManifest(newId, folderName, currentFolderId));
      } catch (e) {
        debugPrint('Failed to upload folder manifest in background: $e');
      }
      currentFolderId = newId;
    } else {
      currentFolderId = folder.id;
    }
  }

  return currentFolderId;
}

RawServerSocket? _uiLockSocket;

/// AeroDrive application entry point.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize AppLogger first to capture all startup logs.
  AppLogger.init();

  // Register main isolate port to indicate that the UI is active
  final receivePort = ReceivePort();
  IsolateNameServer.registerPortWithName(receivePort.sendPort, 'aerodrive_main_isolate');

  // Signal any running background headless service to yield the port lock
  try {
    final socket = await Socket.connect('127.0.0.1', 46828, timeout: const Duration(seconds: 1));
    await socket.close();
    // Wait for the background engine to shut down and release the port
    await Future.delayed(const Duration(milliseconds: 1500));
  } catch (_) {}

  // Bind main UI lock port
  try {
    _uiLockSocket = await RawServerSocket.bind('127.0.0.1', 46828);
    AppLogger.info('[AeroDrive UI] Successfully acquired UI isolate lock.');
  } catch (e) {
    AppLogger.warning('[AeroDrive UI] Failed to acquire UI isolate lock: $e');
  }

  // 2. Allow google_fonts to fetch at runtime (fonts not bundled as assets).
  GoogleFonts.config.allowRuntimeFetching = true;

  // 3. Set up global error handlers AFTER binding is initialized.
  FlutterError.onError = (details) {
    AppLogger.error('Flutter Error', details.exception, details.stack);
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[AeroDrive] Platform Error: $error\n$stack');
    _handleGlobalError(error, stack);
    return true; // Mark as handled to prevent crash
  };

  // Handle errors that occur during widget tree builds.
  ErrorWidget.builder = (details) => DebugErrorScreen(
      error: details.exception,
      stack: details.stack ?? StackTrace.current,
      logs: AppLogger.logs,
    );

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
      await dotenv.load(fileName: '.env');
    } catch (e, s) {
      debugPrint('[AeroDrive] dotenv load failed (non-fatal): $e\n$s');
    }

    // --- Workmanager (mobile only) ---
    // Background auto-backup runs when app is closed/in background
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
        // Register periodic background backup task:
        // - No charging requirement (runs anytime)
        // - No battery-low constraint (we want reliable background backup)
        // - Minimum 15-minute frequency (Android enforced minimum)
        await Workmanager().registerPeriodicTask(
          'aero_drive_backup',
          'aero_drive_scheduled_backup',
          frequency: const Duration(minutes: 15),
          initialDelay: const Duration(minutes: 2),
          constraints: Constraints(
            networkType: NetworkType.connected,
            requiresBatteryNotLow: false,
            requiresCharging: false,
          ),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
          backoffPolicy: BackoffPolicy.linear,
          backoffPolicyDelay: const Duration(minutes: 5),
        );
        debugPrint('[AeroDrive] Background backup task registered successfully');
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

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
    _checkScheduledBackup();

    // Detect any crashed upload from the previous session.
    // The file logger writes continuously during uploads so the log
    // survives an OOM kill. If active_upload.log exists on startup,
    // the upload was interrupted.
    Future.microtask(() async {
      try {
        final crashLog = await crash.UploadFileLogger.detectCrashedUpload();
        if (crashLog != null) {
          AppLogger.warning('Previous upload crashed. Crash log detected in Downloads/AeroDrive/logs/');
          // The log was renamed to crash_<ts>.log by detectCrashedUpload()
        }
      } catch (_) {}
    });
    Future.microtask(() async {
      try {
        ref.read(autoBackupWatcherProvider).start();
        // Start the foreground backup service on Android so backup
        // continues even when the user swipes the app away from recents.
        final settingsRepo = ref.read(settingsRepositoryProvider);
        final autoBackupEnabled = await settingsRepo.getSetting('master_autobackup_enabled');
        if (autoBackupEnabled == 'true') {
          await BackgroundServiceManager.startService();
        }
      } catch (e) {
        AppLogger.error('Failed to start auto-backup watcher', e);
      }
    });


    // If launched from BOOT_COMPLETED, trigger immediate sync
    _handleBootLaunch();
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
          case 'monthly':
            interval = const Duration(days: 30);
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
    _linkSubscription = _appLinks.uriLinkStream.listen(_handleIncomingUri);

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

  Future<void> _handleIncomingUri(Uri uri) async {
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
    IsolateNameServer.removePortNameMapping('aerodrive_main_isolate');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeProvider);
    final router = ref.watch(routerProvider);

    // Map saved locale string to a Locale object
    Locale? locale;
    switch (themeState.localeString) {
      case 'English':
        locale = const Locale('en');
      case 'Spanish':
        locale = const Locale('es');
      case 'French':
        locale = const Locale('fr');
      case 'German':
        locale = const Locale('de');
      // 'System Default' -> null (use system locale)
    }

    // Initialize background services
    ref.watch(uploadQueueServiceProvider);
    ref.watch(downloadQueueServiceProvider);
    ref.watch(realtimeSyncServiceProvider).startListening();

    // Start local proxy server for media streaming
    ref.read(streamingServerProvider).start();

    return MaterialApp.router(
      title: 'AeroDrive',
      theme: AeroDriveTheme.getLight(themeState),
      darkTheme: AeroDriveTheme.getDark(themeState),
      themeMode: themeState.themeMode,
      locale: locale,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Safely logs a critical/global error and presents the DebugErrorScreen.
void _handleGlobalError(Object error, StackTrace stack) {
  // Save crash log (sync-ish — delegates async write to a microtask)
  AppLogger.saveCrashLog(error, stack);

  // Also write a standalone crash report to the public Downloads/AeroDrive/logs/
  // directory so the user can easily find and share it. This runs async but
  // the error handler must return immediately, so we fire-and-forget.
  _savePublicCrashReport(error, stack);

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

/// Writes a crash report to Downloads/AeroDrive/logs/ so the user can share it.
void _savePublicCrashReport(Object error, StackTrace stack) {
  // Use a microtask so we don't block the error handler
  Future.microtask(() async {
    try {
      Directory logDir;
      if (Platform.isAndroid) {
        logDir = Directory('/storage/emulated/0/Download/AeroDrive/logs');
      } else {
        final downloadDir = await getDownloadsDirectory();
        if (downloadDir != null) {
          logDir = Directory('${downloadDir.path}${Platform.pathSeparator}AeroDrive${Platform.pathSeparator}logs');
        } else {
          final appDir = await getApplicationDocumentsDirectory();
          logDir = Directory('${appDir.path}${Platform.pathSeparator}AeroDrive${Platform.pathSeparator}logs');
        }
      }

      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${logDir.path}${Platform.pathSeparator}crash_$timestamp.log';

      final buffer = StringBuffer();
      buffer.writeln('=== AERO DRIVE CRASH REPORT ===');
      buffer.writeln('Timestamp: ${DateTime.now().toIso8601String()}');
      buffer.writeln('App Version: 0.1.0-alpha.1');
      buffer.writeln('');
      buffer.writeln('Exception: $error');
      buffer.writeln('');
      buffer.writeln('Stack Trace:');
      buffer.writeln(stack.toString());
      buffer.writeln('');
      buffer.writeln('=== APPLICATION LOG BUFFER ===');
      for (final log in AppLogger.logs) {
        buffer.writeln(log);
      }

      await File(filePath).writeAsString(buffer.toString());
      debugPrint('[AeroDrive] Public crash report saved to: $filePath');
    } catch (e) {
      // Can't do much — we're already in an error handler
      debugPrint('[AeroDrive] Failed to save public crash report: $e');
    }
  });
}

RawServerSocket? _backgroundLockSocket;
bool _backgroundIsSyncing = false;
ProviderContainer? _backgroundContainer;

void _tryAcquireBackgroundLock() async {
  try {
    final socket = await RawServerSocket.bind('127.0.0.1', 46828);
    _backgroundLockSocket = socket;
    debugPrint('[AeroDrive Background] Successfully bound port lock. Starting background sync.');
    
    // Listen for UI launching connection to yield the lock
    socket.listen((client) async {
      debugPrint('[AeroDrive Background] UI app requested lock. Yielding...');
      await client.close();
      _stopBackgroundSync();
    });

    _startBackgroundSync();
  } catch (_) {
    // Port in use (UI active). Retry in 15 seconds.
    Future.delayed(const Duration(seconds: 15), _tryAcquireBackgroundLock);
  }
}

void _startBackgroundSync() {
  if (_backgroundIsSyncing) return;
  _backgroundIsSyncing = true;

  _backgroundContainer = ProviderContainer();
  _backgroundContainer!.read(autoBackupWatcherProvider).start();
  _backgroundContainer!.read(uploadQueueServiceProvider);
  _backgroundContainer!.read(downloadQueueServiceProvider);
  _backgroundContainer!.read(realtimeSyncServiceProvider).startListening();
}

void _stopBackgroundSync() async {
  if (!_backgroundIsSyncing) return;
  _backgroundIsSyncing = false;

  try {
    if (_backgroundContainer != null) {
      _backgroundContainer!.read(autoBackupWatcherProvider).stop();
      _backgroundContainer!.read(realtimeSyncServiceProvider).stopListening();
      // Dispose the container to release and close TDLib clients!
      _backgroundContainer!.dispose();
      _backgroundContainer = null;
    }
  } catch (e) {
    debugPrint('[AeroDrive Background] Error stopping background sync: $e');
  }

  try {
    if (_backgroundLockSocket != null) {
      await _backgroundLockSocket!.close();
      _backgroundLockSocket = null;
    }
  } catch (_) {}

  // Restart the lock retry loop after yielding
  Future.delayed(const Duration(seconds: 15), _tryAcquireBackgroundLock);
}

@pragma('vm:entry-point')
void backgroundMain() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {}

    debugPrint('[AeroDrive] Headless background engine started. Acquiring lock...');
    _tryAcquireBackgroundLock();
  }, (error, stack) {
    debugPrint('[AeroDrive] Headless background engine fatal error: $error\n$stack');
  });
}
