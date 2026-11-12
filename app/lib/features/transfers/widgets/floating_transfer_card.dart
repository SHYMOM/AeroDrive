import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import 'global_progress_bar.dart';

class FloatingTransferCard extends ConsumerWidget {
  const FloatingTransferCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressState = ref.watch(aggregateTransferProgressProvider);

    return progressState.when(
      data: (data) {
        if (data['hasActive'] != true) return const SizedBox.shrink();

        final progress = (data['progress'] as double).clamp(0.0, 1.0);
        final percent = (progress * 100).toInt();
        final upCount = data['uploads'] as int;
        final downCount = data['downloads'] as int;
        final totalActive = upCount + downCount;

        final label = upCount > 0
            ? 'Uploading $totalActive item${totalActive > 1 ? "s" : ""} ($percent%)'
            : 'Downloading $totalActive item${totalActive > 1 ? "s" : ""} ($percent%)';

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => context.go('/transfers'),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 250,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.outline.withValues(alpha: 0.6),
                  width: 1,
                ),
                boxShadow: AppColors.floatingShadow,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            color: AppColors.onSurface,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress > 0 ? progress : null,
                      minHeight: 5,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

