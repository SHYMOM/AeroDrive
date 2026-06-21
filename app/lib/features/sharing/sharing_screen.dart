import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Sharing screen — share link management.
///
/// Placeholder for Phase 8.
class SharingScreen extends StatelessWidget {
  const SharingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Shared Links')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.share_outlined, size: 64,
                color: AppColors.tertiary.withValues(alpha: 0.5)),
            const SizedBox(height: 24),
            Text('Shared Links', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Coming in Phase 8',
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
