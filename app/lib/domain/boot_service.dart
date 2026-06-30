import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BootService {
  static const _channel = MethodChannel('com.aerodrive.aerodrive/boot');

  static Future<bool> isBootCompleted() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod('isBootCompleted') ?? false;
    } catch (_) {
      return false;
    }
  }
}
