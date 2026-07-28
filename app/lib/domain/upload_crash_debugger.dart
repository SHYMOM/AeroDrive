import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Writes upload pipeline events to a persistent log file in real time.
///
/// ## Why this approach
///
/// When Android kills a process (e.g. OOM), **zero Dart code runs**. No try/catch,
/// no PlatformDispatcher.onError, no runZonedGuarded. The process is simply gone.
///
/// The only way to capture an OOM crash is to write log data **before** the crash
/// happens: every stage transition, chunk upload, and error is flushed to disk
/// immediately. After a crash, the next app launch reads the leftover log file
/// and surfaces it to the user.
///
/// ## File location
///   Primary: App documents/AeroDrive/logs/  (always writable on Android)
///   Fallback: Downloads/AeroDrive/logs/     (visible to user, may fail on scoped storage)
///   Final: debugPrint only                  (visible in adb logcat)
///
/// Two file types:
///   - active_upload.log — the current/recent upload's live log
///   - crash_<ts>.log    — renamed from active_upload.log when a crash is detected
class UploadFileLogger {
  UploadFileLogger._();
  static final UploadFileLogger instance = UploadFileLogger._();

  File? _logFile;
  IOSink? _sink;
  String _currentFileName = '';
  String _logPath = '';
  bool _finishedGracefully = false;
  bool _fileIoFailed = false;
  bool _flushPending = false;
  Timer? _autoFlushTimer;

  // ── Public API ──

  /// Start logging for a new upload. Opens a file and writes the header.
  /// Falls back to debugPrint-only mode if file I/O fails.
  Future<void> startUpload(String fileId, String fileName, int fileSize) async {
    _currentFileName = fileName;
    _finishedGracefully = false;
    _fileIoFailed = false;

    // Close any previous dangling sink
    await _closeSink();

    // Try primary directory first (app documents — always writable),
    // then visible fallback, then system temp.
    Directory? dir;
    try {
      final ad = await getApplicationDocumentsDirectory();
      dir = Directory('${ad.path}${Platform.pathSeparator}AeroDrive${Platform.pathSeparator}logs');
    } catch (_) {}
    if (dir == null || !await _ensureDir(dir)) {
      try {
        final dd = await getDownloadsDirectory();
        if (dd != null) {
          dir = Directory('${dd.path}${Platform.pathSeparator}AeroDrive${Platform.pathSeparator}logs');
        }
      } catch (_) {}
    }
    if (dir == null || !await _ensureDir(dir)) {
      dir = Directory.systemTemp;
    }

    _logPath = '${dir.path}${Platform.pathSeparator}active_upload.log';
    _logFile = File(_logPath);
    try {
      _sink = _logFile!.openWrite(mode: FileMode.writeOnly);
    } catch (e) {
      _fileIoFailed = true;
      _sink = null;
      debugPrint('[UploadFileLogger] Failed to open log file at $_logPath: $e');
    }

    if (!_fileIoFailed) {
      _writeln('=== AeroDrive Upload Live Log ===');
      _writeln('Started: ${_now()}');
      _writeln('App Version: 0.1.0-alpha.1');
      _writeln('');
      _writeln('--- Upload Info ---');
      _writeln('File: $fileName');
      _writeln('Size: $fileSize bytes');
      _writeln('File ID: $fileId');
      _writeln('Log path: $_logPath');
      _writeln('');
      await _flush();
    }

    debugPrint('[UploadFileLogger] Started logging for $fileName -> $_logPath');

    // Start auto-flush timer so we don't need to flush after every write
    _autoFlushTimer?.cancel();
    _autoFlushTimer = Timer.periodic(const Duration(seconds: 2), (_) => _flush());
  }

  /// Log a stage transition.
  void logStage(String stage) {
    final msg = '[${_now()}] STAGE: $stage';
    _writeln(msg);
    debugPrint('[UploadFileLogger] $msg');
  }

  /// Log batch progress.
  void logBatch(int batch, int total) {
    final msg = '[${_now()}] BATCH: $batch/$total';
    _writeln(msg);
    debugPrint('[UploadFileLogger] $msg');
  }

  /// Log chunk progress.
  void logChunk(int chunk, int total) {
    final msg = '[${_now()}] CHUNK: $chunk/$total';
    _writeln(msg);
  }

  /// Log bytes encrypted so far.
  void logBytes(int bytes) {
    final msg = '[${_now()}] BYTES_ENCRYPTED: $bytes';
    _writeln(msg);
  }

  /// Log an error with optional stack trace.
  void logError(String context, String message, [String? stack]) {
    final msg = '[${_now()}] ERROR: $context: $message';
    _writeln(msg);
    debugPrint('[UploadFileLogger] ERROR: $context: $message');
    if (stack != null) {
      final lines = stack.split('\n');
      for (var i = 0; i < lines.length && i < 5; i++) {
        _writeln('  ${lines[i]}');
      }
    }
  }

  /// Log a TDLib event.
  void logTdlibEvent(String eventType) {
    final msg = '[${_now()}] TDLIB: $eventType';
    _writeln(msg);
  }

  /// Log a general info message.
  void logInfo(String message) {
    final msg = '[${_now()}] INFO: $message';
    _writeln(msg);
    debugPrint('[UploadFileLogger] INFO: $message');
  }

