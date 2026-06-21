import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Auth screen — Telegram phone+OTP login flow.
///
/// Placeholder for Phase 1.
class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 64,
                color: AppColors.primary.withValues(alpha: 0.6)),
            const SizedBox(height: 24),
            Text('Authentication', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('Telegram login coming in Phase 1',
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
