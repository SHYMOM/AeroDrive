import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';

class AeroThemeState {
  final ThemeMode themeMode;
  final int accentColorValue;
  final double fontScale;
  final bool highContrast;

  const AeroThemeState({
    required this.themeMode,
    required this.accentColorValue,
    required this.fontScale,
    required this.highContrast,
  });

  AeroThemeState copyWith({
    ThemeMode? themeMode,
    int? accentColorValue,
    double? fontScale,
    bool? highContrast,
  }) {
    return AeroThemeState(
      themeMode: themeMode ?? this.themeMode,
      accentColorValue: accentColorValue ?? this.accentColorValue,
      fontScale: fontScale ?? this.fontScale,
      highContrast: highContrast ?? this.highContrast,
    );
  }
}

class ThemeNotifier extends StateNotifier<AeroThemeState> {
  final Ref _ref;

  ThemeNotifier(this._ref) : super(const AeroThemeState(
    themeMode: ThemeMode.system,
    accentColorValue: 0xFF00B0FF, // default light blue accent
    fontScale: 1.0,
    highContrast: false,
  )) {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final settings = _ref.read(settingsRepositoryProvider);
    
    // Load Mode
    final themeStr = await settings.getSetting('app_theme');
    ThemeMode mode = ThemeMode.system;
    if (themeStr == 'light') mode = ThemeMode.light;
    if (themeStr == 'dark') mode = ThemeMode.dark;

    // Load Accent
    final accentStr = await settings.getSetting('app_accent_color');
    int accentValue = 0xFF00B0FF;
    if (accentStr != null) {
      accentValue = int.tryParse(accentStr) ?? 0xFF00B0FF;
    }

    // Load Font Scale
    final scaleStr = await settings.getSetting('app_font_scale');
    double scale = 1.0;
    if (scaleStr != null) {
      scale = double.tryParse(scaleStr) ?? 1.0;
    }

    // Load Contrast
    final contrastStr = await settings.getSetting('app_high_contrast');
    bool contrast = contrastStr == 'true';

    state = AeroThemeState(
      themeMode: mode,
      accentColorValue: accentValue,
      fontScale: scale,
      highContrast: contrast,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    String themeStr = 'system';
    if (mode == ThemeMode.light) themeStr = 'light';
    if (mode == ThemeMode.dark) themeStr = 'dark';
    await _ref.read(settingsRepositoryProvider).setSetting('app_theme', themeStr);
  }

  Future<void> setAccentColor(Color color) async {
    state = state.copyWith(accentColorValue: color.value);
    await _ref.read(settingsRepositoryProvider).setSetting('app_accent_color', color.value.toString());
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

final themeProvider = StateNotifierProvider<ThemeNotifier, AeroThemeState>((ref) {
  return ThemeNotifier(ref);
});
