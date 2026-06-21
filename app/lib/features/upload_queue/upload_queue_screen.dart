import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Upload queue screen — shows pending/active/completed uploads.
///
/// Placeholder for Phase 4.
class UploadQueueScreen extends StatelessWidget {
  const UploadQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Upload Queue')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.upload_file_outlined,
              size: 64,
              color: AppColors.secondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'No uploads in progress',
              style: theme.textTheme.titleLarge?.copyWith(
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Files you upload will appear here',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
