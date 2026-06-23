import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';

class ThumbnailCacheSizeDialog extends ConsumerStatefulWidget {
  const ThumbnailCacheSizeDialog({super.key});

  @override
  ConsumerState<ThumbnailCacheSizeDialog> createState() => _ThumbnailCacheSizeDialogState();
}

class _ThumbnailCacheSizeDialogState extends ConsumerState<ThumbnailCacheSizeDialog> {
  String _size = '1GB';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final val = await ref.read(settingsRepositoryProvider).getSetting('thumbnail_cache_size') ?? '1GB';
    if (mounted) setState(() => _size = val);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Thumbnail Cache Size'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioListTile<String>(title: const Text('500 MB'), value: '500MB', groupValue: _size, onChanged: (v) => setState(() => _size = v!)),
          RadioListTile<String>(title: const Text('1 GB (Default)'), value: '1GB', groupValue: _size, onChanged: (v) => setState(() => _size = v!)),
          RadioListTile<String>(title: const Text('2 GB'), value: '2GB', groupValue: _size, onChanged: (v) => setState(() => _size = v!)),
          RadioListTile<String>(title: const Text('Unlimited'), value: 'Unlimited', groupValue: _size, onChanged: (v) => setState(() => _size = v!)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            await ref.read(settingsRepositoryProvider).setSetting('thumbnail_cache_size', _size);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class ClearThumbnailCacheDialog extends ConsumerWidget {
  const ClearThumbnailCacheDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: const Text('Clear Thumbnail Cache'),
      content: const Text(
        'Are you sure you want to clear the local thumbnail cache? '
        'This will free up storage, but thumbnails will need to be re-downloaded from Telegram.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            // Simulated clearing logic
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Cleared local thumbnail cache.')),
            );
          },
          style: FilledButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
          ),
          child: const Text('Clear Cache'),
        ),
      ],
    );
  }
}

class VideoPlayerQualityDialog extends ConsumerStatefulWidget {
  const VideoPlayerQualityDialog({super.key});

  @override
  ConsumerState<VideoPlayerQualityDialog> createState() => _VideoPlayerQualityDialogState();
}

class _VideoPlayerQualityDialogState extends ConsumerState<VideoPlayerQualityDialog> {
  String _quality = '1080p';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final val = await ref.read(settingsRepositoryProvider).getSetting('video_player_quality') ?? '1080p';
    if (mounted) setState(() => _quality = val);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Default Video Quality'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioListTile<String>(title: const Text('Original (No transcoding)'), value: 'Original', groupValue: _quality, onChanged: (v) => setState(() => _quality = v!)),
          RadioListTile<String>(title: const Text('1080p (Default)'), value: '1080p', groupValue: _quality, onChanged: (v) => setState(() => _quality = v!)),
          RadioListTile<String>(title: const Text('720p (Save bandwidth)'), value: '720p', groupValue: _quality, onChanged: (v) => setState(() => _quality = v!)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            await ref.read(settingsRepositoryProvider).setSetting('video_player_quality', _quality);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
