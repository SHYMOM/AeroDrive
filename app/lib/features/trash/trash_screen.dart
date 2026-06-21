import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Trash screen — shows soft-deleted files with 30-day auto-purge.
///
/// Placeholder for Phase 5.
class TrashScreen extends StatelessWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash'),
        actions: [
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.delete_forever_outlined, size: 18),
            label: const Text('Empty Trash'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
            ),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.delete_outline,
              size: 64,
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 24),
            Text(
              'Trash is empty',
              style: theme.textTheme.titleLarge?.copyWith(
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Deleted files are kept for 30 days\nbefore permanent removal',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
