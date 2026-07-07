import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/logger.dart';
import '../../core/providers.dart';
import '../../data/db/database.dart';
import '../drive/media_player_screen.dart';
import 'archive_viewer.dart';
import 'file_decryption_util.dart';
import 'image_gallery_screen.dart';
import 'media_gallery_screen.dart';
import 'universal_file_viewer.dart';
import 'video_gallery_screen.dart';

class PreviewDownloadButton extends ConsumerWidget {
  const PreviewDownloadButton({super.key, required this.fileId});
  final String fileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
      icon: const Icon(Icons.download),
      tooltip: 'Download',
      onPressed: () async {
        final db = ref.read(databaseProvider);
        await db.into(db.transferQueue).insert(
          TransferQueueCompanion.insert(
            id: const Uuid().v4(),
            fileId: drift.Value(fileId),
            type: const drift.Value('DOWNLOAD_FILE'),
            status: const drift.Value('PENDING'),
            priority: const drift.Value(1),
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

class PreviewRouter {
  static void openPreview(BuildContext context, FileData file, {List<FileData>? siblings}) {
    final mime = file.mimeType ?? '';
    final ext = file.name.split('.').last.toLowerCase();

    final isImage = mime.startsWith('image/');
    final isVideo = mime.startsWith('video/');

    if (isVideo || isImage) {
      final hasImages = siblings?.any((f) => f.mimeType?.startsWith('image/') == true) ?? isImage;
      final hasVideos = siblings?.any((f) => f.mimeType?.startsWith('video/') == true) ?? isVideo;

      if (hasImages && hasVideos) {
        final mediaSiblings = siblings!.where((f) => f.mimeType?.startsWith('image/') == true || f.mimeType?.startsWith('video/') == true).toList();
        final initialIndex = mediaSiblings.indexWhere((f) => f.id == file.id);
        final startIndex = initialIndex >= 0 ? initialIndex : 0;

        Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
          builder: (_) => MediaGalleryScreen(files: mediaSiblings, initialIndex: startIndex),
        ));
      } else if (hasVideos && !hasImages) {
        final videoSiblings = siblings?.where((f) => f.mimeType?.startsWith('video/') == true).toList() ?? [file];
        final initialIndex = videoSiblings.indexWhere((f) => f.id == file.id);
        final startIndex = initialIndex >= 0 ? initialIndex : 0;

        Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
          builder: (_) => VideoGalleryScreen(files: videoSiblings, initialIndex: startIndex),
        ));
      } else if (hasImages && !hasVideos) {
        final imageSiblings = siblings?.where((f) => f.mimeType?.startsWith('image/') == true).toList() ?? [file];
        final initialIndex = imageSiblings.indexWhere((f) => f.id == file.id);
        final startIndex = initialIndex >= 0 ? initialIndex : 0;

        Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
          builder: (_) => ImageGalleryScreen(files: imageSiblings, initialIndex: startIndex),
        ));
      }
    } else if (mime.startsWith('audio/')) {
      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
        builder: (_) => MediaPlayerScreen(file: file),
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
    } else if (_isPreviewable(mime, ext)) {
      // Open with the universal file viewer
      _openUniversalViewer(context, file);
    } else {
      _openGeneric(context, file);
    }
  }

  /// Determines if a file can be shown in the universal text/code/markup viewer
  static bool _isPreviewable(String mime, String ext) {
    if (mime == 'application/pdf') return true;
    if (mime.startsWith('text/')) return true;
    if (mime == 'application/json' ||
        mime == 'application/xml' ||
        mime == 'application/javascript' ||
        mime.endsWith('+xml') ||
        mime.endsWith('+json')) return true;

    // Code file extensions
    const codeExts = {
      'java', 'py', 'dart', 'js', 'ts', 'c', 'cpp', 'cs', 'go', 'kt',
      'swift', 'rs', 'rb', 'php', 'sh', 'bat', 'json', 'xml', 'yaml',
      'yml', 'toml', 'ini', 'conf', 'gradle', 'cmake', 'makefile',
      'dockerfile', 'properties', 'md', 'markdown', 'html', 'htm',
      'css', 'scss', 'sass', 'less', 'txt', 'log', 'csv',
    };
    return codeExts.contains(ext);
  }

  static void _openUniversalViewer(BuildContext context, FileData file) {
    final mime = file.mimeType ?? '';
    final ext = file.name.split('.').last.toLowerCase();

    // Determine the viewer type label and color for the AppBar
    final String viewerLabel;
    final Color accentColor;

    if (mime == 'application/pdf' || ext == 'pdf') {
      viewerLabel = 'PDF Viewer';
      accentColor = const Color(0xFFE53935);
    } else if (mime == 'text/html' || ext == 'html' || ext == 'htm') {
      viewerLabel = 'HTML Viewer';
      accentColor = const Color(0xFFFF9800);
    } else if (mime == 'text/x-markdown' || ext == 'md' || ext == 'markdown') {
      viewerLabel = 'Markdown Viewer';
      accentColor = const Color(0xFF607D8B);
    } else {
      viewerLabel = 'Code Editor';
      accentColor = const Color(0xFF00B4D8);
    }

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: const Color(0xFF0D1117),
        appBar: AppBar(
          backgroundColor: const Color(0xFF161B22),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                file.name,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                viewerLabel,
                style: TextStyle(color: accentColor, fontSize: 11),
              ),
            ],
          ),
          actions: [
            PreviewDownloadButton(fileId: file.id),
          ],
          iconTheme: const IconThemeData(color: Colors.white70),
        ),
        body: UniversalFileViewer(file: file),
      ),
    ));
  }

  static void _openGeneric(BuildContext context, FileData file) {
    final sizeStr = file.size != null && file.size! > 0
        ? '${(file.size! / 1024 / 1024).toStringAsFixed(1)} MB'
        : 'Unknown size';
    final mimeStr = file.mimeType ?? 'Unknown';

    final icon = fileTypeIcon(file.mimeType, file.name);
    final color = fileTypeColor(file.mimeType, file.name);
    final ext = file.name.split('.').last.toUpperCase();

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: const Color(0xFF0D1117),
        appBar: AppBar(
          backgroundColor: const Color(0xFF161B22),
          title: Text(file.name, style: const TextStyle(color: Colors.white)),
          iconTheme: const IconThemeData(color: Colors.white70),
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
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.15),
                    border: Border.all(color: color.withValues(alpha: 0.4), width: 2),
                    boxShadow: [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 24, spreadRadius: 4)],
                  ),
                  child: Icon(icon, size: 48, color: color),
                ),
                const SizedBox(height: 24),
                Text(
                  file.name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('.$ext', style: TextStyle(color: color, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),
                const SizedBox(height: 8),
                Text('Type: $mimeStr', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                Text('Size: $sizeStr', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () => _downloadAndOpen(context, file),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open with external app'),
                  style: FilledButton.styleFrom(backgroundColor: color),
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