  /// Mark the upload as finished successfully.
  Future<void> finishUpload() async {
    _finishedGracefully = true;
    final msg = '[${_now()}] UPLOAD_COMPLETE: $_currentFileName';
    _writeln(msg);
    debugPrint('[UploadFileLogger] $msg');
    _writeln('--- End of log ---');
    await _closeSink();

    // Rename active -> finished so it doesn't get picked up as a crash
    await _renameActiveLog('ok_${DateTime.now().millisecondsSinceEpoch}.log');
  }

  /// Close the logger (called on dispose).
  Future<void> dispose() async {
    if (!_finishedGracefully && _logFile != null) {
      final msg = '[${_now()}] UPLOAD_INTERRUPTED: log ended abruptly';
      _writeln(msg);
      debugPrint('[UploadFileLogger] $msg');
    }
    await _closeSink();
  }

  // ── Crash detection (called on next app start) ──

  /// Checks if a previous upload crashed by looking for active_upload.log.
  /// Returns the log content if found (and renames it to crash_<ts>.log).
  static Future<String?> detectCrashedUpload() async {
    try {
      final dir = await _getLogDir();
      if (dir == null) return null;

      final activeFile = File('${dir.path}${Platform.pathSeparator}active_upload.log');
      if (!await activeFile.exists()) return null;

      final content = await activeFile.readAsString();

      // Rename to crash log so it doesn't get picked up again
      final ts = DateTime.now().millisecondsSinceEpoch;
      final crashPath = '${dir.path}${Platform.pathSeparator}crash_$ts.log';
      await activeFile.rename(crashPath);

      // Also delete old "ok_" logs older than 7 days
      try {
        final entries = dir.listSync();
        final cutoff = DateTime.now().subtract(const Duration(days: 7));
        for (final entry in entries) {
          if (entry is File && entry.path.endsWith('.log')) {
            final stat = entry.statSync();
            if (stat.modified.isBefore(cutoff)) {
              entry.deleteSync();
            }
          }
        }
      } catch (_) {}

      return content;
    } catch (e) {
      debugPrint('[UploadFileLogger] Crash detection error: $e');
      return null;
    }
  }

  /// Returns the log directory path for external access.
  static Future<String?> getLogDirectoryPath() async {
    try {
      final ad = await getApplicationDocumentsDirectory();
      final dir = Directory('${ad.path}${Platform.pathSeparator}AeroDrive${Platform.pathSeparator}logs');
      if (await dir.exists()) return dir.path;
    } catch (_) {}
    try {
      final dd = await getDownloadsDirectory();
      if (dd != null) {
        final dir = Directory('${dd.path}${Platform.pathSeparator}AeroDrive${Platform.pathSeparator}logs');
        if (await dir.exists()) return dir.path;
      }
    } catch (_) {}
    return null;
  }

  // ── Internal ──

  void _writeln(String line) {
    if (_fileIoFailed) return;
    try {
      _sink?.writeln(line);
    } catch (e) {
      _fileIoFailed = true;
      if (_sink != null) {
        try { _sink!.close(); } catch (_) {}
        _sink = null;
      }
      debugPrint('[UploadFileLogger] _writeln failed, disabled: $e');
    }
  }

  Future<void> _flush() async {
    if (_fileIoFailed || _flushPending) return;
    _flushPending = true;
    try {
      await _sink?.flush();
    } catch (e) {
      _fileIoFailed = true;
      if (_sink != null) {
        try { await _sink!.close(); } catch (_) {}
        _sink = null;
      }
      debugPrint('[UploadFileLogger] _flush failed, disabled: $e');
    } finally {
      _flushPending = false;
    }
  }

  Future<void> _closeSink() async {
    _autoFlushTimer?.cancel();
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {}
    _sink = null;
  }

  Future<void> _renameActiveLog(String newName) async {
    try {
      if (_logFile != null && await _logFile!.exists()) {
        final dir = _logFile!.parent;
        final newPath = '${dir.path}${Platform.pathSeparator}$newName';
        await _logFile!.rename(newPath);
      }
    } catch (_) {}
    _logFile = null;
  }

  /// Ensures [dir] exists. Returns true on success, false if creation failed.
  static Future<bool> _ensureDir(Directory dir) async {
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return true;
    } catch (e) {
      debugPrint('[UploadFileLogger] Failed to create dir ${dir.path}: $e');
      return false;
    }
  }

  static Future<Directory?> _getLogDir() async {
    // Primary: app documents — always writable on Android
    try {
      final ad = await getApplicationDocumentsDirectory();
      final dir = Directory('${ad.path}${Platform.pathSeparator}AeroDrive${Platform.pathSeparator}logs');
      if (await dir.exists()) return dir;
    } catch (_) {}
    // Fallback: Downloads — visible to user
    try {
      final dd = await getDownloadsDirectory();
      if (dd != null) {
        final dir = Directory('${dd.path}${Platform.pathSeparator}AeroDrive${Platform.pathSeparator}logs');
        if (await dir.exists()) return dir;
      }
    } catch (_) {}
    return null;
  }

  static String _now() => DateTime.now().toIso8601String();
}
