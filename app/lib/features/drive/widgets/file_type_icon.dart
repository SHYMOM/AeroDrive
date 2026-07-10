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
        color = const Color(0xFF10B981); // Green
      case 'doc':
      case 'docx':
        color = const Color(0xFF3B82F6); // Blue
      case 'ppt':
      case 'pptx':
        color = const Color(0xFFF97316); // Orange
      case 'ps':
      case 'psd':
        color = const Color(0xFF0284C7); // Light Blue
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
        color = const Color(0xFFF59E0B); // Amber
      case 'mp3':
      case 'wav':
      case 'ogg':
      case 'flac':
      case 'm4a':
        color = const Color(0xFF8B5CF6); // Purple
      case 'txt':
      case 'md':
      case 'log':
        color = const Color(0xFF64748B); // Slate Grey
      default:
        color = const Color(0xFF475569); // Dark slate
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
    return SizedBox(
      width: size,
      height: size,
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
    final paint = Paint()
      ..color = color
      ..style = style
      ..strokeWidth = style == PaintingStyle.stroke ? 2.0 : 0;

    final path = Path();
    final double fold = size.width * 0.32; // dog-ear corner size

    path.moveTo(0, size.height * 0.1);
    path.quadraticBezierTo(0, 0, size.height * 0.1, 0); // round top-left slightly
    path.lineTo(size.width - fold, 0);
    path.lineTo(size.width, fold);
    path.lineTo(size.width, size.height - (size.height * 0.1));
    path.quadraticBezierTo(size.width, size.height, size.width - (size.height * 0.1), size.height);
    path.lineTo(size.height * 0.1, size.height);
    path.quadraticBezierTo(0, size.height, 0, size.height - (size.height * 0.1));
    path.close();

    canvas.drawPath(path, paint);

    // Draw folded flap only for fill style
    if (style == PaintingStyle.fill) {
      final flapPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;

      final flapPath = Path();
      flapPath.moveTo(size.width - fold, 0);
      flapPath.lineTo(size.width - fold, fold - (fold * 0.2));
      flapPath.quadraticBezierTo(size.width - fold, fold, size.width - fold + (fold * 0.2), fold);
      flapPath.lineTo(size.width, fold);
      flapPath.close();

      canvas.drawPath(flapPath, flapPaint);

      final flapHighlightPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..style = PaintingStyle.fill;

      canvas.drawPath(flapPath, flapHighlightPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
