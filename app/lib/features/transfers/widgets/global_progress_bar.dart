import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';

final aggregateTransferProgressProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.transferQueue).watch().map((queues) {
    var activeUploads = 0;
    var activeDownloads = 0;
    var totalBytes = 0;
    var transferredBytes = 0;

    for (final q in queues) {
      if (q.status == 'PENDING' || q.status == 'PROCESSING') {
        if (q.type == 'UPLOAD_FILE') activeUploads++;
        if (q.type == 'DOWNLOAD_FILE') activeDownloads++;
        totalBytes += (q.totalBytes ?? 0);
        transferredBytes += (q.bytesTransferred ?? 0);
      }
    }

    return {
      'hasActive': (activeUploads + activeDownloads) > 0,
      'uploads': activeUploads,
      'downloads': activeDownloads,
      'progress': totalBytes > 0 ? (transferredBytes / totalBytes) : 0.0,
      'transferredBytes': transferredBytes,
      'totalBytes': totalBytes,
    };
  });
});

class GlobalProgressBar extends ConsumerWidget {
  const GlobalProgressBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressState = ref.watch(aggregateTransferProgressProvider);

    return progressState.when(
      data: (data) {
        if (data['hasActive'] != true) return const SizedBox.shrink();

        final progress = data['progress'] as double;
        final upCount = data['uploads'] as int;
        final downCount = data['downloads'] as int;

        var label = 'Transferring...';
        if (upCount > 0 && downCount > 0) {
          label = 'Uploading $upCount, Downloading $downCount items...';
        } else if (upCount > 0) {
          label = 'Uploading $upCount items...';
        } else if (downCount > 0) {
          label = 'Downloading $downCount items...';
        }

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: const Border(
              top: BorderSide(color: AppColors.outlineVariant),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    if (upCount > 0) const Icon(Icons.upload, size: 16, color: AppColors.primary),
                    if (upCount > 0 && downCount > 0) const SizedBox(width: 4),
                    if (downCount > 0) const Icon(Icons.download, size: 16, color: AppColors.secondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: AppColors.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '${(progress * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.transparent,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                minHeight: 3,
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
