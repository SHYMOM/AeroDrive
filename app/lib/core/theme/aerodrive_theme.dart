import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'theme_provider.dart';

/// Represents a curated, named color theme preset.
class AeroThemePreset {
  const AeroThemePreset({
    required this.name,
    required this.primary,
    required this.secondary,
    required this.icon,
    required this.gradient,
  });

  final String name;
  final Color primary;
  final Color secondary;
  final IconData icon;
  final List<Color> gradient;
}

/// AeroDrive dynamic theme generation using FlexColorScheme.
abstract final class AeroDriveTheme {

  static const int _defaultAccent    = 0xFF1A73E8; // Google Blue
  static const int _defaultSecondary = 0xFF4285F4; // Google Blue Light

  /// Curated theme presets for AeroDrive.
  static const List<AeroThemePreset> presets = [
    // ── Professional presets (top of list = default) ──────────────
    AeroThemePreset(
      name: 'Professional Dark',
      primary: Color(0xFF1A73E8),
      secondary: Color(0xFF4285F4),
      icon: Icons.dark_mode,
      gradient: [Color(0xFF1A73E8), Color(0xFF4285F4)],
    ),
    AeroThemePreset(
      name: 'Google Blue',
      primary: Color(0xFF1A73E8),
      secondary: Color(0xFF4285F4),
      icon: Icons.cloud,
      gradient: [Color(0xFF1A73E8), Color(0xFF4285F4)],
    ),
    AeroThemePreset(
      name: 'Material Light',
      primary: Color(0xFF1565C0),
      secondary: Color(0xFF42A5F5),
      icon: Icons.light_mode,
      gradient: [Color(0xFF1565C0), Color(0xFF42A5F5)],
    ),
    // ── Fun/Lifestyle presets ─────────────────────────────────────
    AeroThemePreset(
      name: 'Neon Cyan',
      primary: Color(0xFF00E5FF),
      secondary: Color(0xFF7C3AED),
      icon: Icons.bolt,
      gradient: [Color(0xFF00E5FF), Color(0xFF7C3AED)],
    ),
    AeroThemePreset(
      name: 'Electric Violet',
      primary: Color(0xFF7C3AED),
      secondary: Color(0xFFEC4899),
      icon: Icons.auto_awesome,
      gradient: [Color(0xFF7C3AED), Color(0xFFEC4899)],
    ),
    AeroThemePreset(
      name: 'Rose Gold',
      primary: Color(0xFFE8758A),
      secondary: Color(0xFFF59E0B),
      icon: Icons.diamond_outlined,
      gradient: [Color(0xFFE8758A), Color(0xFFF59E0B)],
    ),
    AeroThemePreset(
      name: 'Forest Green',
      primary: Color(0xFF10B981),
      secondary: Color(0xFF14B8A6),
      icon: Icons.eco,
      gradient: [Color(0xFF10B981), Color(0xFF14B8A6)],
    ),
    AeroThemePreset(
      name: 'Sunset Orange',
      primary: Color(0xFFEA580C),
      secondary: Color(0xFFF59E0B),
      icon: Icons.wb_sunny_outlined,
      gradient: [Color(0xFFEA580C), Color(0xFFF59E0B)],
    ),
    AeroThemePreset(
      name: 'Midnight Purple',
      primary: Color(0xFF6D28D9),
      secondary: Color(0xFF2563EB),
      icon: Icons.nightlight_round,
      gradient: [Color(0xFF6D28D9), Color(0xFF2563EB)],
    ),
    AeroThemePreset(
      name: 'Arctic Ice',
      primary: Color(0xFF0EA5E9),
      secondary: Color(0xFF38BDF8),
      icon: Icons.ac_unit,
      gradient: [Color(0xFF0EA5E9), Color(0xFF38BDF8)],
    ),
  ];

  /// Finds the preset that matches a given primary color value.
  static AeroThemePreset? presetFromAccentValue(int value) {
    try {
      return presets.firstWhere((p) => p.primary.toARGB32() == value);
    } catch (_) {
      return null;
    }
  }

  /// Generates the Light ThemeData based on the current global state.
  static ThemeData getLight(AeroThemeState state) {
    final primary = Color(state.accentColorValue != 0
        ? state.accentColorValue
        : _defaultAccent);
    final preset = presetFromAccentValue(state.accentColorValue);
    final secondary = preset != null ? preset.secondary : Color(_defaultSecondary);

    return FlexThemeData.light(
      colors: FlexSchemeColor.from(
        primary: primary,
        secondary: secondary,
        brightness: Brightness.light,
      ),
      surfaceMode: FlexSurfaceMode.highSurfaceLowScaffold,
      blendLevel: state.highContrast ? 0 : 4,
      appBarStyle: FlexAppBarStyle.scaffoldBackground,
      appBarOpacity: 0.97,
      subThemesData: const FlexSubThemesData(
        blendOnLevel: 8,
        useTextTheme: true,
        useM2StyleDividerInM3: true,
        alignedDropdown: true,
        useInputDecoratorThemeInDialogs: true,
        inputDecoratorRadius: 12,
        inputDecoratorUnfocusedHasBorder: false,
        fabUseShape: true,
        fabRadius: 16,
        cardRadius: 12,
        bottomSheetRadius: 20,
        dialogRadius: 16,
        navigationBarSelectedLabelSchemeColor: SchemeColor.primary,
        navigationBarUnselectedLabelSchemeColor: SchemeColor.onSurface,
        navigationBarMutedUnselectedLabel: true,
        navigationBarSelectedIconSchemeColor: SchemeColor.onPrimary,
        navigationBarUnselectedIconSchemeColor: SchemeColor.onSurface,
        navigationBarMutedUnselectedIcon: true,
        navigationBarIndicatorSchemeColor: SchemeColor.primary,
        navigationBarIndicatorOpacity: 1,
        navigationBarElevation: 0,
        navigationBarBackgroundSchemeColor: SchemeColor.surface,
      ),
      keyColors: const FlexKeyColors(
        useSecondary: true,
        useTertiary: true,
        keepPrimary: true,
      ),
      tones: state.highContrast
          ? FlexTones.highContrast(Brightness.light)
          : FlexTones.material(Brightness.light),
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
      fontFamily: GoogleFonts.inter().fontFamily,
      textTheme: _buildTextTheme(state.fontScale, Brightness.light),
    );
  }

