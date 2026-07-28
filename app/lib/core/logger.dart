import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Centralized diagnostic logging utility for AeroDrive.
///
/// Buffers logs in memory and supports saving/loading crash reports
/// to/from the local file system.
abstract final class AppLogger {
  static const int _maxLogs = 1000;
  static final List<String> _logs = [];

  /// Returns a read-only list of the current log buffer.
  static List<String> get logs => List.unmodifiable(_logs);

  /// Initializes the logger, intercepting all [debugPrint] and standard log output.
  static void init() {
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) {
        _addLog(message);
      }
      originalDebugPrint(message, wrapWidth: wrapWidth);
    };
  }

  /// Adds a raw log line with a timestamp.
  static void _addLog(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final cleanMessage = message.trim();
    if (cleanMessage.isEmpty) return;

    _logs.add('[$timestamp] $cleanMessage');
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }
  }

  /// Logs a standard info message.
  static void info(String message) {
    debugPrint('[INFO] $message');
  }

  /// Logs a warning message.
  static void warning(String message) {
    debugPrint('[WARNING] $message');
  }

  /// Logs an error with details and an optional stack trace.
  static void error(String message, [Object? error, StackTrace? stack]) {
    final errorString = error != null ? '\nError: $error' : '';
    final stackString = stack != null ? '\nStack: $stack' : '';
    _addLog('[ERROR] $message$errorString$stackString');
    debugPrint('[ERROR] $message$errorString$stackString');
  }

  /// Returns the path to the crash log file.
  static Future<File> get _logFile async {
    final directory = await getTemporaryDirectory();
    return File('${directory.path}/crash_log.txt');
  }

  /// Persists the current log buffer along with error details to a local crash file.
  static Future<void> saveCrashLog(Object error, StackTrace stack) async {
    try {
      final file = await _logFile;
      final buffer = StringBuffer();
      buffer.writeln('=== AERO DRIVE CRITICAL ERROR ===');
      buffer.writeln('Timestamp: ${DateTime.now().toIso8601String()}');
      buffer.writeln('Exception: $error');
      buffer.writeln('Stack Trace:');
      buffer.writeln(stack.toString());
      buffer.writeln('\n=== APPLICATION LOG BUFFER ===');
      for (final log in _logs) {
        buffer.writeln(log);
      }
      await file.writeAsString(buffer.toString());

      // ALSO save to the public Download/AeroDrive/logs/ folder so users can
      // access the crash report via file manager or USB.
      await _saveToPublicLogs(error, stack);
    } catch (e) {
      // Direct console write in case file write fails
      stderr.writeln('[AppLogger] Failed to write crash log: $e');
    }
  }

  /// Saves a crash report to the public Downloads/AeroDrive/logs/ directory.
  /// This is the location the user can easily find and share.
  static Future<String> _saveToPublicLogs(Object error, StackTrace stack) async {
    try {
      Directory logDir;
      if (Platform.isAndroid) {
        logDir = Directory('/storage/emulated/0/Download/AeroDrive/logs');
      } else {
        final downloadDir = await getDownloadsDirectory();
        if (downloadDir != null) {
          logDir = Directory('${downloadDir.path}${Platform.pathSeparator}AeroDrive${Platform.pathSeparator}logs');
        } else {
          final appDir = await getApplicationDocumentsDirectory();
          logDir = Directory('${appDir.path}${Platform.pathSeparator}AeroDrive${Platform.pathSeparator}logs');
        }
      }

      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${logDir.path}${Platform.pathSeparator}crash_$timestamp.log';

      final buffer = StringBuffer();
      buffer.writeln('=== AERO DRIVE CRASH REPORT ===');
      buffer.writeln('Timestamp: ${DateTime.now().toIso8601String()}');
      buffer.writeln('');
      buffer.writeln('Exception: $error');
      buffer.writeln('');
      buffer.writeln('Stack Trace:');
      buffer.writeln(stack.toString());
      buffer.writeln('');
      buffer.writeln('=== APPLICATION LOG BUFFER ===');
      for (final log in _logs) {
        buffer.writeln(log);
      }

      await File(filePath).writeAsString(buffer.toString());
      debugPrint('[AppLogger] Crash report saved to public logs: $filePath');
      return filePath;
    } catch (e) {
      // Write to stderr so it shows up in logcat / debug console
      stderr.writeln('[AppLogger] Failed to save public crash log: $e');
      rethrow; // Let caller know it failed
    }
  }

  /// Checks if a crash log file exists from a previous crash.
  static Future<bool> hasSavedCrashLog() async {
    try {
      final file = await _logFile;
      return await file.exists();
    } catch (_) {
      return false;
    }
  }

  /// Reads and returns the contents of the persisted crash log file.
  static Future<String?> getSavedCrashLog() async {
    try {
      final file = await _logFile;
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (e) {
      debugPrint('[AppLogger] Failed to read crash log: $e');
    }
    return null;
  }

  /// Deletes the local crash log file.
  static Future<void> clearSavedCrashLog() async {
    try {
      final file = await _logFile;
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('[AppLogger] Failed to clear crash log: $e');
    }
  }
}
