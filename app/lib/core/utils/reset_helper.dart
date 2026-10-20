import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tdlib/tdlib.dart';
import '../../features/telegram/telegram_service.dart';

class AppResetHelper {
  static Future<void> showResetConfirmation(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B2F),
        title: const Text('Reset AeroDrive?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will completely wipe all local settings, accounts, files, and database records from this device.\n\nThe application will close. On the next launch, it will start as a fresh installation.\n\nAre you sure you want to perform a hard reset?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Reset Application'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const PopScope(
            canPop: false,
            child: AlertDialog(
              backgroundColor: Color(0xFF1B1B2F),
              content: Row(
                children: [
                  CircularProgressIndicator(color: Colors.redAccent),
                  SizedBox(width: 16),
                  Text('Clearing application data...', style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ),
        );
      }

      try {
        // 1. Close and destroy all active TDLib clients and any orphaned client IDs so files are released
        for (final entry in TelegramService.activeInstances.entries) {
          try {
            TdPlugin.instance.tdSend(entry.key, jsonEncode({"@type": "close"}));
            TdPlugin.instance.tdSend(entry.key, jsonEncode({"@type": "destroy"}));
          } catch (_) {}
        }
        for (var id = 1; id <= 25; id++) {
          try {
            TdPlugin.instance.tdSend(id, jsonEncode({"@type": "destroy"}));
          } catch (_) {}
        }
        await Future.delayed(const Duration(milliseconds: 1000));

        // 2. Delete the entire AeroDrive documents directory
        final docDir = await getApplicationDocumentsDirectory();
        final aerodriveDir = Directory('${docDir.path}${Platform.pathSeparator}AeroDrive');
        if (await aerodriveDir.exists()) {
          await aerodriveDir.delete(recursive: true);
        }

        final sqliteFile = File('${docDir.path}${Platform.pathSeparator}aerodrive.sqlite');
        if (await sqliteFile.exists()) {
          await sqliteFile.delete();
        }
        final sqliteWal = File('${docDir.path}${Platform.pathSeparator}aerodrive.sqlite-wal');
        if (await sqliteWal.exists()) {
          await sqliteWal.delete();
        }
        final sqliteShm = File('${docDir.path}${Platform.pathSeparator}aerodrive.sqlite-shm');
        if (await sqliteShm.exists()) {
          await sqliteShm.delete();
        }

        // 3. Force terminate process to release all native libraries and OS locks
        exit(0);
      } catch (e) {
        debugPrint('Hard reset failed: $e');
        if (context.mounted) {
          Navigator.pop(context); // dismiss loading
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Reset failed: $e. Please close the app and manually clear data.')),
          );
        }
      }
    }
  }
}
