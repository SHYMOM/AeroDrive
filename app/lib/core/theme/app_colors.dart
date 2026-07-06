import 'package:flutter/material.dart';

abstract final class AppColors {
  static bool isDark = true;

  // ── Background & Surface ────────────────────
  static Color get background => isDark ? const Color(0xFF040609) : const Color(0xFFF8FAFC); // Deep space dark vs slate 50
  static Color get surface => isDark ? const Color(0xFF0B1018) : const Color(0xFFFFFFFF); // Deep card vs pure white
  static Color get surfaceElevated => isDark ? const Color(0xFF131A26) : const Color(0xFFFFFFFF); // Elevated dark card vs pure white
  static Color get surfaceVariant => isDark ? const Color(0xFF161F2E) : const Color(0xFFF1F5F9); // Dark slate vs slate 100
  static Color get surfaceContainerHighest => isDark ? const Color(0xFF192436) : const Color(0xFFE2E8F0); // Deep slate container vs slate 200

  // ── Primary — Electric Cyan (AeroDrive brand) ──────────────────────
  static const Color primary = Color(0xFF00E5FF); // neonCyan
  static const Color primaryLight = Color(0xFF67E8F9); 
  static const Color primaryDark = Color(0xFF0891B2);
  static const Color primaryContainer = Color(0xFF0D3B4D); // Deep cyan tint

  // ── Secondary — Deep Violet (For contrasts) ────────────────────────
  static const Color secondary = Color(0xFF7C3AED); // neonViolet
  static const Color secondaryLight = Color(0xFF8B5CF6);
  static const Color secondaryDark = Color(0xFF5B21B6);

  // ── Semantic ──────────────────────────────────────────────────────
  static const Color tertiary = Color(0xFFF472B6);
  static const Color error = Color(0xFFEF4444);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);

  // ── Text & Icons ──────────────────────────────────────────────────
  static Color get onBackground => isDark ? const Color(0xFFFFFFFF) : const Color(0xFF0F172A); // White text vs Slate 900
  static Color get onSurface => isDark ? const Color(0xFFFFFFFF) : const Color(0xFF0F172A);
  static Color get onSurfaceVariant => isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B); // Slate subtitle vs Slate 500
  static const Color onPrimary = Color(0xFF000000);
  static const Color onSecondary = Color(0xFFFFFFFF);

  // ── Borders & Dividers ────────────────────────────────────────────
  static Color get outline => isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0); // Subtle borders
  static Color get outlineVariant => isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);

  // ── Glassmorphism ─────────────────────────────────────────────────
  static Color get glassBg => isDark ? const Color(0x08FFFFFF) : const Color(0x0D000000); 
  static Color get glassBorder => isDark ? const Color(0x11FFFFFF) : const Color(0x1A000000); 
  static Color get glassBgDark => isDark ? const Color(0x730B1018) : const Color(0x73FFFFFF); 

  // ── Glow (Shadows) ────────────────────────────────────────────────
  static const Color glowCyan = Color(0x6600E5FF); 
  static const Color shadow = Color(0x80000000);
  static const Color scrim = Color(0xCC000000);

  // ── Multi-Color Folder References ──────────────────
  static const Map<String, Color> folderColors = {
    'Blue': Color(0xFF60A5FA),
    'Pink': Color(0xFFF472B6),
    'Cyan': Color(0xFF2DD4BF),
    'Red': Color(0xFFF87171),
    'Purple': Color(0xFFA78BFA),
    'Orange': Color(0xFFFBBF24),
    'Yellow': Color(0xFFFDE047),
    'Slate': Color(0xFFCBD5E1),
  };

  static const Color folderDefault = Color(0xFF60A5FA);

  // ── File-type icon colors ────────────────────────
  static const Color fileFolder = Color(0xFF00E5FF); 
  static const Color fileImage = Color(0xFF10B981); 
  static const Color fileVideo = Color(0xFF8B5CF6); 
  static const Color fileAudio = Color(0xFFEC4899); 
  static const Color fileDocument = Color(0xFFF59E0B); 
  static const Color fileArchive = Color(0xFFF97316); 
  static const Color fileCode = Color(0xFF14B8A6); 
  static const Color filePdf = Color(0xFFEF4444); 
  static const Color fileUnknown = Color(0xFF94A3B8); 
}
