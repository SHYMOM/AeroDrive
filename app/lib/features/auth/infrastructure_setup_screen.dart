import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../widgets/aerodrive_logo.dart';
import 'auth_provider.dart';

class InfrastructureSetupScreen extends ConsumerStatefulWidget {
  const InfrastructureSetupScreen({super.key});

  @override
  ConsumerState<InfrastructureSetupScreen> createState() => _InfrastructureSetupScreenState();
}

class _InfrastructureSetupScreenState extends ConsumerState<InfrastructureSetupScreen> {
  double _progress = 0.05;
  late Timer _progressTimer;

  final List<String> _steps = [
    'Initializing Telegram encryption protocols...',
    'Provisioning storage channel 1 of 3 (AeroDrive Storage 1)...',
    'Provisioning storage channel 2 of 3 (AeroDrive Storage 2)...',
    'Provisioning storage channel 3 of 3 (AeroDrive Storage 3)...',
    'Creating Config & Public Sharing channels...',
    'Setting application icons & encrypted channel descriptions...',
    'Grouping channels into Telegram "AeroDrive" folder...',
    'Promoting secondary accounts as administrators...',
    'Syncing system configuration to config channel...',
    'Finalizing infrastructure setup...',
  ];

  String get _currentStep {
    final index = ((_progress * (_steps.length - 1))).floor().clamp(0, _steps.length - 1);
    return _steps[index];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(authProvider) == AuthState.authenticated && mounted) {
        context.go('/drive');
      }
    });

    _progressTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
      if (!mounted) return;
      setState(() {
        if (_progress < 1.0) {
          _progress += 0.02;
        } else {
          timer.cancel();
          context.go('/drive');
        }
      });
    });
  }

  @override
  void dispose() {
    _progressTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (_, next) {
      if (next == AuthState.authenticated && mounted) {
        context.go('/drive');
      }
    });
    final percentage = (_progress * 100).toInt().clamp(0, 100);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // Animated Logo
              const AeroDriveLogo(size: AeroDriveLogoSize.large)
                  .animate(onPlay: (controller) => controller.repeat(reverse: true))
                  .scale(begin: const Offset(0.95, 0.95), end: const Offset(1.05, 1.05), duration: 2.seconds, curve: Curves.easeInOut)
                  .elevation(begin: 10, end: 30, color: AppColors.primary),
              const SizedBox(height: 40),
              
              Text(
                'Setting Up AeroDrive',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.1,
                    ),
              ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.2, end: 0),
              const SizedBox(height: 12),
              
              Text(
                'Creating your multi-channel cloud infrastructure on Telegram...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                  height: 1.4,
                ),
              ).animate().fadeIn(delay: 200.ms, duration: 500.ms),

              const Spacer(),

              // Status Step Text
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Text(
                  _currentStep,
                  key: ValueKey<String>(_currentStep),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.primaryLight,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Progress Bar Line
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ).animate().fadeIn(delay: 300.ms),
              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Please do not close the app',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    '$percentage%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
