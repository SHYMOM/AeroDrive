import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Search screen — full-text search over file metadata.
///
/// Placeholder for Phase 5.
class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          decoration: InputDecoration(
            hintText: 'Search files and folders...',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            hintStyle: TextStyle(
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
          style: theme.textTheme.bodyLarge,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list_outlined),
            tooltip: 'Filters',
            onPressed: () {},
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_outlined,
              size: 64,
              color: AppColors.secondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'Search your files',
              style: theme.textTheme.titleLarge?.copyWith(
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Find files by name, type, or content',
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
