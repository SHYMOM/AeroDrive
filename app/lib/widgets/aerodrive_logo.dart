import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

/// AeroDrive logo sizes.
enum AeroDriveLogoSize {
  small(32),
  medium(48),
  large(72);

  const AeroDriveLogoSize(this.dimension);
  final double dimension;
}

/// Animated AeroDrive logo widget.
///
/// Displays a cloud + upload arrow icon composition with a subtle
/// shimmer/glow animation using the electric violet accent.
class AeroDriveLogo extends StatefulWidget {
  const AeroDriveLogo({
    super.key,
    this.size = AeroDriveLogoSize.medium,
    this.showText = true,
  });

  /// Controls the icon size.
  final AeroDriveLogoSize size;

  /// Whether to show the "AeroDrive" text label beside the icon.
  final bool showText;

  @override
  State<AeroDriveLogo> createState() => _AeroDriveLogoState();
}

class _AeroDriveLogoState extends State<AeroDriveLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dim = widget.size.dimension;
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _glowAnimation,
          builder: (context, child) => Container(
              width: dim,
              height: dim,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(dim * 0.25),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary.withValues(alpha: _glowAnimation.value),
                    AppColors.secondary.withValues(
                      alpha: _glowAnimation.value * 0.7,
                    ),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(
                      alpha: _glowAnimation.value * 0.3,
                    ),
                    blurRadius: dim * 0.4,
                    spreadRadius: dim * 0.05,
                  ),
                ],
              ),
              child: Icon(
                Icons.cloud_upload_rounded,
                size: dim * 0.55,
                color: Colors.white,
              ),
            ),
        ),
        if (widget.showText) ...[
          SizedBox(width: dim * 0.3),
          Text(
            'AeroDrive',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: dim * 0.4,
              letterSpacing: -0.5,
              foreground: Paint()
                ..shader = const LinearGradient(
                  colors: [AppColors.primaryLight, AppColors.secondaryLight],
                ).createShader(
                  Rect.fromLTWH(0, 0, dim * 3, dim * 0.5),
                ),
            ),
          ),
        ],
      ],
    );
  }
}
