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

/// AeroDrive Theme Extension for Soft-Tonic design tokens
class AeroThemeTokens extends ThemeExtension<AeroThemeTokens> {
  const AeroThemeTokens({
    required this.workspaceBackground,
    required this.cardBackground,
    required this.hoverPillBackground,
    required this.categoryImages,
    required this.categoryImagesBg,
    required this.categoryVideos,
    required this.categoryVideosBg,
    required this.categoryDocuments,
    required this.categoryDocumentsBg,
    required this.categoryAudio,
    required this.categoryAudioBg,
    required this.categoryOffline,
    required this.categoryOfflineBg,
  });

  final Color workspaceBackground;
  final Color cardBackground;
  final Color hoverPillBackground;
  final Color categoryImages;
  final Color categoryImagesBg;
  final Color categoryVideos;
  final Color categoryVideosBg;
  final Color categoryDocuments;
  final Color categoryDocumentsBg;
  final Color categoryAudio;
  final Color categoryAudioBg;
  final Color categoryOffline;
  final Color categoryOfflineBg;

  @override
  AeroThemeTokens copyWith({
    Color? workspaceBackground,
    Color? cardBackground,
    Color? hoverPillBackground,
    Color? categoryImages,
    Color? categoryImagesBg,
    Color? categoryVideos,
    Color? categoryVideosBg,
    Color? categoryDocuments,
    Color? categoryDocumentsBg,
    Color? categoryAudio,
    Color? categoryAudioBg,
    Color? categoryOffline,
    Color? categoryOfflineBg,
  }) => AeroThemeTokens(
    workspaceBackground: workspaceBackground ?? this.workspaceBackground,
    cardBackground: cardBackground ?? this.cardBackground,
    hoverPillBackground: hoverPillBackground ?? this.hoverPillBackground,
    categoryImages: categoryImages ?? this.categoryImages,
    categoryImagesBg: categoryImagesBg ?? this.categoryImagesBg,
    categoryVideos: categoryVideos ?? this.categoryVideos,
    categoryVideosBg: categoryVideosBg ?? this.categoryVideosBg,
    categoryDocuments: categoryDocuments ?? this.categoryDocuments,
    categoryDocumentsBg: categoryDocumentsBg ?? this.categoryDocumentsBg,
    categoryAudio: categoryAudio ?? this.categoryAudio,
    categoryAudioBg: categoryAudioBg ?? this.categoryAudioBg,
    categoryOffline: categoryOffline ?? this.categoryOffline,
    categoryOfflineBg: categoryOfflineBg ?? this.categoryOfflineBg,
  );

  @override
  AeroThemeTokens lerp(ThemeExtension<AeroThemeTokens>? other, double t) {
    if (other is! AeroThemeTokens) return this;
    return AeroThemeTokens(
      workspaceBackground: Color.lerp(workspaceBackground, other.workspaceBackground, t)!,
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
      hoverPillBackground: Color.lerp(hoverPillBackground, other.hoverPillBackground, t)!,
      categoryImages: Color.lerp(categoryImages, other.categoryImages, t)!,
      categoryImagesBg: Color.lerp(categoryImagesBg, other.categoryImagesBg, t)!,
      categoryVideos: Color.lerp(categoryVideos, other.categoryVideos, t)!,
      categoryVideosBg: Color.lerp(categoryVideosBg, other.categoryVideosBg, t)!,
      categoryDocuments: Color.lerp(categoryDocuments, other.categoryDocuments, t)!,
      categoryDocumentsBg: Color.lerp(categoryDocumentsBg, other.categoryDocumentsBg, t)!,
      categoryAudio: Color.lerp(categoryAudio, other.categoryAudio, t)!,
      categoryAudioBg: Color.lerp(categoryAudioBg, other.categoryAudioBg, t)!,
      categoryOffline: Color.lerp(categoryOffline, other.categoryOffline, t)!,
      categoryOfflineBg: Color.lerp(categoryOfflineBg, other.categoryOfflineBg, t)!,
    );
  }

  static const light = AeroThemeTokens(
    workspaceBackground: Color(0xFFF4F7FE),
    cardBackground: Color(0xFFFFFFFF),
    hoverPillBackground: Color(0xFFEEF2FF),
    categoryImages: Color(0xFF6366F1),
    categoryImagesBg: Color(0xFFEEF2FF),
    categoryVideos: Color(0xFFEF4444),
    categoryVideosBg: Color(0xFFFEF2F2),
    categoryDocuments: Color(0xFF0EA5E9),
    categoryDocumentsBg: Color(0xFFF0F9FF),
    categoryAudio: Color(0xFFF59E0B),
    categoryAudioBg: Color(0xFFFFFBEB),
    categoryOffline: Color(0xFF10B981),
    categoryOfflineBg: Color(0xFFECFDF5),
  );

  static const dark = AeroThemeTokens(
    workspaceBackground: Color(0xFF0B0F17),
    cardBackground: Color(0xFF151C28),
    hoverPillBackground: Color(0xFF1E293B),
    categoryImages: Color(0xFF6366F1),
    categoryImagesBg: Color(0xFF23254B),
    categoryVideos: Color(0xFFEF4444),
    categoryVideosBg: Color(0xFF451E24),
    categoryDocuments: Color(0xFF0EA5E9),
    categoryDocumentsBg: Color(0xFF153448),
    categoryAudio: Color(0xFFF59E0B),
    categoryAudioBg: Color(0xFF422E15),
    categoryOffline: Color(0xFF10B981),
    categoryOfflineBg: Color(0xFF13392E),
  );
}

