import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/drive_providers.dart';
import '../providers/storage_provider.dart';

class StorageWidget extends ConsumerWidget {
  const StorageWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final totalStorageAsync = ref.watch(totalStorageProvider);
    final breakdownAsync = ref.watch(storageBreakdownProvider);

    // Prefer totalStorageProvider (supports test overrides), fallback to breakdown.totalBytes
    final totalBytes = totalStorageAsync.valueOrNull ?? breakdownAsync.valueOrNull?.totalBytes ?? 0;
    final activeCategories = breakdownAsync.valueOrNull?.activeCategories ?? [];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surfaceContainer : colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 340;

              final infinityLogo = Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      colorScheme.primary.withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                    radius: 0.8,
                  ),
                ),
                child: Icon(
                  Icons.all_inclusive,
                  color: colorScheme.primary,
                  size: 40,
                ),
              );

              final textColumn = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Storage',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Unlimited',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Used ${formatStorageBytes(totalBytes)}',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              );

              final upgradeButton = OutlinedButton.icon(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  foregroundColor: colorScheme.primary,
                  side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.diamond_outlined, size: 16),
                label: const Text('Upgrade Plan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        infinityLogo,
                        const SizedBox(width: 12),
                        Expanded(child: textColumn),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: upgradeButton,
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  infinityLogo,
                  const SizedBox(width: 16),
                  Expanded(child: textColumn),
                  const SizedBox(width: 16),
                  upgradeButton,
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          // Multi-segmented Progress Bar
          _buildSegmentedProgressBar(
            totalBytes: totalBytes,
            activeCategories: activeCategories,
            colorScheme: colorScheme,
          ),
          if (activeCategories.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildCategoryBadges(
              categories: activeCategories,
              colorScheme: colorScheme,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSegmentedProgressBar({
    required int totalBytes,
    required List<StorageCategoryItem> activeCategories,
    required ColorScheme colorScheme,
  }) {
    const barHeight = 6.0;
    final trackColor = colorScheme.surfaceContainerHighest;

    if (totalBytes <= 0) {
      return Container(
        height: barHeight,
        width: double.infinity,
        decoration: BoxDecoration(
          color: trackColor,
          borderRadius: BorderRadius.circular(3),
        ),
      );
    }

    if (activeCategories.isEmpty) {
      // Direct total storage without breakdown (e.g. test override)
      return Container(
        height: barHeight,
        width: double.infinity,
        decoration: BoxDecoration(
          color: colorScheme.primary,
          borderRadius: BorderRadius.circular(3),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Container(
        height: barHeight,
        width: double.infinity,
        color: trackColor,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: activeCategories.map((cat) {
            final flex = (cat.fractionOf(totalBytes) * 1000).round();
            if (flex <= 0) return const SizedBox.shrink();
            return Expanded(
              flex: flex,
              child: Container(color: cat.color),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildCategoryBadges({
    required List<StorageCategoryItem> categories,
    required ColorScheme colorScheme,
  }) =>
      Wrap(
        spacing: 12,
        runSpacing: 6,
        children: categories
            .map(
              (cat) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: cat.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${cat.label} ${formatStorageBytes(cat.bytes)}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      );
}
