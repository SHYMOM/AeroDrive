import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/importer/takeout_importer_service.dart';

class TakeoutImporterDialog extends ConsumerStatefulWidget {
  const TakeoutImporterDialog({super.key, this.targetFolderId});

  final String? targetFolderId;

  @override
  ConsumerState<TakeoutImporterDialog> createState() => _TakeoutImporterDialogState();
}

class _TakeoutImporterDialogState extends ConsumerState<TakeoutImporterDialog> {
  String? _selectedPath;
  TakeoutImportSummary? _summary;
  bool _isAnalyzing = false;
  bool _isImporting = false;
  double _importProgress = 0.0;
  String _statusText = '';

  Future<void> _pickFolder() async {
    try {
      final dirPath = await FilePicker.getDirectoryPath();
      if (dirPath == null) return;

      setState(() {
        _selectedPath = dirPath;
        _isAnalyzing = true;
        _summary = null;
      });

      final service = ref.read(takeoutImporterServiceProvider);
      final summary = await service.analyzeDirectory(dirPath);

      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          _summary = summary;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAnalyzing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to read folder: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _startImport() {
    if (_selectedPath == null) return;

    setState(() {
      _isImporting = true;
      _importProgress = 0.0;
      _statusText = 'Starting import...';
    });

    final service = ref.read(takeoutImporterServiceProvider);
    service.importTakeoutDirectory(
      _selectedPath!,
      targetParentFolderId: widget.targetFolderId,
      onStatus: (msg) {
        if (mounted) {
          setState(() => _statusText = msg);
        }
      },
    ).listen(
      (progress) {
        if (mounted) {
          setState(() => _importProgress = progress);
        }
      },
      onDone: () {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Google Takeout import queued (${_summary?.totalMediaFiles ?? 0} files)!'),
              backgroundColor: AppColors.primary,
            ),
          );
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() => _isImporting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Import failed: $e'), backgroundColor: AppColors.error),
          );
        }
      },
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.cloud_download_rounded, color: Colors.amber, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Google Takeout Importer',
                        style: TextStyle(
                          color: AppColors.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                      Text(
                        'Migrate Google Photos with original dates & GPS',
                        style: TextStyle(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_selectedPath == null && !_isAnalyzing)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: OutlinedButton.icon(
                    onPressed: _pickFolder,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: const Text('Select Google Takeout Folder'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
            if (_isAnalyzing)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Analyzing Takeout metadata & sidecars...',
                        style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            if (_summary != null && !_isAnalyzing && !_isImporting) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.outline),
                ),
                child: Column(
                  children: [
                    _buildStatRow(Icons.photo_library_rounded, 'Media Files Found', '${_summary!.totalMediaFiles}'),
                    const Divider(height: 16),
                    _buildStatRow(Icons.data_object_rounded, 'Metadata Sidecars Matched', '${_summary!.sidecarsMatched}'),
                    const Divider(height: 16),
                    _buildStatRow(Icons.folder_rounded, 'Albums / Folders', '${_summary!.foldersCreated}'),
                    const Divider(height: 16),
                    _buildStatRow(Icons.storage_rounded, 'Total Size', _formatBytes(_summary!.totalBytes)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: _pickFolder,
                    child: const Text('Change Folder'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _summary!.totalMediaFiles > 0 ? _startImport : null,
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                    child: const Text('Import to AeroDrive'),
                  ),
                ],
              ),
            ],
            if (_isImporting) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: _importProgress,
                backgroundColor: AppColors.outline,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _statusText,
                      style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${(_importProgress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ],
            if (!_isImporting)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Close', style: TextStyle(color: AppColors.onSurfaceVariant)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13),
          ),
        ),
        Text(
          value,
          style: TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ],
    );
  }
}
