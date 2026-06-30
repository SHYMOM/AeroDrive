import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cryptography/cryptography.dart';

import 'package:aerodrive/widgets/aerodrive_logo.dart';
import 'package:aerodrive/core/providers/security_providers.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:aerodrive/core/theme/app_colors.dart';
import 'package:aerodrive/core/logger.dart';
import 'package:aerodrive/domain/recovery/recovery_scanner.dart';
import 'package:aerodrive/domain/saved_messages_sync.dart';
import 'package:aerodrive/features/drive/providers/drive_providers.dart';
import 'package:aerodrive/features/telegram/telegram_service.dart';

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
      // Phase 1: Initializing (0–0.08)
      setState(() { _statusText = 'Initializing...'; });
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      setState(() { _progress = 0.08; });

      // Bootstrap salt from channel description for cross-device key derivation.
      await _bootstrapSaltFromChannel();

      // Check if a master key exists (i.e. a password has been set up).
      final masterKeyList = ref.read(masterKeyProvider);
      if (masterKeyList == null) {
        setState(() { _progress = 1; _statusText = 'Ready'; });
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) context.go('/auth');
        return;
      }

      final cipher = AesGcm.with256bits();
      final masterKey = await cipher.newSecretKeyFromBytes(masterKeyList);
      final settings = ref.read(settingsRepositoryProvider);

      // Phase 2: Restore from Saved Messages (0.08–0.3)
      final smEnabled = await settings.getSetting('saved_messages_sync_enabled');
      if (smEnabled == 'true' && mounted) {
        setState(() { _progress = 0.1; _statusText = 'Restoring from Saved Messages...'; });
        final sync = ref.read(savedMessagesSyncProvider);
        final restored = await sync.restoreFromSavedMessages(masterKey);
        if (restored && mounted) {
          ref.read(dbRebuildVersionProvider.notifier).state++;
        }
        if (mounted) setState(() { _progress = 0.3; });
      }

      // Phase 3: Scan channel captions (0.3–0.95)
      if (mounted) {
        final ccEnabled = await settings.getSetting('channel_caption_sync_enabled');
        if (ccEnabled == 'true') {
          final activeChannelStr = await settings.getSetting('active_channel_id');
          if (activeChannelStr != null) {
            setState(() { _statusText = 'Scanning channel messages...'; });
            final scanner = ref.read(recoveryServiceProvider);
            await scanner.runDisasterRecovery(
              masterKey: masterKey,
              channelId: int.parse(activeChannelStr),
              onProgress: (scanned, recovered) {
                if (!mounted) return;
                setState(() {
                  _progress = 0.3 + (scanned / 2000).clamp(0.0, 0.65);
                  _statusText = scanned < 2000
                      ? 'Scanning: $scanned messages, $recovered items found'
                      : 'Processed $scanned messages, $recovered items recovered';
                });
              },
            );
            if (mounted) {
              ref.read(dbRebuildVersionProvider.notifier).state++;
            }
          }
        }
      }

      // Phase 4: Done (0.95–1.0)
      if (mounted) {
        setState(() { _progress = 1; _statusText = 'Sync complete!'; });
      }
    } catch (e, s) {
      AppLogger.error('Splash sync failed', e, s);
      if (mounted) {
        setState(() { _progress = 1; _statusText = 'Ready'; });
      }
    }

    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) context.go('/auth');
  }

  /// Reads the active channel's description for a cross-device salt.
  /// If found and it differs from the local salt, adopts it so the lock screen
  /// uses the same salt → same derived key on all devices.
  Future<void> _bootstrapSaltFromChannel() async {
    try {
      final settings = ref.read(settingsRepositoryProvider);
      final channelIdStr = await settings.getSetting('active_channel_id');
      if (channelIdStr == null) return;

      final telegram = ref.read(telegramServiceProvider.notifier);
      final description = await telegram.getChannelDescription(int.parse(channelIdStr));
      if (description == null || !description.startsWith('AERODRIVE_SALT:')) return;

      final remoteSalt = description.substring('AERODRIVE_SALT:'.length).trim();
      if (remoteSalt.isEmpty) return;

      final localSalt = await settings.getSetting('master_password_salt');
      if (localSalt == null || localSalt.isEmpty) {
        await settings.setSetting('master_password_salt', remoteSalt);
        AppLogger.info('Splash: adopted salt from channel description (no local salt)');
      } else if (remoteSalt != localSalt) {
        AppLogger.warning('Splash: remote salt differs from local salt — local salt preserved (re-login on other device to unify)');
      }
    } catch (e) {
      AppLogger.error('Failed to bootstrap salt from channel', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.5,
            colors: [
              Color(0xFF0D0E23), // deepSpace
              Color(0xFF1A0850), // dark edge
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
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.6),
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
                              style: const TextStyle(
                                color: Colors.white70,
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
                                  color: AppColors.primary.withOpacity(0.4),
                                  blurRadius: 8,
                                  spreadRadius: 0,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: _progress > 0 ? _progress : null,
                                backgroundColor: Colors.white.withOpacity(0.1),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppColors.primary,
                                ),
                              ),
                            ),
                          ),
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
}

class StarfieldPainter extends CustomPainter {
  final Random random = Random(42); // fixed seed for consistent stars

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    for (int i = 0; i < 80; i++) {
      final x = random.nextDouble() * size.width;
      // Spread stars far vertically to allow for the looping moveY animation
      final y = random.nextDouble() * size.height * 2 - size.height;
      final radius = random.nextDouble() * 1.5 + 0.5;
      final opacity = random.nextDouble() * 0.8 + 0.2;
      paint.color = Colors.white.withOpacity(opacity);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
