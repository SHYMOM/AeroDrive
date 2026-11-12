import 'package:flutter/material.dart';

abstract final class AppColors {
  static bool _isDark = false; // Default to Soft-Tonic Light Theme
  static bool get isDark => _isDark;
  static set isDark(bool value) {
    _isDark = value;
    if (_primary.toARGB32() == 0xFF4F46E5) {
      _primaryContainer = value ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF);
    }
  }

  // ── Background & Surface (Soft-Tonic Canvas & Elevated Pure White) ───
  // Light: Cool Alabaster / Soft Periwinkle-Tinted White (#F4F7FE)
  // Dark: Recessed Deep Canvas (#0D131F)
  static Color get background => isDark ? const Color(0xFF0D131F) : const Color(0xFFF4F7FE);
  
  // Elevated surfaces, floating cards, sidebar panels
  static Color get surface => isDark ? const Color(0xFF161F30) : const Color(0xFFFFFFFF);
  static Color get surfaceElevated => isDark ? const Color(0xFF1D283E) : const Color(0xFFFFFFFF);
  
  // Hover & selection pills (#EEF2FF Whisper Indigo)
  static Color get surfaceVariant => isDark ? const Color(0xFF222F46) : const Color(0xFFEEF2FF);
  static Color get surfaceContainerHighest => isDark ? const Color(0xFF25334B) : const Color(0xFFE0E7FF);

  // ── Primary Brand Accent (Royal Indigo / Deep Periwinkle) ────────────
  static Color _primary = const Color(0xFF4F46E5); // Royal Indigo #4F46E5
  static Color _primaryLight = const Color(0xFF818CF8); 
  static Color _primaryDark = const Color(0xFF3730A3);
  static Color _primaryContainer = const Color(0xFFEEF2FF);

  static Color get primary => _primary;
  static Color get primaryLight => _primaryLight;
  static Color get primaryDark => _primaryDark;
  static Color get primaryContainer => _primaryContainer;

  // ── Secondary Brand Accent (Sky Blue for folders and highlights) ─────
  static Color _secondary = const Color(0xFF3B82F6); // Sky Blue #3B82F6
  static Color _secondaryLight = const Color(0xFF60A5FA);
  static Color _secondaryDark = const Color(0xFF1D4ED8);

  static Color get secondary => _secondary;
  static Color get secondaryLight => _secondaryLight;
  static Color get secondaryDark => _secondaryDark;

  // ── Semantic Colors ────────────────────────────────────────────────
  static const Color tertiary = Color(0xFFF472B6);
  static const Color error = Color(0xFFEF4444);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);

  // ── Text & Typography (Deep Slate 900 for high-contrast legibility) ──
  static Color get onBackground => isDark ? const Color(0xFFFFFFFF) : const Color(0xFF0F172A); // Slate 900
  static Color get onSurface => isDark ? const Color(0xFFFFFFFF) : const Color(0xFF0F172A);
  static Color get onSurfaceVariant => isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B); // Slate 500
  static Color get subtleText => isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8); // Slate 400
  static Color get onPrimary => _primary.computeLuminance() > 0.5 ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
  static Color get onSecondary => _secondary.computeLuminance() > 0.5 ? const Color(0xFF000000) : const Color(0xFFFFFFFF);

  // ── Borders & Dividers (Subtle, non-jarring hairline dividers) ────────
  static Color get outline => isDark ? const Color(0x14FFFFFF) : const Color(0xFFE2E8F0);
  static Color get outlineVariant => isDark ? const Color(0x0AFFFFFF) : const Color(0xFFF1F5F9);
  static Color get borderSubtle => outline;

  // Convenient Aliases
  static Color get canvas => background;
  static Color get textPrimary => onSurface;
  static Color get textSecondary => onSurfaceVariant;

  // ── Glassmorphism ─────────────────────────────────────────────────
  static Color get glassBg => isDark ? const Color(0x33151C28) : const Color(0xE6FFFFFF); 
  static Color get glassBorder => isDark ? const Color(0x1FFFFFFF) : const Color(0x1F000000); 
  static Color get glassBgDark => isDark ? const Color(0x800B0F17) : const Color(0x80FFFFFF); 

  // ── Ambient Soft Shadows (Zero harsh neon glows) ───────────────────
  static Color get softShadow => isDark ? const Color(0x40000000) : const Color(0x0A000000);
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: isDark ? const Color(0x40000000) : const Color(0x0A000000),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];
  static List<BoxShadow> get floatingShadow => [
    BoxShadow(
      color: isDark ? const Color(0x60000000) : const Color(0x14000000),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];
  static Color get glowCyan => _primary.withValues(alpha: 0.2); 
  static const Color shadow = Color(0x40000000);
  static const Color scrim = Color(0x80000000);

  // ── Pastel Squircle Category Colors ────────────────────────────────
  // Images (Indigo / Purple)
  static const Color categoryImages = Color(0xFF6366F1);
  static Color get categoryImagesBg => isDark ? const Color(0xFF23254B) : const Color(0xFFEEF2FF);

  // Videos (Coral / Rose)
  static const Color categoryVideos = Color(0xFFEF4444);
  static Color get categoryVideosBg => isDark ? const Color(0xFF451E24) : const Color(0xFFFEF2F2);

  // Documents (Cyan / Sky)
  static const Color categoryDocuments = Color(0xFF0EA5E9);
  static Color get categoryDocumentsBg => isDark ? const Color(0xFF153448) : const Color(0xFFF0F9FF);

  // Audio (Amber / Warm Yellow)
  static const Color categoryAudio = Color(0xFFF59E0B);
  static Color get categoryAudioBg => isDark ? const Color(0xFF422E15) : const Color(0xFFFFFBEB);

  // Offline / Storage (Emerald / Mint)
  static const Color categoryOffline = Color(0xFF10B981);
  static Color get categoryOfflineBg => isDark ? const Color(0xFF13392E) : const Color(0xFFECFDF5);

  // ── Dynamic Theme Update Hook ─────────────────────────────────────
  static void update({
    required bool isDark,
    Color? primary,
    Color? secondary,
  }) {
    _isDark = isDark;
    if (primary != null) {
      _primary = primary;
      if (primary.toARGB32() == 0xFF4F46E5) {
        _primaryLight = const Color(0xFF818CF8);
        _primaryDark = const Color(0xFF3730A3);
        _primaryContainer = isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF);
      } else {
        final hsl = HSLColor.fromColor(primary);
        _primaryLight = hsl.withLightness((hsl.lightness + 0.15).clamp(0.0, 1.0)).toColor();
        _primaryDark = hsl.withLightness((hsl.lightness - 0.15).clamp(0.0, 1.0)).toColor();
        _primaryContainer = isDark
            ? hsl.withLightness((hsl.lightness * 0.4).clamp(0.0, 1.0)).withSaturation((hsl.saturation * 0.8).clamp(0.0, 1.0)).toColor()
            : hsl.withLightness((hsl.lightness + 0.35).clamp(0.0, 1.0)).withSaturation((hsl.saturation * 0.5).clamp(0.0, 1.0)).toColor();
      }
    } else {
      if (_primary.toARGB32() == 0xFF4F46E5) {
        _primaryContainer = isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF);
      } else {
        final hsl = HSLColor.fromColor(_primary);
        _primaryContainer = isDark
            ? hsl.withLightness((hsl.lightness * 0.4).clamp(0.0, 1.0)).withSaturation((hsl.saturation * 0.8).clamp(0.0, 1.0)).toColor()
            : hsl.withLightness((hsl.lightness + 0.35).clamp(0.0, 1.0)).withSaturation((hsl.saturation * 0.5).clamp(0.0, 1.0)).toColor();
      }
    }

    if (secondary != null) {
      _secondary = secondary;
      if (secondary.toARGB32() == 0xFF3B82F6) {
        _secondaryLight = const Color(0xFF60A5FA);
        _secondaryDark = const Color(0xFF1D4ED8);
      } else {
        final hslSec = HSLColor.fromColor(secondary);
        _secondaryLight = hslSec.withLightness((hslSec.lightness + 0.15).clamp(0.0, 1.0)).toColor();
        _secondaryDark = hslSec.withLightness((hslSec.lightness - 0.15).clamp(0.0, 1.0)).toColor();
      }
    }
  }

  // ── Multi-Color Folder References (8 Curated macOS/Soft-Tonic colors) ─
  static const Map<String, Color> folderColors = {
    'Sky Blue': Color(0xFF3B82F6),
    'Indigo': Color(0xFF6366F1),
    'Emerald': Color(0xFF10B981),
    'Amber': Color(0xFFF59E0B),
    'Coral': Color(0xFFF43F5E),
    'Teal': Color(0xFF14B8A6),
    'Violet': Color(0xFF8B5CF6),
    'Slate': Color(0xFF64748B),
  };

  static const Color folderDefault = Color(0xFF3B82F6); // Sky Blue Apple-style folder

  /// Safely resolves a folder color from hex string or fallback to [folderDefault].
  static Color resolveFolderColor(String? colorStr) {
    if (colorStr == null || colorStr.isEmpty) return folderDefault;
    try {
      var s = colorStr.trim();
      if (s.startsWith('#')) {
        s = s.replaceFirst('#', '0xFF');
      } else if (!s.startsWith('0x') && !s.startsWith('0X')) {
        s = '0x$s';
      }
      return Color(int.parse(s));
    } catch (_) {
      // Check if named in map
      if (folderColors.containsKey(colorStr)) {
        return folderColors[colorStr]!;
      }
      return folderDefault;
    }
  }

  // ── File-type icon colors ────────────────────────
  static const Color fileFolder = Color(0xFF3B82F6); 
  static const Color fileImage = Color(0xFF6366F1); 
  static const Color fileVideo = Color(0xFFEF4444); 
  static const Color fileAudio = Color(0xFFF59E0B); 
  static const Color fileDocument = Color(0xFF0EA5E9); 
  static const Color fileArchive = Color(0xFFF97316); 
  static const Color fileCode = Color(0xFF14B8A6); 
  static const Color filePdf = Color(0xFFEF4444); 
  static const Color fileUnknown = Color(0xFF94A3B8); 
}
