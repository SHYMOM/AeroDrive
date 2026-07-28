import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import '../../core/logger.dart';

/// Picks files using file_picker (avoids ANR from file_selector's main-thread copy).
/// For content:// URIs (Android 11+), the file is copied to temp on a native background thread.
Future<List<String>> pickFilesForUpload({bool allowMultiple = false}) async {
  final result = await FilePicker.pickFiles(
    allowMultiple: allowMultiple,
    type: FileType.any,
  );
  if (result == null || result.files.isEmpty) return [];

  final paths = <String>[];
  const channel = MethodChannel('com.aerodrive.aerodrive/file_picker');

  for (final file in result.files) {
    if (file.path == null) continue;

    if (file.path!.startsWith('content://')) {
      try {
        final tempPath = await channel.invokeMethod<String>('copyToTemp', {
          'uri': file.path,
          'fileName': file.name,
        });
        if (tempPath != null) {
          paths.add(tempPath);
        } else {
          AppLogger.warning('FilePickerUtil: copyToTemp returned null for ${file.name}');
        }
      } catch (e) {
        AppLogger.error('FilePickerUtil: copyToTemp failed for ${file.name}', e);
      }
    } else {
      paths.add(file.path!);
    }
  }

  return paths;
}
