import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/reset_helper.dart';
import '../features/telegram/telegram_service.dart';

class SyncDebugOverlay extends ConsumerStatefulWidget {
  const SyncDebugOverlay({super.key});

  @override
  ConsumerState<SyncDebugOverlay> createState() => _SyncDebugOverlayState();
}

class _SyncDebugOverlayState extends ConsumerState<SyncDebugOverlay> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final telegramService = ref.watch(telegramServiceProvider.notifier);

    return ValueListenableBuilder<TelegramInitDebugInfo>(
      valueListenable: telegramService.debugInfo,
      builder: (context, info, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final hasError = info.lastError != null;
        final statusColor = hasError
            ? AppColors.error
            : (info.pendingRequests.isNotEmpty ? const Color(0xFFF59E0B) : AppColors.primary);

        return Material(
          type: MaterialType.transparency,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.only(top: 14, left: 16, right: 16),
            constraints: BoxConstraints(
              maxWidth: _isExpanded ? 460 : 320,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF151D2A) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hasError
                    ? AppColors.error.withValues(alpha: 0.4)
                    : (isDark ? Colors.white.withValues(alpha: 0.08) : AppColors.outline.withValues(alpha: 0.6)),
                width: 1,
              ),
              boxShadow: AppColors.floatingShadow,
            ),
            child: InkWell(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sleek Pill Header Row
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: statusColor.withValues(alpha: 0.4),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isExpanded
                                ? 'Connection Diagnostics'
                                : 'Sync: ${info.currentStep}',
                            style: TextStyle(
                              color: AppColors.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          _isExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ],
                    ),

                    // Expandable Details
                    if (_isExpanded) ...[
                      const SizedBox(height: 10),
                      const Divider(height: 1),
                      const SizedBox(height: 10),
                      Text(
                        'Current Step: ${info.currentStep}',
                        style: TextStyle(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Last TDLib Event: ${info.lastEvent}',
                        style: TextStyle(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                      if (info.pendingRequests.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Pending Requests: ${info.pendingRequests.join(", ")}',
                          style: const TextStyle(
                            color: Color(0xFFF59E0B),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      if (info.lastError != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Error: ${info.lastError}',
                          style: TextStyle(
                            color: AppColors.error,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => AppResetHelper.showResetConfirmation(context),
                          icon: Icon(Icons.refresh_rounded, color: AppColors.error, size: 14),
                          label: Text(
                            'Reset App',
                            style: TextStyle(
                              color: AppColors.error,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            backgroundColor: AppColors.error.withValues(alpha: 0.08),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
