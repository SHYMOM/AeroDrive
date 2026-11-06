import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import '../../domain/webdav/webdav_config.dart';
import '../../domain/webdav/webdav_server.dart';
import 'windows_network_drive_service.dart';
import '../logger.dart';

/// Manages the Windows notification area (system tray) icon and background lifecycle.
class TrayService with TrayListener {
  static final TrayService instance = TrayService._();
  TrayService._();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (kIsWeb || !Platform.isWindows) return;
    if (_isInitialized) return;

    trayManager.addListener(this);

    try {
      await trayManager.setIcon('assets/app_icon.ico');
    } catch (_) {
      try {
        await trayManager.setIcon('assets/icon.png');
      } catch (_) {}
    }

    await trayManager.setToolTip('AeroDrive - Encrypted Cloud Storage');
    await updateContextMenu();
    _isInitialized = true;
    AppLogger.info('TrayService: System tray initialized successfully');
  }

  Future<void> updateContextMenu() async {
    if (kIsWeb || !Platform.isWindows) return;

    final isServerRunning = WebDavServer.isRunning;
    String? mountedDrive;
    if (isServerRunning) {
      final port = WebDavServer.activePort ?? WebDavConfigService.defaultPort;
      mountedDrive = await WindowsNetworkDriveService.getMountedDrive(port);
    }

    final menuItems = [
      MenuItem(
        key: 'show_window',
        label: 'Open AeroDrive',
      ),
      MenuItem.separator(),
      if (isServerRunning) ...[
        if (mountedDrive != null) ...[
          MenuItem(
            key: 'open_drive',
            label: 'Open Drive ($mountedDrive)',
          ),
          MenuItem(
            key: 'unmount_drive',
            label: 'Unmount Drive ($mountedDrive)',
          ),
        ] else ...[
          MenuItem(
            key: 'mount_drive',
            label: 'Mount Drive (Z:)',
          ),
        ],
        MenuItem.separator(),
      ],
      MenuItem(
        key: 'quit_app',
        label: 'Quit AeroDrive',
      ),
    ];

    await trayManager.setContextMenu(Menu(items: menuItems));
  }

  @override
  void onTrayIconMouseDown() async {
    await restoreWindow();
  }

  @override
  void onTrayIconRightMouseDown() async {
    await updateContextMenu();
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show_window':
        await restoreWindow();
        break;
      case 'open_drive':
        final port = WebDavServer.activePort ?? WebDavConfigService.defaultPort;
        final drive = await WindowsNetworkDriveService.getMountedDrive(port);
        if (drive != null) {
          Process.run('explorer.exe', [drive]);
        }
        break;
      case 'mount_drive':
        final port = WebDavServer.activePort ?? WebDavConfigService.defaultPort;
        try {
          await WindowsNetworkDriveService.mountDrive(port);
          await updateContextMenu();
        } catch (_) {}
        break;
      case 'unmount_drive':
        final port = WebDavServer.activePort ?? WebDavConfigService.defaultPort;
        final drive = await WindowsNetworkDriveService.getMountedDrive(port);
        if (drive != null) {
          await WindowsNetworkDriveService.unmountDrive(drive);
          await updateContextMenu();
        }
        break;
      case 'quit_app':
        await quitApp();
        break;
    }
  }

  Future<void> restoreWindow() async {
    final isMinimized = await windowManager.isMinimized();
    if (isMinimized) {
      await windowManager.restore();
    }
    await windowManager.show();
    await windowManager.focus();
  }

  /// Cleanly unmounts network drive, stops servers, and terminates the application.
  Future<void> quitApp() async {
    AppLogger.info('TrayService: Quitting AeroDrive...');
    try {
      final port = WebDavServer.activePort ?? WebDavConfigService.defaultPort;
      final drive = await WindowsNetworkDriveService.getMountedDrive(port);
      if (drive != null) {
        await WindowsNetworkDriveService.unmountDrive(drive);
      }
    } catch (_) {}

    try {
      WebDavServer.stop();
    } catch (_) {}

    try {
      trayManager.removeListener(this);
      await trayManager.destroy();
    } catch (_) {}

    try {
      await windowManager.destroy();
    } catch (_) {}

    exit(0);
  }
}

