import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';

final aggregateTransferProgressProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.transferQueue).watch().map((queues) {
    var activeUploads = 0;
    var activeDownloads = 0;
    var activeEncrypting = 0;
    var totalBytes = 0;
    var transferredBytes = 0;

    for (final q in queues) {
      if (q.status == 'PENDING' || q.status == 'PROCESSING' || q.status == 'ENCRYPTING') {
        if (q.status == 'ENCRYPTING') activeEncrypting++;
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
      'encrypting': activeEncrypting,
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
        final encCount = (data['encrypting'] as int?) ?? 0;

        var label = 'Transferring...';
        if (encCount > 0 && upCount == encCount && downCount == 0) {
          label = encCount == 1 ? 'Preparing & encrypting file...' : 'Preparing & encrypting $encCount files...';
        } else if (upCount > 0 && downCount > 0) {
          final prepPrefix = encCount > 0 ? '($encCount preparing) ' : '';
          label = '${prepPrefix}Uploading $upCount, Downloading $downCount items...';
        } else if (upCount > 0) {
          final prepPrefix = encCount > 0 ? '($encCount preparing) ' : '';
          label = '${prepPrefix}Uploading $upCount items...';
        } else if (downCount > 0) {
          label = 'Downloading $downCount items...';
        }

        final isIndeterminate = encCount > 0 && progress == 0.0;
        final isEncryptingOnly = encCount > 0 && upCount == encCount && downCount == 0;
        final barColor = isEncryptingOnly ? Colors.amber : AppColors.primary;

        return GestureDetector(
          onTap: () => context.go('/transfers'),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(
                top: BorderSide(color: AppColors.outlineVariant),
              ),
              boxShadow: [
                BoxShadow(
                  color: (isEncryptingOnly ? Colors.amber : AppColors.primary).withValues(alpha: 0.1),
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
                      if (isEncryptingOnly)
                        const Icon(Icons.enhanced_encryption_outlined, size: 16, color: Colors.amber)
                      else ...[
                        if (upCount > 0) Icon(Icons.upload, size: 16, color: AppColors.primary),
                        if (upCount > 0 && downCount > 0) const SizedBox(width: 4),
                        if (downCount > 0) Icon(Icons.download, size: 16, color: AppColors.secondary),
                      ],
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            color: AppColors.onSurface,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        isIndeterminate ? 'Preparing...' : '${(progress * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: isIndeterminate ? Colors.amber : AppColors.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: isIndeterminate ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right, size: 16, color: AppColors.onSurfaceVariant),
                    ],
                  ),
                ),
                LinearProgressIndicator(
                  value: isIndeterminate ? null : progress,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(barColor),
                  minHeight: 3,
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
