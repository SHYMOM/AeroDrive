import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/providers.dart';
import '../core/theme/app_colors.dart';
import '../data/db/database.dart';

class FolderTreeScanResult {
  const FolderTreeScanResult({
    required this.subfolders,
    required this.files,
    required this.fileRelativePaths,
    required this.emptyFolderRelativePaths,
    required this.totalBytes,
  });

  final List<FolderData> subfolders;
  final List<FileData> files;
  final Map<String, String> fileRelativePaths;
  final List<String> emptyFolderRelativePaths;
  final int totalBytes;

  int get totalFiles => files.length;
  int get totalSubfolders => subfolders.length;
}

class FolderTreeHelper {
  /// Recursively scans folder and all subfolders in the database.
  static Future<FolderTreeScanResult> scanFolderTree(AeroDriveDatabase db, FolderData rootFolder) async {
    final allFolders = await (db.select(db.folders)..where((f) => f.deletedAt.isNull())).get();
    final allFiles = await (db.select(db.files)..where((f) => f.deletedAt.isNull())).get();

    final Map<String, List<FolderData>> childrenFolders = {};
    for (final f in allFolders) {
      if (f.parentId != null) {
        childrenFolders.putIfAbsent(f.parentId!, () => []).add(f);
      }
    }

    final Map<String, List<FileData>> folderFiles = {};
    for (final f in allFiles) {
      if (f.folderId != null) {
        folderFiles.putIfAbsent(f.folderId!, () => []).add(f);
      }
    }

    final List<FolderData> collectedSubfolders = [];
    final List<FileData> collectedFiles = [];
    final Map<String, String> fileRelativePaths = {};
    final List<String> emptyFolderRelativePaths = [];
    var totalBytes = 0;

    void traverse(FolderData current, String currentRelPath) {
      final children = childrenFolders[current.id] ?? [];
      final filesInFolder = folderFiles[current.id] ?? [];

      if (children.isEmpty && filesInFolder.isEmpty && current.id != rootFolder.id) {
        emptyFolderRelativePaths.add(currentRelPath);
      }

      for (final f in filesInFolder) {
        final rel = currentRelPath.isEmpty ? f.name : '$currentRelPath/${f.name}';
        collectedFiles.add(f);
        fileRelativePaths[f.id] = rel;
        totalBytes += (f.size ?? 0);
      }

      for (final sub in children) {
        collectedSubfolders.add(sub);
        final subRel = currentRelPath.isEmpty ? sub.name : '$currentRelPath/${sub.name}';
        traverse(sub, subRel);
      }
    }

    traverse(rootFolder, '');

    return FolderTreeScanResult(
      subfolders: collectedSubfolders,
      files: collectedFiles,
      fileRelativePaths: fileRelativePaths,
      emptyFolderRelativePaths: emptyFolderRelativePaths,
      totalBytes: totalBytes,
    );
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  /// Shows the pre-download confirmation dialog and executes the recursive download.
  static Future<void> confirmAndDownloadFolder({
    required BuildContext context,
    required WidgetRef ref,
    required FolderData folder,
  }) async {
    final db = ref.read(databaseProvider);

    // Scan tree
    final scan = await scanFolderTree(db, folder);

    if (!context.mounted) return;

    // Resolve base downloads path for preview
    Directory? baseDir;
    try {
      baseDir = await getDownloadsDirectory();
    } catch (_) {}
    baseDir ??= await getApplicationDocumentsDirectory();
    final destPreview = p.join(baseDir.path, folder.name);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.download_rounded, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Download Folder "${folder.name}"?',
                style: TextStyle(
                  color: AppColors.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.outline.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  _dialogStatRow('Total Files', '${scan.totalFiles} file(s)'),
                  const SizedBox(height: 6),
                  _dialogStatRow('Subfolders', '${scan.totalSubfolders} folder(s)'),
                  const SizedBox(height: 6),
                  _dialogStatRow('Total Size', formatBytes(scan.totalBytes)),
                  const Divider(height: 16),
                  _dialogStatRow('Destination', destPreview, isPath: true),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'AeroDrive will recreate the exact folder and subfolder hierarchy directly inside your local Downloads directory (uncompressed).',
              style: TextStyle(
                color: AppColors.onSurfaceVariant,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text('Download Full Tree'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Create root download dir
    final rootDir = Directory(p.join(baseDir.path, folder.name));
    if (!await rootDir.exists()) {
      await rootDir.create(recursive: true);
    }

    // Recreate all empty subfolder paths on disk
    for (final rel in scan.emptyFolderRelativePaths) {
      final subDir = Directory(p.join(rootDir.path, rel));
      if (!await subDir.exists()) {
        await subDir.create(recursive: true);
      }
    }

    // Queue every file with its nested target path
    const uuid = Uuid();
    for (final file in scan.files) {
      final relPath = scan.fileRelativePaths[file.id] ?? file.name;
      final targetFilePath = p.join(rootDir.path, relPath);

      // Ensure parent directory exists for file
      final fileParentDir = Directory(p.dirname(targetFilePath));
      if (!await fileParentDir.exists()) {
        await fileParentDir.create(recursive: true);
      }

      await db.into(db.transferQueue).insert(
        TransferQueueCompanion.insert(
          id: uuid.v4(),
          type: const drift.Value('DOWNLOAD_FILE'),
          status: const drift.Value('PENDING'),
          priority: const drift.Value(1),
          totalBytes: drift.Value(file.size ?? 0),
          fileId: drift.Value('${file.id}|$targetFilePath'),
          createdAt: drift.Value(DateTime.now()),
        ),
      );
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Started downloading "${folder.name}" (${scan.totalFiles} files across ${scan.totalSubfolders} folders)',
          ),
          backgroundColor: AppColors.primary,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  static Widget _dialogStatRow(String label, String value, {bool isPath = false}) {
    return Row(
      crossAxisAlignment: isPath ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: AppColors.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: isPath ? 'monospace' : null,
            ),
            maxLines: isPath ? 2 : 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
