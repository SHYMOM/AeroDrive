import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Shown when the remote gate returns "BLOCKED".
/// The user cannot proceed — tapping the button exits the application.
class TestingEndedScreen extends StatefulWidget {
  const TestingEndedScreen({super.key});

  @override
  State<TestingEndedScreen> createState() => _TestingEndedScreenState();
}

class _TestingEndedScreenState extends State<TestingEndedScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _exitApp() {
    SystemNavigator.pop(); // exits on Android
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08091A),
      body: Stack(
        children: [
          // ── Animated starfield background ──────────────────────────
          Positioned.fill(
            child: CustomPaint(painter: _StarfieldPainter())
                .animate(onPlay: (c) => c.repeat())
                .moveY(begin: 0, end: 80, duration: 12.seconds, curve: Curves.linear),
          ),

          // ── Subtle grid overlay ────────────────────────────────────
          Positioned.fill(
            child: CustomPaint(painter: _GridPainter()),
          ),

          // ── Main content ───────────────────────────────────────────
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated status orb
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (_, child) {
                      final glow = 20 + 20 * _pulseController.value;
                      return Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF1A0000),
                          border: Border.all(
                            color: const Color(0xFFFF3B30).withValues(
                              alpha: 0.5 + 0.4 * _pulseController.value,
                            ),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF3B30).withValues(
                                alpha: 0.3 + 0.3 * _pulseController.value,
                              ),
                              blurRadius: glow,
                              spreadRadius: glow / 3,
                            ),
                          ],
                        ),
                        child: child,
                      );
                    },
                    child: const Icon(
                      Icons.lock_outline_rounded,
                      color: Color(0xFFFF3B30),
                      size: 52,
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 600.ms)
                      .scale(
                          begin: const Offset(0.7, 0.7),
                          end: const Offset(1, 1),
                          duration: 600.ms,
                          curve: Curves.elasticOut),

                  const SizedBox(height: 36),

                  // ── Headline ───────────────────────────────────────
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFFFF6B6B), Color(0xFFFF3B30)],
                    ).createShader(bounds),
                    child: const Text(
                      'Testing Has Ended',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        height: 1.2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 200.ms, duration: 500.ms)
                      .slideY(begin: 0.15, end: 0, delay: 200.ms),

                  const SizedBox(height: 16),

                  // ── Sub-message ────────────────────────────────────
                  const Text(
                    'This testing session is now closed.\nStay tuned for the next test release\nand the official launch!',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 15,
                      height: 1.7,
                      letterSpacing: 0.3,
                    ),
                    textAlign: TextAlign.center,
                  )
                      .animate()
                      .fadeIn(delay: 350.ms, duration: 500.ms)
                      .slideY(begin: 0.1, end: 0, delay: 350.ms),

                  const SizedBox(height: 40),

                  // ── Divider decoration ─────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 1,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.transparent, Color(0xFFFF3B30)],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFFF3B30),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 1,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFFFF3B30), Colors.transparent],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ).animate().fadeIn(delay: 500.ms),

                  const SizedBox(height: 40),

                  // ── Info card ──────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.white.withValues(alpha: 0.04),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Column(
                      children: [
                        _InfoRow(
                          icon: Icons.rocket_launch_outlined,
                          iconColor: const Color(0xFF4A90E2),
                          text: 'New version is in development',
                        ),
                        const SizedBox(height: 14),
                        _InfoRow(
                          icon: Icons.notifications_active_outlined,
                          iconColor: const Color(0xFF7B61FF),
                          text: 'Updates coming soon',
                        ),
                        const SizedBox(height: 14),
                        _InfoRow(
                          icon: Icons.security_outlined,
                          iconColor: const Color(0xFF34C759),
                          text: 'Your data remains safe & encrypted',
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 550.ms).slideY(begin: 0.1, end: 0, delay: 550.ms),

                  const SizedBox(height: 40),

                  // ── Exit button ────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _exitApp,
                      icon: const Icon(Icons.exit_to_app_rounded),
                      label: const Text(
                        'Exit Application',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFF3B30),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ).animate().fadeIn(delay: 700.ms).slideY(begin: 0.1, end: 0, delay: 700.ms),

                  const SizedBox(height: 32),

                  // ── Creator credit ─────────────────────────────────
                  Column(
                    children: [
                      Text(
                        'Made With ❤️ In 🇧🇩',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.25),
                          fontSize: 10,
                          letterSpacing: 1.2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 3),
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Color(0xFF7B61FF), Color(0xFF4A90E2), Color(0xFFEC4899)],
                        ).createShader(bounds),
                        child: const Text(
                          'SHEIKH SHYMOM ISLAM',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ).animate().fadeIn(delay: 900.ms),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helper Widgets ──────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  final IconData icon;
  final Color iconColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: iconColor.withValues(alpha: 0.12),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
        ),
      ],
    );
  }
}

// ── Painters ────────────────────────────────────────────────────────────────

class _StarfieldPainter extends CustomPainter {
  final Random _rng = Random(77);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var i = 0; i < 90; i++) {
      final x = _rng.nextDouble() * size.width;
      final y = _rng.nextDouble() * size.height * 2 - size.height;
      final radius = _rng.nextDouble() * 1.4 + 0.3;
      final opacity = _rng.nextDouble() * 0.6 + 0.1;
      paint.color = Colors.white.withValues(alpha: opacity);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.02)
      ..strokeWidth = 0.5;

    const spacing = 40.0;
    for (var x = 0.0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}
