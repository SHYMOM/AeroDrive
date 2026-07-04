import 'package:battery_plus/battery_plus.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logger.dart';
import '../../core/providers.dart';
import '../../core/providers/repository_providers.dart';
import 'ml_service.dart';

class AIQueueService {

  AIQueueService(this._ref);
  final Ref _ref;
  final Battery _battery = Battery();
  bool _isProcessing = false;

  Future<void> triggerQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final settings = _ref.read(settingsRepositoryProvider);
      final powerUserStr = await settings.getSetting('ai_power_user');
      final isPowerUser = powerUserStr == 'true';

      if (!isPowerUser) {
        final batteryState = await _battery.batteryState;
        if (batteryState != BatteryState.charging && batteryState != BatteryState.full) {
          AppLogger.info('AIQueueService: Not charging. Skipping ML queue.');
          return;
        }
      }

      final db = _ref.read(databaseProvider);
      
      // Get images without tags (naive check: files without FileTags)
      final untaggedImages = await (db.select(db.files)..where((t) => t.mimeType.like('image/%'))).get();

      // For a real implementation, we'd have a specific "ml_scanned" boolean on the Files table.
      // We will just process them and ml_service handles it.
      
      final mlService = _ref.read(mlServiceProvider);
      await mlService.processImageBatch(untaggedImages);
      
    } catch (e, s) {
      AppLogger.error('AIQueueService error', e, s);
    } finally {
      _isProcessing = false;
    }
  }
}

final aiQueueServiceProvider = Provider<AIQueueService>(AIQueueService.new);
