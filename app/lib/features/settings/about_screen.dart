import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _launchUrl(BuildContext context, String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open link.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: const Color(0xFF0D0E23),
      appBar: AppBar(
        title: const Text('About AeroDrive'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            radius: 1.5,
            colors: [Color(0xFF0D0E23), Color(0xFF1A0850)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          children: [
            // ── App Hero ──────────────────────────────────────────────
            _buildAppHero(context),
            const SizedBox(height: 32),

            // ── About Application ─────────────────────────────────────
            _buildCard(
              context,
              icon: Icons.info_outline,
              iconColor: const Color(0xFF4A90E2),
              title: 'About Application',
              child: const Text(
                'AeroDrive is an advanced, ultra-secure, and decentralized cloud storage client powered directly by the Telegram TDLib backend. It provides users with unlimited storage by harnessing Telegram channels as a backend file system, wrapped in a beautiful and highly functional Material 3 interface.',
                style: TextStyle(height: 1.6, color: Colors.white70, fontSize: 13),
              ),
            ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1, end: 0),
            const SizedBox(height: 16),

            // ── About Developer ──────────────────────────────────────
            _buildDeveloperCard(context),

            // ── Links ────────────────────────────────────────────────
            _buildCard(
              context,
              icon: Icons.link,
              iconColor: const Color(0xFF7B61FF),
              title: 'Resources & Links',
              child: Column(
                children: [
                  _buildLinkTile(
                    context,
                    icon: Icons.update,
                    label: 'Check for Updates',
                    subtitle: 'You are on the latest version',
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AeroDrive is up to date!'))),
                  ),
                  _buildDivider(),
                  _buildLinkTile(
                    context,
                    icon: Icons.code,
                    label: 'GitHub Repository',
                    subtitle: 'View the source code',
                    onTap: () => _launchUrl(context, 'https://github.com/SHYMOM/AeroDrive'),
                  ),
                  _buildDivider(),
                  _buildLinkTile(
                    context,
                    icon: Icons.bug_report_outlined,
                    label: 'Report a Bug',
                    subtitle: 'Submit an issue on GitHub',
                    onTap: () => _launchUrl(context, 'https://github.com/SHYMOM/AeroDrive/issues'),
                  ),
                  _buildDivider(),
                  _buildLinkTile(
                    context,
                    icon: Icons.favorite_outline,
                    label: 'Support Development',
                    subtitle: 'Support the ongoing development',
                    iconColor: Colors.pinkAccent,
                    onTap: () => _launchUrl(context, 'https://github.com/sponsors/SHYMOM'),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1, end: 0),
            const SizedBox(height: 24),

            // ── Signature Credit ────────────────────────────────────
            _buildSignatureCredit(context),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );

  Widget _buildAppHero(BuildContext context) {
    return Center(
      child: Column(
        children: [
          // Pulsing glow logo
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF4A90E2), Color(0xFF7B61FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4A90E2).withValues(alpha: 0.5),
                  blurRadius: 30,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: const Icon(Icons.cloud, size: 50, color: Colors.white),
          ).animate(onPlay: (c) => c.repeat(reverse: true))
           .scale(begin: const Offset(0.95, 0.95), end: const Offset(1.05, 1.05), duration: 2.seconds),
          const SizedBox(height: 16),
          Text(
            'AeroDrive',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF4A90E2).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF4A90E2).withValues(alpha: 0.4)),
            ),
            child: const Text(
              'Version 1.0.0-alpha',
              style: TextStyle(color: Color(0xFF4A90E2), fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Zero-Knowledge · Unlimited Storage · Open Source',
            style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 0.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 600.ms).scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1));
  }

  Widget _buildDeveloperCard(BuildContext context) {
    return _buildCard(
      context,
      icon: Icons.person_outline,
      iconColor: const Color(0xFF9C27B0),
      title: 'About Developer',
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7B61FF), Color(0xFF9C27B0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7B61FF).withValues(alpha: 0.4),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.network(
                    'https://avatars.githubusercontent.com/u/130169485',
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Text('SS', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SHEIKH SHYMOM ISLAM',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF9C27B0).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF9C27B0).withValues(alpha: 0.3)),
                      ),
                      child: const Text(
                        '🎓 CS Student & App Developer',
                        style: TextStyle(color: Color(0xFFCE93D8), fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '🇧🇩 Bangladesh',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            '👋 Hey there! I\'m Shymom — a CSE student, app dev enthusiast, and tech explorer with a knack for crafting solutions and diving into new tech. I built AeroDrive to make unlimited, secure cloud storage accessible to everyone.',
            style: TextStyle(height: 1.6, color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.white.withValues(alpha: 0.08)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildSocialButton(
                context,
                icon: Icons.code,
                label: 'GitHub',
                color: const Color(0xFF4A90E2),
                url: 'https://github.com/SHYMOM',
              ),
              _buildSocialButton(
                context,
                icon: Icons.facebook,
                label: 'Facebook',
                color: const Color(0xFF1877F2),
                url: 'https://www.facebook.com/Sheikh.Shymom',
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildSocialButton(BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required String url,
  }) {
    return InkWell(
      onTap: () => _launchUrl(context, url),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 18),
                ),
                const SizedBox(width: 10),
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildLinkTile(BuildContext context, {
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    Color iconColor = const Color(0xFF4A90E2),
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                  Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white30),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() => Divider(color: Colors.white.withValues(alpha: 0.06), height: 1);

  // ── Signature Credit Widget ──────────────────────────────────────────────
  Widget _buildSignatureCredit(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1A0850),
            Color(0xFF0D1B4D),
            Color(0xFF1A0850),
          ],
        ),
        border: Border.all(color: const Color(0xFF7B61FF).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7B61FF).withValues(alpha: 0.15),
            blurRadius: 32,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Column(
        children: [
          // Stars decoration
          const _StarDecoration(),
          const SizedBox(height: 12),

          // Flag and heart line
          const Text(
            'Made With ❤️ In 🇧🇩',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              letterSpacing: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),

          // Name with gradient
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFF7B61FF), Color(0xFF4A90E2), Color(0xFFEC4899)],
            ).createShader(bounds),
            child: const Text(
              'SHEIKH SHYMOM ISLAM',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: 12),
          Divider(color: const Color(0xFF7B61FF).withValues(alpha: 0.25)),
          const SizedBox(height: 10),

          // Sub-line
          const Text(
            'Computer Science Student  ·  App Developer  ·  Tech Explorer',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 10.5,
              letterSpacing: 0.8,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).animate().fadeIn(delay: 400.ms).scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1));
  }
}

/// Simple decorative star row
class _StarDecoration extends StatelessWidget {
  const _StarDecoration();

  @override
  Widget build(BuildContext context) {
    final rand = Random(99);
    final stars = List.generate(7, (i) {
      final size = 6.0 + rand.nextDouble() * 4;
      final opacity = 0.3 + rand.nextDouble() * 0.5;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Icon(
          rand.nextBool() ? Icons.star : Icons.star_half,
          size: size,
          color: const Color(0xFF7B61FF).withValues(alpha: opacity),
        ),
      );
    });

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: stars,
    );
  }
}
