import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/core/theme/app_colors.dart';
import 'package:aerodrive/features/transfers/transfers_screen.dart';

class TransferProgressBar extends ConsumerWidget {
  const TransferProgressBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfersAsync = ref.watch(transfersStreamProvider);

    return transfersAsync.when(
      data: (items) {
        final active = items.where((i) =>
          (i.transfer.status == 'PROCESSING' || i.transfer.status == 'PENDING') &&
          (i.transfer.type == 'UPLOAD_FILE' || i.transfer.type == 'DOWNLOAD_FILE')
        ).toList();

        final processing = active.where((i) => i.transfer.status == 'PROCESSING').toList();

        if (processing.isEmpty && active.isEmpty) return const SizedBox.shrink();

        final hasProgress = processing.isNotEmpty;
        final totalProgress = hasProgress ? _calculateAggregateProgress(processing) : 0.0;
        final totalUploaded = _sumBytes(processing);
        final pendingCount = active.length - processing.length;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(0),
              child: LinearProgressIndicator(
                value: hasProgress ? totalProgress : null,
                backgroundColor: AppColors.outline.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(_getBarColor(processing)),
                minHeight: 3,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  top: BorderSide(
                    color: AppColors.outline.withValues(alpha: 0.3),
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  _buildIcon(processing.isNotEmpty ? processing : active),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _formatSummary(processing, pendingCount),
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasProgress) ...[
                    Text(
                      _formatBytes(totalUploaded),
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${(totalProgress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildIcon(List<TransferItem> items) {
    final hasUpload = items.any((i) => i.transfer.type == 'UPLOAD_FILE');
    final hasDownload = items.any((i) => i.transfer.type == 'DOWNLOAD_FILE');
    if (hasUpload && hasDownload) {
      return Icon(Icons.sync, size: 14, color: AppColors.onSurfaceVariant.withValues(alpha: 0.7));
    } else if (hasUpload) {
      return Icon(Icons.cloud_upload_outlined, size: 14, color: AppColors.primaryLight);
    } else {
      return Icon(Icons.cloud_download_outlined, size: 14, color: AppColors.secondaryLight);
    }
  }

  Color _getBarColor(List<TransferItem> items) {
    final hasUpload = items.any((i) => i.transfer.type == 'UPLOAD_FILE');
    final hasDownload = items.any((i) => i.transfer.type == 'DOWNLOAD_FILE');
    if (hasUpload && hasDownload) return AppColors.primary;
    if (hasUpload) return AppColors.primaryLight;
    return AppColors.secondaryLight;
  }

  double _calculateAggregateProgress(List<TransferItem> items) {
    if (items.isEmpty) return 0.0;
    double total = 0.0;
    int count = 0;
    for (final item in items) {
      final t = item.transfer.totalBytes ?? 0;
      final b = item.transfer.bytesTransferred;
      if (t > 0) {
        total += (b / t).clamp(0.0, 1.0);
        count++;
      }
    }
    return count > 0 ? total / count : 0.0;
  }

  int _sumBytes(List<TransferItem> items) {
    return items.fold<int>(0, (sum, item) => sum + item.transfer.bytesTransferred);
  }

  String _formatSummary(List<TransferItem> items, int pendingCount) {
    int uploads = 0;
    int downloads = 0;
    for (final item in items) {
      if (item.transfer.type == 'UPLOAD_FILE') uploads++;
      else downloads++;
    }
    final parts = <String>[];
    if (uploads > 0) parts.add('$uploads uploading');
    if (downloads > 0) parts.add('$downloads downloading');
    if (pendingCount > 0) parts.add('$pendingCount queued');
    return parts.join(' · ');
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
