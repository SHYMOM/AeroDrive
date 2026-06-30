import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/features/preview/file_decryption_util.dart';
import 'package:aerodrive/core/theme/app_colors.dart';

/// Shows the contents of a ZIP archive stored as an encrypted file.
/// Supports browsing entries and extracting individual files.
class ArchiveViewer extends ConsumerStatefulWidget {
  final FileData file;
  const ArchiveViewer({super.key, required this.file});

  @override
  ConsumerState<ArchiveViewer> createState() => _ArchiveViewerState();
}

class _ArchiveViewerState extends ConsumerState<ArchiveViewer> {
  Archive? _archive;
  List<ArchiveFile>? _entries;
  bool _isLoading = true;
  String? _error;
  String _extractStatus = '';

  @override
  void initState() {
    super.initState();
    _loadArchive();
  }

  Future<void> _loadArchive() async {
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      final bytes = await loadDecryptedFile(container, widget.file);
      if (bytes == null || bytes.isEmpty) {
        setState(() { _error = 'Failed to load archive'; _isLoading = false; });
        return;
      }

      final archive = ZipDecoder().decodeBytes(bytes);

      if (mounted) {
        setState(() {
          _archive = archive;
          _entries = archive.files
            ..sort((a, b) {
              // Directories first, then files
              if (a.isFile != b.isFile) return a.isFile ? 1 : -1;
              return a.name.compareTo(b.name);
            });
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _extractFile(ArchiveFile entry) async {
    setState(() => _extractStatus = 'Extracting ${entry.name}...');
    try {
      final tempDir = await getTemporaryDirectory();
      final outDir = Directory('${tempDir.path}/aerodrive_extracted');
      if (!await outDir.exists()) await outDir.create(recursive: true);

      final outFile = File('${outDir.path}/${entry.name}');
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(entry.content);

      if (mounted) {
        setState(() => _extractStatus = 'Extracted to ${outFile.path}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Extracted to ${outFile.path}')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _extractStatus = 'Extraction failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.archive_outlined, size: 48, color: AppColors.error.withValues(alpha: 0.6)),
              const SizedBox(height: 16),
              Text('Failed to open archive', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    if (_archive == null || _entries == null) {
      return const Center(child: Text('No archive data'));
    }

    final fileCount = _entries!.where((e) => e.isFile).length;
    final dirCount = _entries!.where((e) => !e.isFile).length;
    final totalSize = _entries!.fold<int>(0, (s, e) => s + e.size);

    return Column(
      children: [
        // Archive info header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
          ),
          child: Row(
            children: [
              const Icon(Icons.folder_zip, color: AppColors.fileArchive),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_archive!.files.length} entries',
                      style: theme.textTheme.titleSmall),
                    Text('$dirCount directories, $fileCount files — ${_formatSize(totalSize)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),

        if (_extractStatus.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.primary.withValues(alpha: 0.1),
            child: Row(
              children: [
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Expanded(child: Text(_extractStatus, style: const TextStyle(fontSize: 13))),
              ],
            ),
          ),

        // File list
        Expanded(
          child: ListView.builder(
            itemCount: _entries!.length,
            itemBuilder: (context, index) {
              final entry = _entries![index];
              final isDir = !entry.isFile;
              final indent = entry.name.split('/').length - 1;

              return Padding(
                padding: EdgeInsets.only(left: 8.0 * indent),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    isDir ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
                    color: isDir ? AppColors.fileFolder : AppColors.fileDocument,
                    size: 18,
                  ),
                  title: Text(
                    entry.name.split('/').last,
                    style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                  ),
                  subtitle: isDir ? null : Text(
                    _formatSize(entry.size),
                    style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant),
                  ),
                  trailing: isDir ? null : IconButton(
                    icon: const Icon(Icons.download, size: 16),
                    tooltip: 'Extract file',
                    onPressed: () => _extractFile(entry),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
