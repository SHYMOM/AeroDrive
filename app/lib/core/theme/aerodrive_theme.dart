import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'theme_provider.dart';

/// AeroDrive dynamic theme generation using FlexColorScheme.
abstract final class AeroDriveTheme {
  
  /// Generates the Light ThemeData based on the current global state.
  static ThemeData getLight(AeroThemeState state) {
    return FlexThemeData.light(
      colors: FlexSchemeColor.from(
        primary: Color(state.accentColorValue),
        brightness: Brightness.light,
      ),
      surfaceMode: FlexSurfaceMode.highSurfaceLowScaffold,
      blendLevel: state.highContrast ? 0 : 5,
      appBarStyle: FlexAppBarStyle.scaffoldBackground,
      appBarOpacity: 0.95,
      subThemesData: const FlexSubThemesData(
        blendOnLevel: 10,
        blendOnColors: false,
        useTextTheme: true,
        useM2StyleDividerInM3: true,
        alignedDropdown: true,
        useInputDecoratorThemeInDialogs: true,
        inputDecoratorRadius: 16.0,
        inputDecoratorUnfocusedHasBorder: false,
        fabUseShape: true,
        fabRadius: 20.0,
        cardRadius: 24.0,
        bottomSheetRadius: 32.0,
        dialogRadius: 28.0,
        navigationBarSelectedLabelSchemeColor: SchemeColor.primary,
        navigationBarUnselectedLabelSchemeColor: SchemeColor.onSurface,
        navigationBarMutedUnselectedLabel: true,
        navigationBarSelectedIconSchemeColor: SchemeColor.onPrimary,
        navigationBarUnselectedIconSchemeColor: SchemeColor.onSurface,
        navigationBarMutedUnselectedIcon: true,
        navigationBarIndicatorSchemeColor: SchemeColor.primary,
        navigationBarIndicatorOpacity: 1.00,
        navigationBarElevation: 0.0,
        navigationBarBackgroundSchemeColor: SchemeColor.surface,
      ),
      keyColors: const FlexKeyColors(
        useSecondary: true,
        useTertiary: true,
        keepPrimary: true,
      ),
      tones: state.highContrast ? FlexTones.highContrast(Brightness.light) : FlexTones.material(Brightness.light),
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
      useMaterial3: true,
      fontFamily: GoogleFonts.inter().fontFamily,
      textTheme: _buildTextTheme(state.fontScale, Brightness.light),
    );
  }

  /// Generates the Dark ThemeData based on the current global state.
  static ThemeData getDark(AeroThemeState state) {
    return FlexThemeData.dark(
      colors: FlexSchemeColor.from(
        primary: Color(state.accentColorValue),
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
        inputDecoratorRadius: 16.0,
        inputDecoratorUnfocusedHasBorder: false,
        fabUseShape: true,
        fabRadius: 20.0,
        cardRadius: 24.0,
        bottomSheetRadius: 32.0,
        dialogRadius: 28.0,
        navigationBarSelectedLabelSchemeColor: SchemeColor.primary,
        navigationBarUnselectedLabelSchemeColor: SchemeColor.onSurface,
        navigationBarMutedUnselectedLabel: true,
        navigationBarSelectedIconSchemeColor: SchemeColor.onPrimary,
        navigationBarUnselectedIconSchemeColor: SchemeColor.onSurface,
        navigationBarMutedUnselectedIcon: true,
        navigationBarIndicatorSchemeColor: SchemeColor.primary,
        navigationBarIndicatorOpacity: 1.00,
        navigationBarElevation: 0.0,
        navigationBarBackgroundSchemeColor: SchemeColor.surface,
      ),
      keyColors: const FlexKeyColors(
        useSecondary: true,
        useTertiary: true,
        keepPrimary: true,
      ),
      tones: state.highContrast ? FlexTones.highContrast(Brightness.dark) : FlexTones.vividSurfaces(Brightness.dark),
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
      useMaterial3: true,
      fontFamily: GoogleFonts.inter().fontFamily,
      textTheme: _buildTextTheme(state.fontScale, Brightness.dark),
    );
  }

  /// Builds the text theme dynamically applying the user's font scale.
  static TextTheme _buildTextTheme(double scale, Brightness brightness) {
    final bodyFont = GoogleFonts.inter();
    final displayFont = GoogleFonts.outfit();
    final color = brightness == Brightness.dark ? Colors.white : Colors.black87;
    final variantColor = brightness == Brightness.dark ? Colors.white70 : Colors.black54;

    return TextTheme(
      // Display
      displayLarge: displayFont.copyWith(fontSize: 57 * scale, fontWeight: FontWeight.w400, color: color),
      displayMedium: displayFont.copyWith(fontSize: 45 * scale, fontWeight: FontWeight.w400, color: color),
      displaySmall: displayFont.copyWith(fontSize: 36 * scale, fontWeight: FontWeight.w400, color: color),

      // Headline
      headlineLarge: displayFont.copyWith(fontSize: 32 * scale, fontWeight: FontWeight.w600, color: color),
      headlineMedium: displayFont.copyWith(fontSize: 28 * scale, fontWeight: FontWeight.w600, color: color),
      headlineSmall: displayFont.copyWith(fontSize: 24 * scale, fontWeight: FontWeight.w600, color: color),

      // Title
      titleLarge: bodyFont.copyWith(fontSize: 22 * scale, fontWeight: FontWeight.w600, color: color),
      titleMedium: bodyFont.copyWith(fontSize: 16 * scale, fontWeight: FontWeight.w600, color: color),
      titleSmall: bodyFont.copyWith(fontSize: 14 * scale, fontWeight: FontWeight.w600, color: color),

      // Body
      bodyLarge: bodyFont.copyWith(fontSize: 16 * scale, fontWeight: FontWeight.w400, color: color),
      bodyMedium: bodyFont.copyWith(fontSize: 14 * scale, fontWeight: FontWeight.w400, color: color),
      bodySmall: bodyFont.copyWith(fontSize: 12 * scale, fontWeight: FontWeight.w400, color: variantColor),

      // Label
      labelLarge: bodyFont.copyWith(fontSize: 14 * scale, fontWeight: FontWeight.w600, color: color),
      labelMedium: bodyFont.copyWith(fontSize: 12 * scale, fontWeight: FontWeight.w600, color: color),
      labelSmall: bodyFont.copyWith(fontSize: 11 * scale, fontWeight: FontWeight.w600, color: variantColor),
    );
  }
}