/// AeroDrive dynamic theme generation using FlexColorScheme.
abstract final class AeroDriveTheme {

  static const int defaultAccent = 0xFF4F46E5; // Royal Indigo
  static const int defaultSecondary = 0xFF3B82F6; // Sky Blue

  /// Curated theme presets for AeroDrive.
  static const List<AeroThemePreset> presets = [
    // ── Primary Theme Preset (Default) ─────────────────────────────
    AeroThemePreset(
      name: 'Soft-Tonic Indigo',
      primary: Color(0xFF4F46E5),
      secondary: Color(0xFF3B82F6),
      icon: Icons.cloud_outlined,
      gradient: [Color(0xFF4F46E5), Color(0xFF3B82F6)],
    ),
    AeroThemePreset(
      name: 'Google Blue',
      primary: Color(0xFF1A73E8),
      secondary: Color(0xFF4285F4),
      icon: Icons.cloud,
      gradient: [Color(0xFF1A73E8), Color(0xFF4285F4)],
    ),
    AeroThemePreset(
      name: 'Electric Violet',
      primary: Color(0xFF7C3AED),
      secondary: Color(0xFFEC4899),
      icon: Icons.auto_awesome,
      gradient: [Color(0xFF7C3AED), Color(0xFFEC4899)],
    ),
    AeroThemePreset(
      name: 'Neon Cyan',
      primary: Color(0xFF00E5FF),
      secondary: Color(0xFF7C3AED),
      icon: Icons.bolt,
      gradient: [Color(0xFF00E5FF), Color(0xFF7C3AED)],
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
        : defaultAccent);
    final preset = presetFromAccentValue(state.accentColorValue);
    final secondary = preset != null ? preset.secondary : const Color(defaultSecondary);

    final baseTheme = FlexThemeData.light(
      colors: FlexSchemeColor.from(
        primary: primary,
        secondary: secondary,
        brightness: Brightness.light,
      ),
      scaffoldBackground: const Color(0xFFF4F7FE),
      surfaceMode: FlexSurfaceMode.highSurfaceLowScaffold,
      blendLevel: state.highContrast ? 0 : 2,
      appBarStyle: FlexAppBarStyle.scaffoldBackground,
      appBarOpacity: 0.98,
      subThemesData: const FlexSubThemesData(
        blendOnLevel: 4,
        useTextTheme: true,
        useM2StyleDividerInM3: true,
        alignedDropdown: true,
        useInputDecoratorThemeInDialogs: true,
        inputDecoratorRadius: 14,
        inputDecoratorUnfocusedHasBorder: false,
        fabUseShape: true,
        fabRadius: 16,
        cardRadius: 16,
        bottomSheetRadius: 28,
        dialogRadius: 20,
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

    return baseTheme.copyWith(
      scaffoldBackgroundColor: const Color(0xFFF4F7FE),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shadowColor: const Color(0x0A000000),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      extensions: [AeroThemeTokens.light],
    );
  }

  /// Generates the Dark ThemeData based on the current global state.
  static ThemeData getDark(AeroThemeState state) {
    final primary = Color(state.accentColorValue != 0
        ? state.accentColorValue
        : defaultAccent);
    final preset = presetFromAccentValue(state.accentColorValue);
    final secondary = preset != null ? preset.secondary : const Color(defaultSecondary);

    final baseTheme = FlexThemeData.dark(
      colors: FlexSchemeColor.from(
        primary: primary,
        secondary: secondary,
        brightness: Brightness.dark,
      ),
      scaffoldBackground: const Color(0xFF0B0F17),
      surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
      blendLevel: state.highContrast ? 0 : 8,
      appBarStyle: FlexAppBarStyle.background,
      appBarOpacity: 0.90,
      subThemesData: const FlexSubThemesData(
        blendOnLevel: 10,
        useTextTheme: true,
        useM2StyleDividerInM3: true,
        alignedDropdown: true,
        useInputDecoratorThemeInDialogs: true,
        inputDecoratorRadius: 14,
        inputDecoratorUnfocusedHasBorder: false,
        fabUseShape: true,
        fabRadius: 16,
        cardRadius: 16,
        bottomSheetRadius: 28,
        dialogRadius: 20,
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

    return baseTheme.copyWith(
      scaffoldBackgroundColor: const Color(0xFF0B0F17),
      cardTheme: CardThemeData(
        color: const Color(0xFF151C28),
        elevation: 0,
        shadowColor: const Color(0x40000000),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF151C28),
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      extensions: [AeroThemeTokens.dark],
    );
  }

  /// Builds the text theme dynamically applying the user's font scale.
  static TextTheme _buildTextTheme(double scale, Brightness brightness) {
    final bodyFont = GoogleFonts.inter();
    final displayFont = GoogleFonts.outfit();

    // High-contrast slate 900 for Light mode, pure white for Dark mode.
    final color = brightness == Brightness.dark
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF0F172A);
    final variantColor = brightness == Brightness.dark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B); // Slate-500

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
