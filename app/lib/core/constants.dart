/// App-wide constants for AeroDrive.
///
/// Centralizes magic numbers and configuration values so they can be
/// changed in one place and referenced consistently.
abstract final class AppConstants {
  // ── App Info ──────────────────────────────────────────────────────
  static const String appName = 'AeroDrive';
  static const String appVersion = '0.1.0-alpha.1';

  // ── Chunking ──────────────────────────────────────────────────────
  /// Maximum size per chunk uploaded to Telegram (1.5 GB).
  static const int maxChunkSizeBytes = 1536 * 1024 * 1024; // 1.5 GB

  /// Default number of concurrent chunk upload workers.
  static const int maxConcurrentUploads = 4;

  // ── Trash ─────────────────────────────────────────────────────────
  /// Days before trashed items are permanently purged.
  static const int trashRetentionDays = 30;

  // ── Responsive Breakpoints ────────────────────────────────────────
  /// Below this width: mobile layout (bottom navigation bar).
  static const double mobileBreakpoint = 600;

  /// At or above this width: desktop layout (persistent sidebar).
  static const double desktopBreakpoint = 1024;

  // ── Crypto ────────────────────────────────────────────────────────
  /// AES-256-GCM nonce size in bytes.
  static const int gcmNonceBytes = 12;

  /// Argon2id parameters (OWASP 2023 recommendations).
  static const int argon2Memory = 65536; // 64 MB
  static const int argon2Iterations = 3;
  static const int argon2Parallelism = 4;

  // ── Network / Telegram ────────────────────────────────────────────
  /// Base flood-wait backoff in milliseconds.
  static const int floodWaitBaseMs = 1000;

  /// Maximum retry attempts for a failed chunk upload.
  static const int maxUploadRetries = 5;

  // ── UI ────────────────────────────────────────────────────────────
  /// Animation durations.
  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animNormal = Duration(milliseconds: 300);
  static const Duration animSlow = Duration(milliseconds: 500);

  /// Corner radii.
  static const double radiusSmall = 8;
  static const double radiusMedium = 12;
  static const double radiusLarge = 16;
  static const double radiusXLarge = 20;
}
