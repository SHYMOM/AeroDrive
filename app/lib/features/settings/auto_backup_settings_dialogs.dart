import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../domain/auto_backup_watcher.dart';
import '../drive/widgets/folder_picker_dialog.dart';

class ManageBackupFoldersScreen extends ConsumerStatefulWidget {
  const ManageBackupFoldersScreen({super.key});

  @override
  ConsumerState<ManageBackupFoldersScreen> createState() => _ManageBackupFoldersScreenState();
}

class _ManageBackupFoldersScreenState extends ConsumerState<ManageBackupFoldersScreen> {
  List<Map<String, dynamic>> _profiles = [];
  bool _isLoading = true;
  bool _powerSaving = false;
  bool _isBatteryOptimizationsIgnored = false;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final raw = await ref.read(settingsRepositoryProvider).getSetting('tracked_backup_folders');
    if (raw != null && raw.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(raw);
        _profiles = decoded.cast<Map<String, dynamic>>();
      } catch (e) {
        _profiles = [];
      }
    } else {
      _profiles = [];
    }

    final powerSavingStr = await ref.read(settingsRepositoryProvider).getSetting('auto_backup_power_saving');
    _powerSaving = powerSavingStr != 'false'; // Defaults to true (saving power)

    await _checkBatteryOptimizations();

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _checkBatteryOptimizations() async {
    if (!kIsWeb && Platform.isAndroid) {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (mounted) {
        setState(() {
          _isBatteryOptimizationsIgnored = status.isGranted;
        });
      }
    }
  }

  Future<void> _requestIgnoreBatteryOptimizations() async {
    if (!kIsWeb && Platform.isAndroid) {
      final status = await Permission.ignoreBatteryOptimizations.request();
      if (mounted) {
        setState(() {
          _isBatteryOptimizationsIgnored = status.isGranted;
        });
      }
    }
  }

  Future<void> _updateWorkmanagerConstraints() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        final wifiOnly = _profiles.any((p) => p['wifiOnly'] == true);
        await Workmanager().cancelAll();
        
        final enabled = await ref.read(settingsRepositoryProvider).getSetting('master_autobackup_enabled');
        if (enabled == 'true' && _profiles.isNotEmpty) {
          final powerSavingStr = await ref.read(settingsRepositoryProvider).getSetting('auto_backup_power_saving');
          final isPowerSaving = powerSavingStr != 'false';

          await Workmanager().registerPeriodicTask(
            'aero_drive_backup',
            'aero_drive_scheduled_backup',
            frequency: const Duration(minutes: 15),
            constraints: Constraints(
              networkType: wifiOnly ? NetworkType.unmetered : NetworkType.connected,
              requiresBatteryNotLow: isPowerSaving,
              requiresCharging: isPowerSaving,
            ),
            existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
          );
          debugPrint('[AeroDrive] Workmanager constraints updated. wifiOnly=$wifiOnly powerSaving=$isPowerSaving');
        }
      } catch (e) {
        debugPrint('[AeroDrive] Failed to update Workmanager constraints: $e');
      }
    }
  }

  Future<void> _saveProfiles() async {
    await ref.read(settingsRepositoryProvider).setSetting('tracked_backup_folders', jsonEncode(_profiles));
    await _updateWorkmanagerConstraints();
    
    // Notify the watcher to refresh watchers instantly
    ref.read(autoBackupWatcherProvider).start();

    if (mounted) setState(() {});
  }

  void _removeProfile(int index) {
    _profiles.removeAt(index);
    _saveProfiles();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
        title: const Text('Manage Tracked Folders'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Settings Card
                Card(
                  margin: const EdgeInsets.all(12),
                  color: Colors.grey[900],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Power Saving Mode', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        subtitle: const Text('Only run backup when charging and battery is not low', style: TextStyle(color: Colors.white70, fontSize: 11)),
                        value: _powerSaving,
                        onChanged: (v) async {
                          setState(() {
                            _powerSaving = v;
                          });
                          await ref.read(settingsRepositoryProvider).setSetting('auto_backup_power_saving', v ? 'true' : 'false');
                          await _updateWorkmanagerConstraints();
                        },
                      ),
                      if (Platform.isAndroid) ...[
                        const Divider(height: 1, color: Colors.white10),
                        ListTile(
                          title: const Text('Background Execution', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                          subtitle: Text(
                            _isBatteryOptimizationsIgnored
                                ? 'Unrestricted (Best backup performance)'
                                : 'Restricted by system battery saver. Tap to allow unrestricted background backup.',
                            style: TextStyle(
                              color: _isBatteryOptimizationsIgnored ? Colors.green : Colors.amber,
                              fontSize: 11,
                            ),
                          ),
                          trailing: Icon(
                            _isBatteryOptimizationsIgnored ? Icons.check_circle : Icons.warning_amber_rounded,
                            color: _isBatteryOptimizationsIgnored ? Colors.green : Colors.amber,
                          ),
                          onTap: _requestIgnoreBatteryOptimizations,
                        ),
                      ],
                    ],
                  ),
                ),
                
                // Tracked folders header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Tracked Folders', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white)),
                      Text('${_profiles.length} folder${_profiles.length == 1 ? "" : "s"}', style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
                
                // Folder list / empty state
                Expanded(
                  child: _profiles.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.folder_off_outlined, size: 64, color: Colors.grey.shade600),
                              const SizedBox(height: 16),
                              Text('No folders tracked', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
                              const SizedBox(height: 8),
                              const Text('Add a folder to start auto-backing up your files.', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _profiles.length,
                          itemBuilder: (context, index) {
                            final profile = _profiles[index];
                            final path = profile['path'] as String? ?? 'Unknown Path';
                            final types = <String>[];
                            if (profile['include_images'] == true) types.add('Images');
                            if (profile['include_videos'] == true) types.add('Videos');
                            if (profile['include_documents'] == true) types.add('Docs');
                            if (profile['include_all'] == true) types.add('All Files');

                            final dest = profile['destinationFolderName'] ?? 'My Drive (Root)';
                            final mode = profile['backupMode'] == 'drive_to_local'
                                ? 'Download Only'
                                : profile['backupMode'] == 'both'
                                    ? 'Sync'
                                    : 'Upload Only';
                            final del = profile['deleteBehavior'] == 'sync_deletions'
                                ? 'Delete on Dest'
                                : 'Keep on Dest';
                            final net = profile['wifiOnly'] == true ? 'Wi-Fi' : 'Any Net';

                            return ListTile(
                              leading: const Icon(Icons.folder, color: Colors.blueAccent),
                              title: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                              subtitle: Text(
                                'To: $dest • $mode ($del) • $net\nTypes: ${types.join(', ')} • Quality: ${profile['quality']}',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              isThreeLine: true,
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                onPressed: () => _removeProfile(index),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final newProfile = await showDialog<Map<String, dynamic>>(
            context: context,
            builder: (context) => const AddBackupProfileDialog(),
          );
          if (newProfile != null) {
            _profiles.add(newProfile);
            _saveProfiles();
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Folder'),
      ),
    );
}

class AddBackupProfileDialog extends ConsumerStatefulWidget {
  const AddBackupProfileDialog({super.key});

  @override
  ConsumerState<AddBackupProfileDialog> createState() => _AddBackupProfileDialogState();
}

class _AddBackupProfileDialogState extends ConsumerState<AddBackupProfileDialog> {
  String? _selectedPath;
  String? _destinationFolderId;
  String _destinationFolderName = 'My Drive (Root)';
  bool _incImages = true;
  bool _incVideos = false;
  bool _incDocs = false;
  bool _incAll = false;
  String _quality = 'High';
  String _backupMode = 'local_to_drive';
  String _deleteBehavior = 'dont_delete';
  bool _wifiOnly = true;

  Future<void> _pickFolder() async {
    if (Platform.isAndroid) {
      final status = await Permission.manageExternalStorage.request();
      if (status.isDenied || status.isPermanentlyDenied) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: Colors.grey[900],
              title: const Text('Storage Permission Required', style: TextStyle(color: Colors.white)),
              content: const Text(
                'AeroDrive needs "Manage All Files" access to read and sync backup folders from your device.\n\n'
                'Please grant this permission in your device settings to enable automatic backup.',
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    const MethodChannel('com.aerodrive.aerodrive/settings')
                        .invokeMethod('openManageAllFilesSettings');
                  },
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );
        }
        return;
      }
    }

    try {
      final String? result = await getDirectoryPath();
      if (result != null) {
        setState(() {
          _selectedPath = result;
        });
      }
    } catch (e) {
      if (mounted) {
        _showFolderSelectionError(context, e);
      }
    }
  }

  void _showFolderSelectionError(BuildContext context, dynamic error) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Folder Selection Error'),
        content: Text(
          'Selecting folders in certain directories (like Downloads or Android/data) is not supported by Android\'s storage system.\n\n'
          'Please select a folder from another storage location (e.g. Device storage root or Documents).\n\n'
          'Error details: $error',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDestinationFolder() async {
    final String? result = await showDialog<String?>(
      context: context,
      builder: (context) => const FolderPickerDialog(
        title: 'Select Destination Folder',
      ),
    );
    if (result != null) {
      if (result == '__root__') {
        setState(() {
          _destinationFolderId = null;
          _destinationFolderName = 'My Drive (Root)';
        });
      } else {
        final db = ref.read(databaseProvider);
        final folder = await (db.select(db.folders)..where((f) => f.id.equals(result))).getSingleOrNull();
        if (folder != null) {
          setState(() {
            _destinationFolderId = folder.id;
            _destinationFolderName = folder.name;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
      title: const Text('New Backup Profile'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Local Folder to Track', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedPath ?? 'No folder selected',
                    style: TextStyle(color: _selectedPath == null ? Colors.grey : null),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.folder_open),
                  onPressed: _pickFolder,
                  tooltip: 'Browse Local',
                ),
              ],
            ),
            const Divider(height: 24),

            const Text('Drive Destination Folder', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _destinationFolderName,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.cloud_upload_outlined),
                  onPressed: _pickDestinationFolder,
                  tooltip: 'Choose Drive Folder',
                ),
              ],
            ),
            const Divider(height: 24),

            const Text('Sync Mode', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _backupMode,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              items: const [
                DropdownMenuItem(value: 'local_to_drive', child: Text('Local to Drive (Upload only)')),
                DropdownMenuItem(value: 'drive_to_local', child: Text('Drive to Local (Download only)')),
                DropdownMenuItem(value: 'both', child: Text('Bidirectional Sync (Both directions)')),
              ],
              onChanged: (v) => setState(() => _backupMode = v!),
            ),
            const SizedBox(height: 16),

            const Text('Deletions Policy', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _deleteBehavior,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              items: const [
                DropdownMenuItem(value: 'dont_delete', child: Text('Keep files on destination (DCIM-style)')),
                DropdownMenuItem(value: 'sync_deletions', child: Text('Delete files on destination')),
              ],
              onChanged: (v) => setState(() => _deleteBehavior = v!),
            ),
            const SizedBox(height: 16),

            SwitchListTile(
              title: const Text('Back up on Wi-Fi only', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: const Text('Prevents using mobile data for sync', style: TextStyle(fontSize: 11)),
              value: _wifiOnly,
              onChanged: (v) => setState(() => _wifiOnly = v),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            const Divider(height: 24),

            const Text('File Types to Backup', style: TextStyle(fontWeight: FontWeight.bold)),
            CheckboxListTile(
              title: const Text('Images (JPG, PNG, etc.)'),
              value: _incImages,
              onChanged: _incAll ? null : (v) => setState(() => _incImages = v!),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              title: const Text('Videos (MP4, MKV, etc.)'),
              value: _incVideos,
              onChanged: _incAll ? null : (v) => setState(() => _incVideos = v!),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              title: const Text('Documents (PDF, DOCX, etc.)'),
              value: _incDocs,
              onChanged: _incAll ? null : (v) => setState(() => _incDocs = v!),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              title: const Text('All Files'),
              value: _incAll,
              onChanged: (v) {
                setState(() {
                  _incAll = v!;
                  if (_incAll) {
                    _incImages = true;
                    _incVideos = true;
                    _incDocs = true;
                  }
                });
              },
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const Divider(height: 24),
            const Text('Upload Quality', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _quality,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              items: const [
                DropdownMenuItem(value: 'Original', child: Text('Original')),
                DropdownMenuItem(value: 'High', child: Text('High')),
                DropdownMenuItem(value: 'Medium', child: Text('Medium')),
              ],
              onChanged: (v) => setState(() => _quality = v!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _selectedPath == null
              ? null
              : () {
                  Navigator.pop(context, {
                    'id': DateTime.now().millisecondsSinceEpoch.toString(),
                    'path': _selectedPath,
                    'include_images': _incImages,
                    'include_videos': _incVideos,
                    'include_documents': _incDocs,
                    'include_all': _incAll,
                    'quality': _quality,
                    'destinationFolderId': _destinationFolderId,
                    'destinationFolderName': _destinationFolderName,
                    'backupMode': _backupMode,
                    'deleteBehavior': _deleteBehavior,
                    'wifiOnly': _wifiOnly,
                  });
                },
          child: const Text('Save Profile'),
        ),
      ],
    );
}
