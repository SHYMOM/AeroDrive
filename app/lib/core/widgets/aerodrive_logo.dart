import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class AeroDriveLogo extends StatelessWidget {
  
  const AeroDriveLogo({super.key, this.size = 64});
  final double size;

  @override
  Widget build(BuildContext context) => Icon(
      Icons.cloud_sync,
      size: size,
      color: AppColors.primary,
    );
}
