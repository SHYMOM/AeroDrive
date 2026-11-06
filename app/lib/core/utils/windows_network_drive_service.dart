import 'dart:io';
import 'package:flutter/foundation.dart';
import '../logger.dart';

/// Helper service for managing native Windows network drive mounting via WebDAV (`net use`).
class WindowsNetworkDriveService {
  static bool get isWindows => !kIsWeb && Platform.isWindows;

  /// Checks if a drive letter is currently mounted to the WebDAV server on the specified [port].
  /// Returns the drive letter (e.g. `'Z:'`) or `null` if not mounted.
  static Future<String?> getMountedDrive(int port) async {
    if (!isWindows) return null;
    try {
      final result = await Process.run('net', ['use']);
      if (result.exitCode != 0) return null;

      final output = result.stdout.toString();
      final lines = output.split('\n');

      for (final line in lines) {
        if (line.contains('$port') || line.contains('DavWWWRoot')) {
          final match = RegExp(r'([A-Za-z]:)').firstMatch(line);
          if (match != null) {
            return match.group(1);
          }
        }
      }
      return null;
    } catch (e) {
      AppLogger.warning('WindowsNetworkDriveService: Failed to query net use: $e');
      return null;
    }
  }

  /// Mounts the local WebDAV server as an actual Windows network drive letter (e.g., `Z:`).
  /// Launches Windows File Explorer to the mounted drive upon success.
  /// Returns the mounted drive letter.
  static Future<String> mountDrive(int port) async {
    if (!isWindows) {
      throw UnsupportedError('Network drive mounting is only supported on Windows');
    }

    // Try mounting to next available drive letter with 'net use *'
    final mountUrl = 'http://127.0.0.1:$port/';
    final result = await Process.run('net', ['use', '*', mountUrl]);

    if (result.exitCode != 0) {
      final stderr = result.stderr.toString();
      final stdout = result.stdout.toString();
      throw Exception(stderr.isNotEmpty ? stderr.trim() : stdout.trim());
    }

    final stdout = result.stdout.toString();
    // Expected output format: "Drive Z: is now connected to http://127.0.0.1:49188/."
    final match = RegExp(r'Drive\s+([A-Za-z]:)', caseSensitive: false).firstMatch(stdout);
    final driveLetter = match?.group(1) ?? await getMountedDrive(port) ?? 'Z:';

    // Open Windows File Explorer to the freshly mounted drive
    try {
      await Process.run('explorer.exe', [driveLetter]);
    } catch (_) {}

    AppLogger.info('WindowsNetworkDriveService: Successfully mounted $mountUrl as $driveLetter');
    return driveLetter;
  }

  /// Disconnects and unmounts the specified drive letter.
  static Future<bool> unmountDrive(String driveLetter) async {
    if (!isWindows) return false;
    try {
      final cleanLetter = driveLetter.endsWith(':') ? driveLetter : '$driveLetter:';
      final result = await Process.run('net', ['use', cleanLetter, '/delete', '/yes']);
      return result.exitCode == 0;
    } catch (e) {
      AppLogger.error('WindowsNetworkDriveService: Failed to unmount drive $driveLetter', e);
      return false;
    }
  }

  /// Queries the Windows registry to check the WebClient FileSizeLimitInBytes (in bytes).
  /// By default, Windows caps WebDAV file downloads at 50,000,000 bytes (50 MB), causing error 0x800700DF.
  static Future<int?> checkFileSizeLimitInBytes() async {
    if (!isWindows) return null;
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r"(Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\WebClient\Parameters' -Name 'FileSizeLimitInBytes' -ErrorAction SilentlyContinue).FileSizeLimitInBytes",
      ]);
      if (result.exitCode == 0) {
        final valStr = result.stdout.toString().trim();
        return int.tryParse(valStr);
      }
    } catch (e) {
      AppLogger.warning('WindowsNetworkDriveService: Failed to read FileSizeLimitInBytes: $e');
    }
    return null;
  }

  /// Returns true if the Windows WebClient file size limit is at least 4 GB (or 0xffffffff).
  static Future<bool> isFileSizeLimit4GB() async {
    final limit = await checkFileSizeLimitInBytes();
    if (limit == null) return false;
    // 0xffffffff as signed 32-bit int can be -1 or 4294967295
    return limit == -1 || limit >= 4000000000;
  }

  /// Elevates via UAC to set FileSizeLimitInBytes to 4GB (0xffffffff) and restart the WebClient service.
  /// Returns true if the limit was successfully updated.
  static Future<bool> fixFileSizeLimit() async {
    if (!isWindows) return false;
    try {
      final tempDir = Directory.systemTemp;
      final scriptFile = File('${tempDir.path}\\fix_webdav_limit.bat');
      await scriptFile.writeAsString('''@echo off
reg add "HKLM\\SYSTEM\\CurrentControlSet\\Services\\WebClient\\Parameters" /v FileSizeLimitInBytes /t REG_DWORD /d 0xffffffff /f
net stop WebClient
net start WebClient
''');

      // Use PowerShell Start-Process with -Verb RunAs without -NonInteractive so UAC interactive prompt appears
      await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        'Start-Process -FilePath "${scriptFile.path}" -Verb RunAs -Wait',
      ]);
      AppLogger.info('WindowsNetworkDriveService: Triggered elevated UAC prompt to fix 4GB WebClient limit');
      
      // Cleanup temp script
      try {
        if (await scriptFile.exists()) {
          await scriptFile.delete();
        }
      } catch (_) {}

      return await isFileSizeLimit4GB();
    } catch (e) {
      AppLogger.error('WindowsNetworkDriveService: Failed to trigger UAC registry fix: $e');
      rethrow;
    }
  }
}

