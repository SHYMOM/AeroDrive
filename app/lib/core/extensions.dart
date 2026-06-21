/// Common extension methods used across AeroDrive.
library;

/// File-size formatting for [int] byte counts.
extension FileSizeExtension on int {
  /// Formats bytes into a human-readable string (e.g. "1.5 GB").
  String get readableFileSize {
    if (this < 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    int unitIndex = 0;
    double size = toDouble();
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return '${size.toStringAsFixed(unitIndex == 0 ? 0 : 1)} ${units[unitIndex]}';
  }
}

/// Relative-time formatting for [DateTime].
extension RelativeTimeExtension on DateTime {
  /// Returns a human-readable relative time string (e.g. "2 hours ago").
  String get relativeTime {
    final now = DateTime.now();
    final diff = now.difference(this);

    if (diff.isNegative) return 'just now';
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }
}

/// String truncation helper.
extension TruncateExtension on String {
  /// Truncates to [maxLength] characters, appending [ellipsis] if truncated.
  String truncate(int maxLength, {String ellipsis = '…'}) {
    if (length <= maxLength) return this;
    return '${substring(0, maxLength - ellipsis.length)}$ellipsis';
  }
}
