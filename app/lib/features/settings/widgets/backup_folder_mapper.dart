import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/repository_providers.dart';

class BackupFolderMapper extends ConsumerStatefulWidget {
  const BackupFolderMapper({super.key});

  @override
  ConsumerState<BackupFolderMapper> createState() => _BackupFolderMapperState();
}

class _BackupFolderMapperState extends ConsumerState<BackupFolderMapper> {
  final _controller = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPath();
  }

  Future<void> _loadPath() async {
    final settings = ref.read(settingsRepositoryProvider);
    final path = await settings.getSetting('dropbox_backup_path') ?? '/AeroDrive';
    if (mounted) {
      setState(() {
        _controller.text = path;
        _isLoading = false;
      });
    }
  }

  Future<void> _savePath(String path) async {
    String finalPath = path.trim();
    if (finalPath.isEmpty) finalPath = '/';
    if (!finalPath.startsWith('/')) finalPath = '/$finalPath';
    if (finalPath.endsWith('/') && finalPath.length > 1) {
      finalPath = finalPath.substring(0, finalPath.length - 1);
    }

    final settings = ref.read(settingsRepositoryProvider);
    await settings.setSetting('dropbox_backup_path', finalPath);
    
    if (mounted) {
      setState(() => _controller.text = finalPath);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup destination updated!'), backgroundColor: Colors.green),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Destination Folder', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        const Text(
          'Set the folder path in your Dropbox where database backups will be stored.', 
          style: TextStyle(color: Colors.white70, fontSize: 13)
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.folder_open),
                  hintText: '/AeroDrive',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: _savePath,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _savePath(_controller.text),
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }
}
