import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';

class ManageBackupFoldersScreen extends ConsumerStatefulWidget {
  const ManageBackupFoldersScreen({super.key});

  @override
  ConsumerState<ManageBackupFoldersScreen> createState() => _ManageBackupFoldersScreenState();
}

class _ManageBackupFoldersScreenState extends ConsumerState<ManageBackupFoldersScreen> {
  List<Map<String, dynamic>> _profiles = [];
  bool _isLoading = true;

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
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveProfiles() async {
    await ref.read(settingsRepositoryProvider).setSetting('tracked_backup_folders', jsonEncode(_profiles));
    if (mounted) setState(() {});
  }

  void _removeProfile(int index) {
    _profiles.removeAt(index);
    _saveProfiles();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Tracked Folders'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _profiles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_off_outlined, size: 64, color: Colors.grey.shade600),
                      const SizedBox(height: 16),
                      Text('No folders tracked', style: Theme.of(context).textTheme.titleLarge),
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

                    return ListTile(
                      leading: const Icon(Icons.folder, color: Colors.blueAccent),
                      title: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('Types: ${types.join(', ')} • Quality: ${profile['quality']}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () => _removeProfile(index),
                      ),
                    );
                  },
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
}

class AddBackupProfileDialog extends StatefulWidget {
  const AddBackupProfileDialog({super.key});

  @override
  State<AddBackupProfileDialog> createState() => _AddBackupProfileDialogState();
}

class _AddBackupProfileDialogState extends State<AddBackupProfileDialog> {
  String? _selectedPath;
  bool _incImages = true;
  bool _incVideos = false;
  bool _incDocs = false;
  bool _incAll = false;
  String _quality = 'High';

  Future<void> _pickFolder() async {
    String? result = await getDirectoryPath();
    if (result != null) {
      setState(() {
        _selectedPath = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Backup Profile'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Folder to Track', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  tooltip: 'Browse',
                ),
              ],
            ),
            const Divider(height: 32),
            const Text('File Types to Backup', style: TextStyle(fontWeight: FontWeight.bold)),
            CheckboxListTile(
              title: const Text('Images (JPG, PNG, etc.)'),
              value: _incImages,
              onChanged: _incAll ? null : (v) => setState(() => _incImages = v!),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              title: const Text('Videos (MP4, MKV, etc.)'),
              value: _incVideos,
              onChanged: _incAll ? null : (v) => setState(() => _incVideos = v!),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              title: const Text('Documents (PDF, DOCX, etc.)'),
              value: _incDocs,
              onChanged: _incAll ? null : (v) => setState(() => _incDocs = v!),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
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
            ),
            const Divider(height: 32),
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
                  });
                },
          child: const Text('Save Profile'),
        ),
      ],
    );
  }
}
