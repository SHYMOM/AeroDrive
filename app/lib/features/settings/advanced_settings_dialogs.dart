import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:aerodrive/features/telegram/telegram_service.dart';
import 'package:aerodrive/core/providers/security_providers.dart';
import 'package:aerodrive/domain/recovery/recovery_scanner.dart';
import 'package:cryptography/cryptography.dart';

class DatabaseStatsDialog extends ConsumerStatefulWidget {
  const DatabaseStatsDialog({super.key});

  @override
  ConsumerState<DatabaseStatsDialog> createState() => _DatabaseStatsDialogState();
}

class _DatabaseStatsDialogState extends ConsumerState<DatabaseStatsDialog> {
  int _fileCount = 0;
  int _folderCount = 0;
  String _dbSize = "Calculating...";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final db = ref.read(databaseProvider);
      
      // Get counts
      final fileRes = await db.customSelect("SELECT COUNT(*) as count FROM files").get();
      final folderRes = await db.customSelect("SELECT COUNT(*) as count FROM folders").get();
      
      _fileCount = fileRes.first.read<int>('count');
      _folderCount = folderRes.first.read<int>('count');

      // Get size
      final appDir = await getApplicationDocumentsDirectory();
      final dbFile = File('${appDir.path}/aerodrive.db');
      if (await dbFile.exists()) {
        final bytes = await dbFile.length();
        _dbSize = '${(bytes / 1024).toStringAsFixed(2)} KB';
      } else {
        _dbSize = 'Unknown';
      }
    } catch (e) {
      _dbSize = 'Error reading stats';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Database Statistics'),
      content: _isLoading 
          ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  leading: const Icon(Icons.insert_drive_file),
                  title: const Text('Files Indexed'),
                  trailing: Text('$_fileCount', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                ListTile(
                  leading: const Icon(Icons.folder),
                  title: const Text('Folders Created'),
                  trailing: Text('$_folderCount', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                ListTile(
                  leading: const Icon(Icons.storage),
                  title: const Text('SQLite DB Size'),
                  trailing: Text(_dbSize, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}

class ClearCacheDialog extends StatefulWidget {
  const ClearCacheDialog({super.key});

  @override
  State<ClearCacheDialog> createState() => _ClearCacheDialogState();
}

class _ClearCacheDialogState extends State<ClearCacheDialog> {
  bool _isClearing = false;

  Future<void> _clearCache() async {
    setState(() => _isClearing = true);
    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        tempDir.listSync(recursive: false).forEach((entity) {
          if (entity is File) entity.deleteSync();
        });
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cache cleared successfully.')));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to clear cache: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Clear Local Cache'),
      content: const Text('This will delete all temporary files, downloaded thumbnails, and partial chunks. It will free up device storage but may require re-downloading thumbnails later.'),
      actions: [
        TextButton(onPressed: _isClearing ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: _isClearing ? null : _clearCache,
          icon: _isClearing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.delete),
          label: const Text('Clear Cache'),
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
        ),
      ],
    );
  }
}

class ResetSettingsDialog extends ConsumerWidget {
  const ResetSettingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: const Text('Reset All Settings'),
      content: const Text('Are you sure you want to revert all AeroDrive settings to their defaults? This will NOT delete your files or database, but you will lose custom preferences.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            // Delete the settings database file or wipe the table.
            final db = ref.read(databaseProvider);
            await db.customStatement("DELETE FROM settings");
            ref.invalidate(settingsRepositoryProvider);
            if (context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings reset. Please restart the app.')));
            }
          },
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Reset'),
        ),
      ],
    );
  }
}

class RebuildDriveDialog extends ConsumerStatefulWidget {
  const RebuildDriveDialog({super.key});

  @override
  ConsumerState<RebuildDriveDialog> createState() => _RebuildDriveDialogState();
}

class _RebuildDriveDialogState extends ConsumerState<RebuildDriveDialog> {
  bool _isRebuilding = false;
  double _progress = 0.0;
  String _status = "Ready to scan.";

  Future<void> _startRebuild() async {
    final activeChannelStr = await ref.read(settingsRepositoryProvider).getSetting('active_channel_id');
    if (activeChannelStr == null) {
      if (mounted) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Error'),
            content: const Text('No active storage channel found. Please add and select a storage channel first.'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
      }
      return;
    }

    final masterKeyList = ref.read(masterKeyProvider);
    if (masterKeyList == null) {
      if (mounted) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Error'),
            content: const Text('Please unlock your drive first (vault must be unlocked to decrypt backup manifests).'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
      }
      return;
    }

    final channelId = int.parse(activeChannelStr);

    setState(() {
      _isRebuilding = true;
      _status = "Scanning Telegram channel messages...";
    });

    try {
      final cipher = AesGcm.with256bits();
      final masterKey = await cipher.newSecretKeyFromBytes(masterKeyList);
      final db = ref.read(databaseProvider);
      final telegramService = ref.read(telegramServiceProvider.notifier);

      final scanner = RecoveryScanner(db, telegramService);
      await scanner.runDisasterRecovery(
        masterKey: masterKey,
        channelId: channelId,
        onProgress: (messagesScanned, itemsRecovered) {
          if (mounted) {
            setState(() {
              _status = "Scanned $messagesScanned messages...\nRecovered $itemsRecovered items.";
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _status = "Rebuild complete!";
        });
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Drive successfully rebuilt from Telegram!')));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRebuilding = false;
          _status = "Error: $e";
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Disaster recovery failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Disaster Recovery'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('This will scan your Telegram storage channels and perfectly rebuild your local AeroDrive database from the message captions.'),
          const SizedBox(height: 16),
          if (_isRebuilding) ...[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Text(_status, style: const TextStyle(fontWeight: FontWeight.bold)),
          ]
        ],
      ),
      actions: [
        if (!_isRebuilding) TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        if (!_isRebuilding) FilledButton.icon(
          onPressed: _startRebuild,
          icon: const Icon(Icons.build),
          label: const Text('Start Rebuild'),
        ),
      ],
    );
  }
}
