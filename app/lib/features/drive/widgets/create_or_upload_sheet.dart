import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/logger.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/folder_scanner.dart';
import '../../../domain/channel_load_balancer.dart';
import '../file_picker_util.dart';
import '../providers/drive_providers.dart';
import 'create_folder_dialog.dart';

Future<void> showCreateOrUploadOptions(
  BuildContext context,
  WidgetRef ref, {
  String? currentFolderId,
}) async {
  final targetFolderId = currentFolderId ?? ref.read(currentFolderIdProvider);

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.6)),
        boxShadow: AppColors.floatingShadow,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outline.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'Create or Upload',
                    style: TextStyle(
                      color: AppColors.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.create_new_folder_rounded, color: AppColors.primary, size: 22),
              ),
              title: Text('New Folder', style: TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.w600)),
              subtitle: Text('Create a directory in current view', style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12)),
              onTap: () async {
                Navigator.pop(ctx);
                await showDialog<void>(
                  context: context,
                  builder: (_) => const CreateFolderDialog(),
                );
              },
            ),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.upload_file_rounded, color: AppColors.secondary, size: 22),
              ),
              title: Text('Upload Files', style: TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.w600)),
              subtitle: Text('Upload photos, videos, or documents', style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12)),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  final paths = await pickFilesForUpload(allowMultiple: true);
                  if (paths.isNotEmpty) {
                    final scanner = ref.read(folderScannerProvider);
                    for (final path in paths) {
                      await scanner.scanAndQueueDirectory(path, targetFolderId);
                    }
                    ref.invalidate(folderContentsProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${paths.length} file${paths.length > 1 ? "s" : ""} queued for upload.'),
                          backgroundColor: AppColors.primary,
                        ),
                      );
                    }
                  }
                } catch (e, s) {
                  AppLogger.error('Failed to select files for upload', e, s);
                }
              },
            ),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.drive_folder_upload_rounded, color: Color(0xFFF59E0B), size: 22),
              ),
              title: Text('Upload Folder', style: TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.w600)),
              subtitle: Text('Recursively upload an entire folder', style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12)),
              onTap: () async {
                Navigator.pop(ctx);
                if (Platform.isAndroid) {
                  final status = await Permission.manageExternalStorage.request();
                  if (status.isDenied || status.isPermanentlyDenied) return;
                }
                try {
                  final dirPath = await FilePicker.getDirectoryPath();
                  if (dirPath != null && dirPath.isNotEmpty) {
                    final scanner = ref.read(folderScannerProvider);
                    await scanner.scanAndQueueDirectory(dirPath, targetFolderId);
                    ref.invalidate(folderContentsProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Folder queued for recursive upload.'),
                          backgroundColor: AppColors.primary,
                        ),
                      );
                    }
                  }
                } catch (e, s) {
                  AppLogger.error('Failed to select folder for upload', e, s);
                }
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
  );
}