  /// Generates the Dark ThemeData based on the current global state.
  static ThemeData getDark(AeroThemeState state) {
    final primary = Color(state.accentColorValue != 0
        ? state.accentColorValue
        : _defaultAccent);
    final preset = presetFromAccentValue(state.accentColorValue);
    final secondary = preset != null ? preset.secondary : Color(_defaultSecondary);

    return FlexThemeData.dark(
      colors: FlexSchemeColor.from(
        primary: primary,
        secondary: secondary,
        brightness: Brightness.dark,
      ),
      surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
      blendLevel: state.highContrast ? 0 : 15,
      appBarStyle: FlexAppBarStyle.background,
      appBarOpacity: 0.90,
      subThemesData: const FlexSubThemesData(
        blendOnLevel: 20,
        useTextTheme: true,
        useM2StyleDividerInM3: true,
        alignedDropdown: true,
        useInputDecoratorThemeInDialogs: true,
        inputDecoratorRadius: 12,
        inputDecoratorUnfocusedHasBorder: false,
        fabUseShape: true,
        fabRadius: 16,
        cardRadius: 12,
        bottomSheetRadius: 20,
        dialogRadius: 16,
        navigationBarSelectedLabelSchemeColor: SchemeColor.primary,
        navigationBarUnselectedLabelSchemeColor: SchemeColor.onSurface,
        navigationBarMutedUnselectedLabel: true,
        navigationBarSelectedIconSchemeColor: SchemeColor.onPrimary,
        navigationBarUnselectedIconSchemeColor: SchemeColor.onSurface,
        navigationBarMutedUnselectedIcon: true,
        navigationBarIndicatorSchemeColor: SchemeColor.primary,
        navigationBarIndicatorOpacity: 1,
        navigationBarElevation: 0,
        navigationBarBackgroundSchemeColor: SchemeColor.surface,
      ),
      keyColors: const FlexKeyColors(
        useSecondary: true,
        useTertiary: true,
        keepPrimary: true,
      ),
      tones: state.highContrast
          ? FlexTones.highContrast(Brightness.dark)
          : FlexTones.vividSurfaces(Brightness.dark),
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
      fontFamily: GoogleFonts.inter().fontFamily,
      textTheme: _buildTextTheme(state.fontScale, Brightness.dark),
    );
  }

  /// Builds the text theme dynamically applying the user's font scale.
  static TextTheme _buildTextTheme(double scale, Brightness brightness) {
    final bodyFont = GoogleFonts.inter();
    final displayFont = GoogleFonts.outfit();

    // Light mode uses strong dark ink; dark mode uses white.
    final color = brightness == Brightness.dark
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF0D1117);
    final variantColor = brightness == Brightness.dark
        ? const Color(0xB3FFFFFF) // 70% white
        : const Color(0xFF4A5568); // Slate-600 — legible on white

    return TextTheme(
      // Display
      displayLarge:  displayFont.copyWith(fontSize: 57 * scale, fontWeight: FontWeight.w400, color: color),
      displayMedium: displayFont.copyWith(fontSize: 45 * scale, fontWeight: FontWeight.w400, color: color),
      displaySmall:  displayFont.copyWith(fontSize: 36 * scale, fontWeight: FontWeight.w400, color: color),

      // Headline
      headlineLarge:  displayFont.copyWith(fontSize: 32 * scale, fontWeight: FontWeight.w600, color: color),
      headlineMedium: displayFont.copyWith(fontSize: 28 * scale, fontWeight: FontWeight.w600, color: color),
      headlineSmall:  displayFont.copyWith(fontSize: 24 * scale, fontWeight: FontWeight.w600, color: color),

      // Title
      titleLarge:  bodyFont.copyWith(fontSize: 22 * scale, fontWeight: FontWeight.w600, color: color),
      titleMedium: bodyFont.copyWith(fontSize: 16 * scale, fontWeight: FontWeight.w600, color: color),
      titleSmall:  bodyFont.copyWith(fontSize: 14 * scale, fontWeight: FontWeight.w600, color: color),

      // Body
      bodyLarge:  bodyFont.copyWith(fontSize: 16 * scale, fontWeight: FontWeight.w400, color: color),
      bodyMedium: bodyFont.copyWith(fontSize: 14 * scale, fontWeight: FontWeight.w400, color: color),
      bodySmall:  bodyFont.copyWith(fontSize: 12 * scale, fontWeight: FontWeight.w400, color: variantColor),

      // Label
      labelLarge:  bodyFont.copyWith(fontSize: 14 * scale, fontWeight: FontWeight.w600, color: color),
      labelMedium: bodyFont.copyWith(fontSize: 12 * scale, fontWeight: FontWeight.w600, color: color),
      labelSmall:  bodyFont.copyWith(fontSize: 11 * scale, fontWeight: FontWeight.w600, color: variantColor),
    );
  }
}
