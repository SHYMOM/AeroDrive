import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;
import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/core/logger.dart';
import 'package:aerodrive/features/drive/media_player_screen.dart';
import 'package:aerodrive/features/preview/decrypted_image_viewer.dart';
import 'package:aerodrive/features/preview/decrypted_text_viewer.dart';
import 'package:aerodrive/features/preview/archive_viewer.dart';
import 'package:aerodrive/features/preview/file_decryption_util.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:aerodrive/features/preview/image_gallery_screen.dart';
import 'package:aerodrive/features/preview/video_gallery_screen.dart';
import 'dart:io';

class PreviewDownloadButton extends ConsumerWidget {
  final String fileId;
  const PreviewDownloadButton({super.key, required this.fileId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.download),
      tooltip: 'Download',
      onPressed: () async {
        final db = ref.read(databaseProvider);
        await db.into(db.transferQueue).insert(
          TransferQueueCompanion.insert(
            id: const Uuid().v4(),
            fileId: drift.Value(fileId),
            type: drift.Value('DOWNLOAD_FILE'),
            status: drift.Value('PENDING'),
            priority: drift.Value(1),
            createdAt: drift.Value(DateTime.now()),
          ),
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Queued for download...')),
          );
        }
      },
    );
  }
}

class PreviewRouter {
  static void openPreview(BuildContext context, FileData file, {List<FileData>? siblings}) {
    final mime = file.mimeType ?? '';

    if (mime.startsWith('video/')) {
      final videoSiblings = siblings?.where((f) => f.mimeType?.startsWith('video/') == true).toList() ?? [file];
      final initialIndex = videoSiblings.indexWhere((f) => f.id == file.id);
      final startIndex = initialIndex >= 0 ? initialIndex : 0;

      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => VideoGalleryScreen(files: videoSiblings, initialIndex: startIndex),
      ));
    } else if (mime.startsWith('audio/')) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MediaPlayerScreen(file: file),
      ));
    } else if (mime.startsWith('image/')) {
      final imageSiblings = siblings?.where((f) => f.mimeType?.startsWith('image/') == true).toList() ?? [file];
      final initialIndex = imageSiblings.indexWhere((f) => f.id == file.id);
      final startIndex = initialIndex >= 0 ? initialIndex : 0;

      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ImageGalleryScreen(files: imageSiblings, initialIndex: startIndex),
      ));
    } else if (mime == 'application/pdf') {
      _openPdf(context, file);
    } else if (mime.startsWith('text/') ||
        mime == 'application/json' ||
        mime == 'application/xml' ||
        mime == 'application/javascript' ||
        mime.endsWith('+xml') ||
        mime.endsWith('+json')) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(file.name),
            actions: [
              PreviewDownloadButton(fileId: file.id),
            ],
          ),
          body: DecryptedTextViewer(file: file),
        ),
      ));
    } else if (mime.contains('zip') ||
        mime.contains('rar') ||
        mime.contains('tar') ||
        mime.contains('7z') ||
        mime.contains('compress') ||
        mime.contains('archive') ||
        mime == 'application/gzip') {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(file.name),
            actions: [
              PreviewDownloadButton(fileId: file.id),
            ],
          ),
          body: ArchiveViewer(file: file),
        ),
      ));
    } else {
      _openGeneric(context, file);
    }
  }

  static void _openPdf(BuildContext context, FileData file) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open PDF'),
        content: const Text('Download and open this PDF with an external app?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadAndOpen(context, file);
            },
            child: const Text('Download & Open'),
          ),
        ],
      ),
    );
  }

  static void _openGeneric(BuildContext context, FileData file) {
    final sizeStr = file.size != null && file.size! > 0
        ? '${(file.size! / 1024 / 1024).toStringAsFixed(1)} MB'
        : 'Unknown size';
    final mimeStr = file.mimeType ?? 'Unknown';

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(
          title: Text(file.name),
          actions: [
            PreviewDownloadButton(fileId: file.id),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.insert_drive_file_outlined, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(file.name, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text('Type: $mimeStr', style: Theme.of(context).textTheme.bodySmall),
                Text('Size: $sizeStr', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => _downloadAndOpen(context, file),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open with external app'),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
  }

  static Future<void> _downloadAndOpen(BuildContext context, FileData file) async {
    try {
      final dir = await getTemporaryDirectory();
      final localPath = '${dir.path}/${file.name}';
      final localFile = File(localPath);

      if (!await localFile.exists()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Downloading file...')),
        );
      }

      await _saveFile(context, file, localPath);

      final uri = Uri.file(localPath);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open: ${file.name}')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open: $e')),
        );
      }
    }
  }

  static Future<void> _saveFile(BuildContext context, FileData file, String path) async {
    final localFile = File(path);
    if (await localFile.exists()) return;

    try {
      final container = ProviderScope.containerOf(context, listen: false);
      final bytes = await loadDecryptedFile(container, file);
      if (bytes != null) {
        await localFile.writeAsBytes(bytes);
      }
    } catch (e) {
      AppLogger.error('Failed to save file ${file.id}', e);
    }
  }
}
