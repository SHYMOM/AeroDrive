import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/core/theme/app_colors.dart';

enum TransferFilter { all, active, completed, failed }

class TransfersScreen extends ConsumerStatefulWidget {
  const TransfersScreen({super.key});

  @override
  ConsumerState<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends ConsumerState<TransfersScreen> {
  TransferFilter _currentFilter = TransferFilter.all;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfers'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                _buildFilterChip(TransferFilter.all, 'All'),
                const SizedBox(width: 8),
                _buildFilterChip(TransferFilter.active, 'Active'),
                const SizedBox(width: 8),
                _buildFilterChip(TransferFilter.completed, 'Completed'),
                const SizedBox(width: 8),
                _buildFilterChip(TransferFilter.failed, 'Failed'),
              ],
            ),
          ),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.swap_vert_circle_outlined,
              size: 64,
              color: AppColors.secondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'No transfers',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Uploads and downloads will appear here',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(TransferFilter filter, String label) {
    return FilterChip(
      label: Text(label),
      selected: _currentFilter == filter,
      onSelected: (bool selected) {
        if (selected) {
          setState(() {
            _currentFilter = filter;
          });
        }
      },
    );
  }
}
