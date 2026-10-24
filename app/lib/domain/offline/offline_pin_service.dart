import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/logger.dart';
import '../../core/providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../data/db/database.dart';
import '../../features/preview/file_decryption_util.dart';

const String _kOfflinePinnedSettingKey = 'offline_pinned_files';

/// Manages offline pinned files for zero-network access.
class OfflinePinService {
  OfflinePinService(this._ref);

  final Ref _ref;

  /// Returns the persistent offline directory for pinned files.
  static Future<Directory> getOfflineDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final offlineDir = Directory('${appDir.path}${Platform.pathSeparator}offline_vault');
    if (!await offlineDir.exists()) {
      await offlineDir.create(recursive: true);
    }
    return offlineDir;
  }

  /// Checks if a file is locally pinned and the cached decrypted file exists on disk.
  Future<bool> isPinned(String fileId) async {
    final pinnedMap = await _loadRegistry();
    if (!pinnedMap.containsKey(fileId)) return false;

    final path = pinnedMap[fileId]?['path'] as String?;
    if (path == null) return false;

    return File(path).exists();
  }

  /// Returns the locally pinned [File] if available, or null.
  Future<File?> getOfflineFile(String fileId) async {
    final pinnedMap = await _loadRegistry();
    final path = pinnedMap[fileId]?['path'] as String?;
    if (path == null) return null;

    final file = File(path);
    if (await file.exists()) {
      return file;
    }
    return null;
  }

  /// Pins a file for offline access: downloads, decrypts, and saves to offline vault.
  Future<File?> pinFile(FileData file) async {
    try {
      final offlineDir = await getOfflineDirectory();
      // Sanitize filename for local storage
      final safeName = file.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final targetPath = '${offlineDir.path}${Platform.pathSeparator}${file.id}_$safeName';
      final targetFile = File(targetPath);

      if (!await targetFile.exists()) {
        final container = _ref.container;
        final tempDecrypted = await streamDecryptedFileToDisk(container, file);
        if (tempDecrypted == null || !await tempDecrypted.exists()) {
          AppLogger.error('OfflinePinService: failed to decrypt file ${file.id} for offline pin');
          return null;
        }

        // Copy or move to persistent offline vault
        await tempDecrypted.copy(targetPath);
        try {
          await tempDecrypted.delete();
        } catch (_) {}
      }

      // Update registry
      final pinnedMap = await _loadRegistry();
      pinnedMap[file.id] = {
        'fileId': file.id,
        'name': file.name,
        'path': targetPath,
        'size': file.size ?? (await targetFile.length()),
        'mimeType': file.mimeType ?? 'application/octet-stream',
        'pinnedAt': DateTime.now().toIso8601String(),
      };
      await _saveRegistry(pinnedMap);

      // Notify state
      _ref.read(offlinePinnedIdsProvider.notifier).setPinned(pinnedMap.keys.toSet());
      AppLogger.info('OfflinePinService: pinned file ${file.id} to $targetPath');
      return targetFile;
    } catch (e, s) {
      AppLogger.error('OfflinePinService: error pinning file ${file.id}', e, s);
      return null;
    }
  }

  /// Removes offline pin and deletes local cached file.
  Future<void> unpinFile(String fileId) async {
    try {
      final pinnedMap = await _loadRegistry();
      final entry = pinnedMap.remove(fileId);
      if (entry != null) {
        final path = entry['path'] as String?;
        if (path != null) {
          final f = File(path);
          if (await f.exists()) {
            await f.delete();
          }
        }
      }
      await _saveRegistry(pinnedMap);
      _ref.read(offlinePinnedIdsProvider.notifier).setPinned(pinnedMap.keys.toSet());
      AppLogger.info('OfflinePinService: unpinned file $fileId');
    } catch (e, s) {
      AppLogger.error('OfflinePinService: error unpinning file $fileId', e, s);
    }
  }

  /// Returns total disk size of offline pinned files in bytes.
  Future<int> getTotalOfflineBytes() async {
    try {
      final dir = await getOfflineDirectory();
      var total = 0;
      await for (final entity in dir.list(recursive: false, followLinks: false)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<Map<String, dynamic>> _loadRegistry() async {
    try {
      final settings = _ref.read(settingsRepositoryProvider);
      final raw = await settings.getSetting(_kOfflinePinnedSettingKey);
      if (raw == null || raw.isEmpty) return {};
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveRegistry(Map<String, dynamic> registry) async {
    final settings = _ref.read(settingsRepositoryProvider);
    await settings.setSetting(_kOfflinePinnedSettingKey, jsonEncode(registry));
  }

  /// Initial load of all pinned IDs into reactive provider.
  Future<void> initialize() async {
    final map = await _loadRegistry();
    // Validate each pinned file actually exists on disk
    final validIds = <String>{};
    var changed = false;

    for (final entry in map.entries) {
      final path = entry.value['path'] as String?;
      if (path != null && await File(path).exists()) {
        validIds.add(entry.key);
      } else {
        changed = true;
      }
    }

    if (changed) {
      map.removeWhere((k, v) => !validIds.contains(k));
      await _saveRegistry(map);
    }

    _ref.read(offlinePinnedIdsProvider.notifier).setPinned(validIds);
  }
}

/// Reactive StateNotifier for pinned file IDs.
class OfflinePinnedIdsNotifier extends StateNotifier<Set<String>> {
  OfflinePinnedIdsNotifier() : super({});

  void setPinned(Set<String> ids) {
    state = ids;
  }

  bool isPinned(String id) => state.contains(id);
}

final offlinePinnedIdsProvider =
    StateNotifierProvider<OfflinePinnedIdsNotifier, Set<String>>((ref) {
  return OfflinePinnedIdsNotifier();
});

final offlinePinServiceProvider = Provider<OfflinePinService>((ref) {
  final service = OfflinePinService(ref);
  // Auto-init registry on first access
  service.initialize();
  return service;
});
