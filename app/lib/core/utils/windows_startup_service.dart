import 'dart:io';
import 'package:flutter/foundation.dart';
import '../logger.dart';

/// Service to manage Windows startup and background execution.
/// Works cleanly with both installed and portable ZIP releases by
/// referencing `Platform.resolvedExecutable` into HKCU Run registry key.
class WindowsStartupService {
  static const String _registryKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _appName = 'AeroDrive';

  static bool get isWindows => !kIsWeb && Platform.isWindows;

  /// Checks if AeroDrive is currently registered in Windows Startup.
  static Future<bool> isStartupEnabled() async {
    if (!isWindows) return false;
    try {
      final result = await Process.run('reg', ['query', _registryKey, '/v', _appName]);
      return result.exitCode == 0;
    } catch (e) {
      AppLogger.warning('WindowsStartupService: Failed to query startup registry: $e');
      return false;
    }
  }

  /// Registers or unregisters AeroDrive in Windows Startup (HKCU).
  /// [background]: if true, passes `--background` argument on launch.
  static Future<bool> setStartupEnabled(bool enable, {bool background = true}) async {
    if (!isWindows) return false;
    try {
      if (enable) {
        final exePath = Platform.resolvedExecutable;
        final commandValue = background ? '"$exePath" --background' : '"$exePath"';
        final result = await Process.run('reg', [
          'add',
          _registryKey,
          '/v',
          _appName,
          '/t',
          'REG_SZ',
          '/d',
          commandValue,
          '/f',
        ]);
        final success = result.exitCode == 0;
        if (success) {
          AppLogger.info('WindowsStartupService: Successfully registered AeroDrive in Windows Startup');
        } else {
          AppLogger.warning('WindowsStartupService: reg add failed: ${result.stderr}');
        }
        return success;
      } else {
        final result = await Process.run('reg', [
          'delete',
          _registryKey,
          '/v',
          _appName,
          '/f',
        ]);
        final success = result.exitCode == 0;
        if (success) {
          AppLogger.info('WindowsStartupService: Successfully removed AeroDrive from Windows Startup');
        }
        return success;
      }
    } catch (e) {
      AppLogger.error('WindowsStartupService: Failed to update startup registry', e);
      return false;
    }
  }

  /// Checks if Windows WebClient service has BasicAuthLevel set to 2 (allowing Basic Auth over HTTP).
  static Future<bool> isWebClientBasicAuthEnabled() async {
    if (!isWindows) return false;
    try {
      final result = await Process.run('reg', [
        'query',
        r'HKLM\SYSTEM\CurrentControlSet\Services\WebClient\Parameters',
        '/v',
        'BasicAuthLevel',
      ]);
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        return output.contains('0x2');
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Prompts UAC elevation to set BasicAuthLevel = 2 and restart the WebClient service.
  static Future<bool> enableWebClientBasicAuth() async {
    if (!isWindows) return false;
    try {
      const script = r"Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\WebClient\Parameters' -Name 'BasicAuthLevel' -Value 2; Restart-Service WebClient";
      final result = await Process.run('powershell', [
        '-Command',
        'Start-Process',
        'powershell',
        '-ArgumentList',
        '"-Command $script"',
        '-Verb',
        'RunAs',
      ]);
      return result.exitCode == 0;
    } catch (e) {
      AppLogger.error('WindowsStartupService: Failed to request elevated BasicAuthLevel change', e);
      return false;
    }
  }
}

