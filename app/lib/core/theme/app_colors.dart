import 'package:flutter/material.dart';

/// AeroDrive design-system color tokens.
///
/// All colors used across the app should reference these constants
/// rather than using raw hex values inline.
abstract final class AppColors {
  // ── Background & Surface ──────────────────────────────────────────
  /// Deep space blue — primary background.
  static const Color background = Color(0xFF0B0C24);

  /// Slightly lighter surface for cards and panels.
  static const Color surface = Color(0xFF12132B);

  /// Elevated surface for modals and dialogs.
  static const Color surfaceElevated = Color(0xFF1A1B3A);

  /// Surface variant for subtle differentiation.
  static const Color surfaceVariant = Color(0xFF1E1F42);

  // ── Primary — Electric Violet ─────────────────────────────────────
  static const Color primary = Color(0xFF7C3AED);
  static const Color primaryLight = Color(0xFF8B5CF6);
  static const Color primaryDark = Color(0xFF6D28D9);
  static const Color primaryContainer = Color(0xFF2E1065);

  // ── Secondary — Electric Cyan ─────────────────────────────────────
  static const Color secondary = Color(0xFF06B6D4);
  static const Color secondaryLight = Color(0xFF22D3EE);
  static const Color secondaryDark = Color(0xFF0891B2);
  static const Color secondaryContainer = Color(0xFF083344);

  // ── Accent / Tertiary — Neon Pink ─────────────────────────────────
  static const Color tertiary = Color(0xFFEC4899);
  static const Color tertiaryLight = Color(0xFFF472B6);
  static const Color tertiaryContainer = Color(0xFF4A0D2E);

  // ── Semantic ──────────────────────────────────────────────────────
  static const Color error = Color(0xFFEF4444);
  static const Color errorContainer = Color(0xFF450A0A);
  static const Color success = Color(0xFF10B981);
  static const Color successContainer = Color(0xFF052E16);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningContainer = Color(0xFF451A03);

  // ── Text & Icons ──────────────────────────────────────────────────
  static const Color onBackground = Color(0xFFE2E8F0);
  static const Color onSurface = Color(0xFFE2E8F0);
  static const Color onSurfaceVariant = Color(0xFF94A3B8);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color onError = Color(0xFFFFFFFF);

  // ── Borders & Dividers ────────────────────────────────────────────
  static const Color outline = Color(0xFF2D2E55);
  static const Color outlineVariant = Color(0xFF1E1F42);

  // ── Misc ──────────────────────────────────────────────────────────
  static const Color scrim = Color(0xCC000000);
  static const Color shadow = Color(0xFF000000);

  // ── File-type icon colors ─────────────────────────────────────────
  static const Color fileFolder = Color(0xFFFBBF24);
  static const Color fileImage = Color(0xFF34D399);
  static const Color fileVideo = Color(0xFFF472B6);
  static const Color fileAudio = Color(0xFF818CF8);
  static const Color fileDocument = Color(0xFF60A5FA);
  static const Color fileArchive = Color(0xFFFB923C);
  static const Color fileCode = Color(0xFF2DD4BF);
  static const Color fileEncrypted = Color(0xFFA78BFA);
  static const Color fileUnknown = Color(0xFF64748B);
}
