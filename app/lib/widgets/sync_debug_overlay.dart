import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/telegram/telegram_service.dart';
import '../core/theme/app_colors.dart';

import '../core/utils/reset_helper.dart';

class SyncDebugOverlay extends ConsumerWidget {
  const SyncDebugOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final telegramService = ref.watch(telegramServiceProvider.notifier);
    
    return ValueListenableBuilder<TelegramInitDebugInfo>(
      valueListenable: telegramService.debugInfo,
      builder: (context, info, child) {
        return Material(
          type: MaterialType.transparency,
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ]
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: info.lastError != null ? Colors.red : AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'AeroDrive Connection Diagnostics',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => AppResetHelper.showResetConfirmation(context),
                      icon: const Icon(Icons.refresh_rounded, color: Colors.redAccent, size: 14),
                      label: const Text(
                        'Reset App',
                        style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Current Step: ${info.currentStep}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Text(
                  'Last TDLib Event: ${info.lastEvent}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                if (info.pendingRequests.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Pending TDLib Requests: ${info.pendingRequests.join(", ")}',
                    style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ],
                if (info.lastError != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Last Error: ${info.lastError}',
                    style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
