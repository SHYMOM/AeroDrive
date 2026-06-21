import 'package:flutter/material.dart';
import 'package:aerodrive/core/theme/app_colors.dart';

class AeroDriveLogo extends StatelessWidget {
  final double size;
  
  const AeroDriveLogo({super.key, this.size = 64});

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.cloud_sync,
      size: size,
      color: AppColors.primary,
    );
  }
}
