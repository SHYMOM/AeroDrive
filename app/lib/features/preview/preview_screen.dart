import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Preview screen — file preview for PDF/audio/video/code/archive.
///
/// Placeholder for Phase 6.
class PreviewScreen extends StatelessWidget {
  const PreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Preview')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.preview_outlined, size: 64,
                color: AppColors.secondary.withValues(alpha: 0.5)),
            const SizedBox(height: 24),
            Text('File Preview', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Coming in Phase 6',
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
