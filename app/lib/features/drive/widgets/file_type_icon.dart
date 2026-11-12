import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/drive_providers.dart';

class FileTypeIcon extends ConsumerWidget {

  const FileTypeIcon({
    super.key,
    required this.mimeType,
    required this.fileName,
    this.size = 56,
    this.style,
  });
  final String? mimeType;
  final String fileName;
  final double size;
  final String? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ext = fileName.split('.').last.toLowerCase();

    final styleAsync = ref.watch(fileIconStyleProvider);
    final effectiveStyle = style ?? styleAsync.valueOrNull ?? 'Colored';

    Color color;
    switch (ext) {
      case 'pdf':
        color = const Color(0xFFEF4444); // Red
      case 'xls':
      case 'xlsx':
      case 'csv':
        color = const Color(0xFF10B981); // Emerald Green
      case 'doc':
      case 'docx':
        color = const Color(0xFF3B82F6); // Blue
      case 'ppt':
      case 'pptx':
        color = const Color(0xFFF97316); // Orange
      case 'ps':
      case 'psd':
      case 'ai':
        color = const Color(0xFF0284C7); // Light Blue / Creative
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        color = const Color(0xFF14B8A6); // Teal
      case 'mp3':
      case 'wav':
      case 'ogg':
      case 'flac':
      case 'm4a':
      case 'aac':
        color = const Color(0xFF8B5CF6); // Purple
      case 'js':
      case 'ts':
      case 'html':
      case 'css':
      case 'dart':
      case 'py':
      case 'json':
      case 'yaml':
      case 'xml':
        color = const Color(0xFFF59E0B); // Amber / Code
      case 'txt':
      case 'md':
      case 'log':
        color = const Color(0xFF64748B); // Slate Grey
      default:
        color = const Color(0xFF64748B); // Slate
    }

    switch (effectiveStyle) {
      case 'Minimal':
        return _buildMinimal(ext);
      case 'Filled':
        return _buildFilled(ext, color);
      case 'Outlined':
        return _buildOutlined(ext, color);
      case 'Colored':
      default:
        return _buildColored(ext, color);
    }
  }

  Widget _buildColored(String ext, Color color) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: DogEarFilePainter(color: color),
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(top: size * 0.15),
            child: Text(
              ext.toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.20,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMinimal(String ext) {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Text(
          ext.toUpperCase(),
          style: TextStyle(
            color: Colors.grey,
            fontSize: size * 0.20,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildFilled(String ext, Color color) {
    return Center(
      child: SizedBox(
        width: size * 0.74,
        height: size * 0.96,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(size * 0.12),
          ),
          child: Center(
            child: Padding(
              padding: EdgeInsets.only(top: size * 0.15),
              child: Text(
                ext.toUpperCase(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOutlined(String ext, Color color) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: DogEarFilePainter(color: color, style: PaintingStyle.stroke),
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(top: size * 0.15),
            child: Text(
              ext.toUpperCase(),
              style: TextStyle(
                color: color,
                fontSize: size * 0.20,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DogEarFilePainter extends CustomPainter {
  DogEarFilePainter({
    required this.color,
    this.style = PaintingStyle.fill,
  });
  final Color color;
  final PaintingStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    // Vertical document sheet aspect ratio (~0.74 width, 0.96 height) centered
    final docWidth = size.width * 0.74;
    final docHeight = size.height * 0.96;
    final left = (size.width - docWidth) / 2;
    final top = (size.height - docHeight) / 2;
    final right = left + docWidth;
    final bottom = top + docHeight;

    final fold = docWidth * 0.32; // crisp corner fold
    final radius = docWidth * 0.08;

    final paint = Paint()
      ..color = color
      ..style = style
      ..strokeWidth = style == PaintingStyle.stroke ? 2.0 : 0;

    final path = Path();
    path.moveTo(left, top + radius);
    path.quadraticBezierTo(left, top, left + radius, top);
    path.lineTo(right - fold, top);
    path.lineTo(right, top + fold);
    path.lineTo(right, bottom - radius);
    path.quadraticBezierTo(right, bottom, right - radius, bottom);
    path.lineTo(left + radius, bottom);
    path.quadraticBezierTo(left, bottom, left, bottom - radius);
    path.close();

    // Draw subtle drop shadow behind the page if fill style
    if (style == PaintingStyle.fill) {
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.14)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
      canvas.drawPath(path.shift(const Offset(0, 1.5)), shadowPaint);
    }

    canvas.drawPath(path, paint);

    // Draw folded corner flap
    if (style == PaintingStyle.fill) {
      // Dark under-flap
      final flapPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..style = PaintingStyle.fill;

      final flapPath = Path();
      flapPath.moveTo(right - fold, top);
      flapPath.lineTo(right - fold, top + fold - 2);
      flapPath.quadraticBezierTo(right - fold, top + fold, right - fold + 2, top + fold);
      flapPath.lineTo(right, top + fold);
      flapPath.close();

      canvas.drawPath(flapPath, flapPaint);

      // Light highlight on top of flap
      final flapHighlightPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.20)
        ..style = PaintingStyle.fill;

      canvas.drawPath(flapPath, flapHighlightPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
