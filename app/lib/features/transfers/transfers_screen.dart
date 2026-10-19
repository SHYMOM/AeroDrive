import 'dart:math';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/db/database.dart';

enum TransferFilter { all, active, completed, failed }

class TransferItem {
  TransferItem({required this.transfer, this.file});
  final TransferQueueData transfer;
  final FileData? file;
}

// Stream provider to watch database transfers live
final transfersStreamProvider = StreamProvider<List<TransferItem>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.transferQueue).join([
    drift.leftOuterJoin(db.files, db.files.id.equalsExp(db.transferQueue.fileId)),
  ])..orderBy([drift.OrderingTerm.desc(db.transferQueue.createdAt)])).watch().map((rows) => rows.map((row) => TransferItem(
        transfer: row.readTable(db.transferQueue),
        file: row.readTableOrNull(db.files),
      )).toList());
});

class TransfersScreen extends ConsumerStatefulWidget {
  const TransfersScreen({super.key});

  @override
  ConsumerState<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends ConsumerState<TransfersScreen> {
  TransferFilter _currentFilter = TransferFilter.all;

  String _formatSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _getTransferName(TransferItem item) {
    if (item.transfer.type == 'UPLOAD_FILE' && item.transfer.fileId != null) {
      final parts = item.transfer.fileId!.split('|');
      if (parts.isNotEmpty) {
        final path = parts[0];
        return path.split(RegExp(r'[\\/]')).last;
      }
    }
    return item.file?.name ?? item.transfer.fileId ?? 'Unknown File';
  }

  Future<void> _clearHistory(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text('Clear History', style: TextStyle(color: AppColors.onSurface)),
        content: Text(
          'Are you sure you want to clear all completed and failed transfer records from history?',
          style: TextStyle(color: AppColors.onSurface),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final db = ref.read(databaseProvider);
      await (db.delete(db.transferQueue)
        ..where((q) => q.status.equals('COMPLETED') | q.status.equals('FAILED'))
      ).go();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transfer history cleared successfully.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  Future<void> _cancelTransfer(String id) async {
    final db = ref.read(databaseProvider);
    await (db.delete(db.transferQueue)..where((q) => q.id.equals(id))).go();
  }

  @override
  Widget build(BuildContext context) {
    final transfersAsync = ref.watch(transfersStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => context.go('/drive'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_outlined, size: 16, color: AppColors.secondary),
                    const SizedBox(width: 6),
                    Text(
                      'Drive',
                      style: TextStyle(
                        color: AppColors.secondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.outline),
            const SizedBox(width: 4),
            Text(
              'Transfers',
              style: TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          tooltip: 'Back to Drive',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/drive');
            }
          },
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.folder_outlined, size: 16),
            label: const Text('My Drive'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryLight,
            ),
            onPressed: () => context.go('/drive'),
          ),
          IconButton(
            icon: Icon(Icons.delete_sweep_outlined, color: AppColors.onSurfaceVariant),
            tooltip: 'Clear History',
            onPressed: () => _clearHistory(context),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
      body: transfersAsync.when(
          data: (list) {
            // Filter items
            final filtered = list.where((item) {
              final status = item.transfer.status;
              switch (_currentFilter) {
                case TransferFilter.active:
                  return status == 'PENDING' || status == 'PROCESSING' || status == 'ENCRYPTING';
                case TransferFilter.completed:
                  return status == 'COMPLETED';
                case TransferFilter.failed:
                  return status == 'FAILED';
                case TransferFilter.all:
                  return true;
              }
            }).toList();

            if (filtered.isEmpty) {
              return _buildEmptyState();
            }

            return ListView.builder(
              itemCount: filtered.length,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemBuilder: (context, index) {
                final item = filtered[index];
                final name = _getTransferName(item);
                final isUpload = item.transfer.type == 'UPLOAD_FILE';
                final status = item.transfer.status;
                
                final bytesTransferred = item.transfer.bytesTransferred;
                final totalBytes = item.transfer.totalBytes ?? 0;
                final progress = totalBytes > 0 ? (bytesTransferred / totalBytes).clamp(0.0, 1.0) : 0.0;

                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: isUpload 
                                  ? AppColors.primary.withValues(alpha: 0.1) 
                                  : AppColors.secondary.withValues(alpha: 0.1),
                              child: Icon(
                                isUpload ? Icons.cloud_upload : Icons.cloud_download,
                                color: isUpload ? AppColors.primary : AppColors.secondary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.onSurface),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isUpload ? 'Upload' : 'Download',
                                    style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildStatusBadge(status),
                            if (status == 'PENDING' || status == 'PROCESSING' || status == 'ENCRYPTING' || status == 'FAILED') ...[
                              const SizedBox(width: 8),
                              IconButton(
                                icon: Icon(Icons.close, size: 18, color: Colors.grey),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => _cancelTransfer(item.transfer.id),
                              ),
                            ],
                          ],
                        ),
                        if (status == 'PROCESSING' || status == 'ENCRYPTING') ...[
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: AppColors.outlineVariant.withValues(alpha: 0.3),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isUpload ? AppColors.primary : AppColors.secondary
                              ),
                              minHeight: 4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${_formatSize(bytesTransferred)} of ${_formatSize(totalBytes)}',
                                style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant),
                              ),
                              Text(
                                '${(progress * 100).toStringAsFixed(0)}%',
                                style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                        if (status == 'FAILED' && item.transfer.errorMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Error: ${item.transfer.errorMessage}',
                            style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                  ),
                ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.05, end: 0, curve: Curves.easeOut);
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.redAccent))),
        ),
    );
  }

  Widget _buildEmptyState() => Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.swap_vert_circle_outlined,
            size: 64,
            color: AppColors.outline,
          ),
          const SizedBox(height: 24),
          Text(
            'No transfers found',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.onSurfaceVariant,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _getFilterEmptyText(),
            style: TextStyle(
              color: AppColors.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.cloud_outlined, size: 18),
            label: const Text('Return to My Drive'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => context.go('/drive'),
          ),
        ],
      ),
    );

  String _getFilterEmptyText() {
    switch (_currentFilter) {
      case TransferFilter.active:
        return 'No active uploads or downloads';
      case TransferFilter.completed:
        return 'No completed transfers in history';
      case TransferFilter.failed:
        return 'No failed transfers';
      case TransferFilter.all:
        return 'Uploads and downloads will appear here';
    }
  }

  Widget _buildStatusBadge(String? status) {
    Color color;
    String text;
    
    switch (status) {
      case 'PENDING':
        color = Colors.orangeAccent;
        text = 'PENDING';
      case 'ENCRYPTING':
        color = Colors.amber;
        text = 'ENCRYPTING';
      case 'PROCESSING':
        color = Colors.blueAccent;
        text = 'UPLOADING';
      case 'COMPLETED':
        color = Colors.green;
        text = 'SUCCESS';
      case 'FAILED':
        color = Colors.red;
        text = 'FAILED';
      default:
        color = Colors.grey;
        text = 'UNKNOWN';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildFilterChip(TransferFilter filter, String label) {
    final selected = _currentFilter == filter;
    return FilterChip(
      label: Text(label),
      selected: selected,
      selectedColor: AppColors.primary.withValues(alpha: 0.2),
      checkmarkColor: AppColors.primary,
      backgroundColor: AppColors.surfaceElevated.withValues(alpha: 0.1),
      labelStyle: TextStyle(
        color: selected ? AppColors.onSurface : AppColors.onSurfaceVariant,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.outlineVariant,
          width: 0.5,
        ),
      ),
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _currentFilter = filter;
          });
        }
      },
    );
  }
}
