import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logger.dart';
import '../providers/repository_providers.dart';
import 'app_colors.dart';

class AeroThemeState {

  const AeroThemeState({
    required this.themeMode,
    required this.accentColorValue,
    required this.fontScale,
    required this.highContrast,
  });
  final ThemeMode themeMode;
  final int accentColorValue;
  final double fontScale;
  final bool highContrast;

  AeroThemeState copyWith({
    ThemeMode? themeMode,
    int? accentColorValue,
    double? fontScale,
    bool? highContrast,
  }) => AeroThemeState(
      themeMode: themeMode ?? this.themeMode,
      accentColorValue: accentColorValue ?? this.accentColorValue,
      fontScale: fontScale ?? this.fontScale,
      highContrast: highContrast ?? this.highContrast,
    );

  /// Value equality: Riverpod uses this to decide whether to notify listeners.
  /// Without this, every settings save triggers a MaterialApp rebuild even if
  /// no theme-relevant setting changed, resetting the navigation stack.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AeroThemeState &&
        other.themeMode == themeMode &&
        other.accentColorValue == accentColorValue &&
        other.fontScale == fontScale &&
        other.highContrast == highContrast;
  }

  @override
  int get hashCode => Object.hash(themeMode, accentColorValue, fontScale, highContrast);
}

class ThemeNotifier extends StateNotifier<AeroThemeState> {

  ThemeNotifier(this._ref) : super(const AeroThemeState(
    themeMode: ThemeMode.system,
    accentColorValue: 0xFF00B0FF, // default light blue accent
    fontScale: 1,
    highContrast: false,
  )) {
    _updateAppColors(ThemeMode.system);
    _loadTheme();
    PlatformDispatcher.instance.onPlatformBrightnessChanged = () {
      if (state.themeMode == ThemeMode.system) {
        _updateAppColors(ThemeMode.system);
        state = state.copyWith();
      }
    };
  }
  final Ref _ref;

  void _updateAppColors(ThemeMode mode) {
    if (mode == ThemeMode.system) {
      final brightness = PlatformDispatcher.instance.platformBrightness;
      AppColors.isDark = brightness == Brightness.dark;
    } else {
      AppColors.isDark = mode == ThemeMode.dark;
    }
  }

  Future<void> _loadTheme() async {
    try {
      final settings = _ref.read(settingsRepositoryProvider);
      
      // Load Mode
      final themeStr = await settings.getSetting('app_theme');
      ThemeMode mode = ThemeMode.system;
      if (themeStr == 'light') mode = ThemeMode.light;
      if (themeStr == 'dark') mode = ThemeMode.dark;

      // Load Accent
      final accentStr = await settings.getSetting('app_accent_color');
      var accentValue = 0xFF00B0FF;
      if (accentStr != null) {
        accentValue = int.tryParse(accentStr) ?? 0xFF00B0FF;
      }

      // Load Font Scale
      final scaleStr = await settings.getSetting('app_font_scale');
      var scale = 1.0;
      if (scaleStr != null) {
        scale = double.tryParse(scaleStr) ?? 1.0;
      }

      // Load Contrast
      final contrastStr = await settings.getSetting('app_high_contrast');
      final contrast = contrastStr == 'true';

      state = AeroThemeState(
        themeMode: mode,
        accentColorValue: accentValue,
        fontScale: scale,
        highContrast: contrast,
      );
      _updateAppColors(mode);
    } catch (e, s) {
      AppLogger.error('Failed to load theme from DB, using defaults', e, s);
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    _updateAppColors(mode);
    var themeStr = 'system';
    if (mode == ThemeMode.light) themeStr = 'light';
    if (mode == ThemeMode.dark) themeStr = 'dark';
    await _ref.read(settingsRepositoryProvider).setSetting('app_theme', themeStr);
  }

  Future<void> setAccentColor(Color color) async {
    state = state.copyWith(accentColorValue: color.toARGB32());
    await _ref.read(settingsRepositoryProvider).setSetting('app_accent_color', color.toARGB32().toString());
  }

  Future<void> setFontScale(double scale) async {
    state = state.copyWith(fontScale: scale);
    await _ref.read(settingsRepositoryProvider).setSetting('app_font_scale', scale.toString());
  }

  Future<void> setHighContrast(bool enabled) async {
    state = state.copyWith(highContrast: enabled);
    await _ref.read(settingsRepositoryProvider).setSetting('app_high_contrast', enabled.toString());
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, AeroThemeState>(
  ThemeNotifier.new,
  // keepAlive prevents unnecessary recreation when providers update, which
  // would itself trigger a spurious MaterialApp rebuild.
  name: 'themeProvider',
);
