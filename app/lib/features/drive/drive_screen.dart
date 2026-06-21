import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Drive screen — main file browser view.
///
/// Placeholder for Phase 5; shows the branded empty-state UI.
class DriveScreen extends StatelessWidget {
  const DriveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Drive'),
        actions: [
          IconButton(
            icon: const Icon(Icons.view_module_outlined),
            tooltip: 'Toggle view',
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.sort_outlined),
            tooltip: 'Sort',
            onPressed: () {},
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.15),
                    AppColors.primary.withValues(alpha: 0.05),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Icon(
                Icons.cloud_upload_rounded,
                size: 56,
                color: AppColors.primary.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Your drive is empty',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Upload files to get started with\nzero-knowledge encrypted storage',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Upload File'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        tooltip: 'Upload',
        child: const Icon(Icons.add),
      ),
    );
  }
}
