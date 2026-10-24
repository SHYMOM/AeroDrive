import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/logger.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../features/security/biometric_auth_service.dart';
import '../../features/telegram/telegram_service.dart';
import '../../widgets/aerodrive_logo.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  double _progress = 0;
  String _statusText = '';

  @override
  void initState() {
    super.initState();
    _statusText = 'Initializing...';
    _progress = 0.02;
    Future.microtask(_runSync);
  }

  Future<void> _runSync() async {
    try {
      // ── Step 1: Animation start ───────────────────────────────────
      if (!mounted) return;
      setState(() {
        _statusText = 'Connecting to AeroDrive...';
        _progress = 0.3;
      });
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;

      // ── Step 2: Await TDLib Auth State Transition ─────────────────
      // TDLib opens local SQLite database and checks session keys asynchronously.
      // We wait up to 4.5 seconds for it to transition from TelegramAuthState.initial.
      final stopwatch = Stopwatch()..start();
      TelegramAuthState telegramState = ref.read(telegramServiceProvider);

      while (mounted &&
             telegramState == TelegramAuthState.initial &&
             stopwatch.elapsedMilliseconds < 4500) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (!mounted) return;
        telegramState = ref.read(telegramServiceProvider);

        final waitRatio = (stopwatch.elapsedMilliseconds / 4500.0).clamp(0.0, 1.0);
        if (mounted) {
          setState(() {
            _progress = 0.3 + (0.55 * waitRatio);
          });
        }
      }

      if (!mounted) return;

      // ── Step 3: Navigate based on determined auth state ────────────
      if (telegramState == TelegramAuthState.ready) {
        if (mounted) {
          setState(() {
            _statusText = 'Welcome back!';
            _progress = 1.0;
          });
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (!mounted) return;

        final authService = ref.read(biometricAuthServiceProvider);
        final lockEnabled = await authService.isAppLockEnabled();
        if (lockEnabled) {
          ref.read(appLockEnabledProvider.notifier).state = true;
          ref.read(isVaultUnlockedProvider.notifier).state = false;
        }

        ref.read(hasNavigatedPastSplashProvider.notifier).state = true;
        if (mounted) {
          if (lockEnabled) {
            context.go('/lock');
          } else {
            context.go('/drive');
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _progress = 1.0;
          });
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
        if (!mounted) return;
        ref.read(hasNavigatedPastSplashProvider.notifier).state = true;
        if (mounted) context.go('/auth');
      }
    } catch (e, s) {
      AppLogger.warning('SplashScreen: _runSync encountered non-fatal error: $e');
      if (mounted) {
        try {
          ref.read(hasNavigatedPastSplashProvider.notifier).state = true;
          context.go('/auth');
        } catch (_) {}
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: 1.5,
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
            ],
          ),
        ),
        child: Stack(
          children: [
            // Starfield
            Positioned.fill(
              child: CustomPaint(
                painter: StarfieldPainter(),
              ).animate(onPlay: (controller) => controller.repeat())
               .moveY(begin: 0, end: 100, duration: 10.seconds, curve: Curves.linear),
            ),

            // Content
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo with neon pulse
                  DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                          blurRadius: 30,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: const AeroDriveLogo(
                      size: AeroDriveLogoSize.large,
                      showText: false,
                    ),
                  ).animate(onPlay: (controller) => controller.repeat(reverse: true))
                   .scale(begin: const Offset(0.9, 0.9), end: const Offset(1.1, 1.1), duration: 2.seconds, curve: Curves.easeInOut)
                   .fadeIn(duration: 800.ms, curve: Curves.easeOut),

                  const SizedBox(height: 64),

                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedSwitcher(
                            duration: 300.ms,
                            child: Text(
                              _statusText,
                              key: ValueKey(_statusText),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                fontSize: 14,
                                letterSpacing: 0.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),

                          const SizedBox(height: 24),

                          Container(
                            height: 4,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: [
                                BoxShadow(
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: _progress > 0 ? _progress : null,
                                backgroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppColors.primary,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 36),

                          // ── Signature Credit ─────────────────────────
                          Column(
                            children: [
                              Text(
                                'Made With ❤️ In 🇧🇩',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
                                  fontSize: 10,
                                  letterSpacing: 1.2,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              ShaderMask(
                                shaderCallback: (bounds) => LinearGradient(
                                  colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary, Theme.of(context).colorScheme.tertiary],
                                ).createShader(bounds),
                                child: Text(
                                  'SHEIKH SHYMOM ISLAM',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ).animate().fadeIn(delay: 500.ms, duration: 800.ms),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
class StarfieldPainter extends CustomPainter {
  final Random random = Random(42); // fixed seed for consistent stars

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    for (var i = 0; i < 80; i++) {
      final x = random.nextDouble() * size.width;
      // Spread stars far vertically to allow for the looping moveY animation
      final y = random.nextDouble() * size.height * 2 - size.height;
      final radius = random.nextDouble() * 1.5 + 0.5;
      final opacity = random.nextDouble() * 0.8 + 0.2;
      paint.color = Colors.white.withValues(alpha: opacity);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
