/// Sealed error hierarchy for AeroDrive.
///
/// Every I/O boundary (network, disk, FFI, crypto) should produce
/// one of these typed errors rather than throwing raw exceptions.
sealed class AppError implements Exception {
  const AppError(this.message, [this.cause]);

  /// Human-readable description of what went wrong.
  final String message;

  /// The underlying exception/error, if any.
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message'
      '${cause != null ? ' (caused by: $cause)' : ''}';
}

/// Network-related errors (connectivity, timeouts, HTTP failures).
final class NetworkError extends AppError {
  const NetworkError(super.message, [super.cause]);
}

/// Cryptographic operation failures (encrypt, decrypt, key derivation).
final class CryptoError extends AppError {
  const CryptoError(super.message, [super.cause]);
}

/// Telegram API / TDLib errors (auth failures, flood waits, etc.).
final class TelegramError extends AppError {
  const TelegramError(
    String message, {
    Object? cause,
    this.floodWaitSeconds,
  }) : super(message, cause);

  /// If this is a flood-wait error, how long Telegram wants us to wait.
  final int? floodWaitSeconds;
}

/// Local storage / database errors (Drift, file system).
final class StorageError extends AppError {
  const StorageError(super.message, [super.cause]);
}

/// Authentication errors (invalid OTP, session expired, 2FA failure).
final class AuthError extends AppError {
  const AuthError(super.message, [super.cause]);
}

/// File operation errors (chunking, hashing, read/write).
final class FileOperationError extends AppError {
  const FileOperationError(super.message, [super.cause]);
}
