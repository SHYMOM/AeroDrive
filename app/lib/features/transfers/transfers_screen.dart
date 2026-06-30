import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:aerodrive/core/theme/app_colors.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:go_router/go_router.dart';

enum TransferFilter { all, active, completed, failed }

class TransferItem {
  final TransferQueueData transfer;
  final FileData? file;
  TransferItem({required this.transfer, this.file});
}

// Stream provider to watch database transfers live
final transfersStreamProvider = StreamProvider<List<TransferItem>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.transferQueue).join([
    drift.leftOuterJoin(db.files, db.files.id.equalsExp(db.transferQueue.fileId)),
  ])..orderBy([drift.OrderingTerm.desc(db.transferQueue.createdAt)])).watch().map((rows) {
    return rows.map((row) {
      return TransferItem(
        transfer: row.readTable(db.transferQueue),
        file: row.readTableOrNull(db.files),
      );
    }).toList();
  });
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
    var i = (log(bytes) / log(1024)).floor();
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
        title: const Text('Clear History', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to clear all completed and failed transfer records from history?',
          style: TextStyle(color: AppColors.onSurface),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
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
        title: const Text('Transfers', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/drive'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, color: AppColors.onSurfaceVariant),
            tooltip: 'Clear History',
            onPressed: () => _clearHistory(context),
          ),
        ],
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
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.0, -0.3),
            radius: 1.8,
            colors: [
              const Color(0xFF7C3AED).withValues(alpha: 0.15),
              const Color(0xFF00E5FF).withValues(alpha: 0.05),
              AppColors.background,
              AppColors.background,
            ],
          ),
        ),
        child: transfersAsync.when(
          data: (list) {
            // Filter items
            final filtered = list.where((item) {
              final status = item.transfer.status;
              switch (_currentFilter) {
                case TransferFilter.active:
                  return status == 'PENDING' || status == 'PROCESSING';
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
                    padding: const EdgeInsets.all(16.0),
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
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isUpload ? 'Upload' : 'Download',
                                    style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildStatusBadge(status),
                            if (status == 'PENDING' || status == 'PROCESSING' || status == 'FAILED') ...[
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => _cancelTransfer(item.transfer.id),
                              ),
                            ],
                          ],
                        ),
                        if (status == 'PROCESSING') ...[
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: Colors.white10,
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
                                style: const TextStyle(fontSize: 11, color: Colors.white54),
                              ),
                              Text(
                                '${(progress * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.bold),
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
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.swap_vert_circle_outlined,
            size: 64,
            color: Colors.white24,
          ),
          const SizedBox(height: 24),
          Text(
            'No transfers found',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white54,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _getFilterEmptyText(),
            style: const TextStyle(
              color: AppColors.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

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
        break;
      case 'PROCESSING':
        color = Colors.blueAccent;
        text = 'ACTIVE';
        break;
      case 'COMPLETED':
        color = Colors.green;
        text = 'SUCCESS';
        break;
      case 'FAILED':
        color = Colors.red;
        text = 'FAILED';
        break;
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
        color: selected ? Colors.white : AppColors.onSurfaceVariant,
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
