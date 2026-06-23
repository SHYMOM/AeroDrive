import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/data/repositories/folder_repository.dart';
import 'package:aerodrive/data/repositories/file_repository.dart';
import 'package:aerodrive/data/repositories/chunk_repository.dart';
import 'package:aerodrive/data/repositories/settings_repository.dart';
import 'package:aerodrive/data/crypto/encryption_engine.dart';
import 'package:aerodrive/domain/upload_orchestrator.dart';
import 'package:aerodrive/domain/upload_queue_service.dart';
import 'package:aerodrive/domain/download_orchestrator.dart';
import 'package:aerodrive/domain/download_queue_service.dart';
import 'package:aerodrive/features/telegram/telegram_service.dart';
import 'package:aerodrive/features/telegram/telegram_manager.dart';

final folderRepositoryProvider = Provider<FolderRepository>((ref) {
  return FolderRepository(ref.watch(databaseProvider));
});

final fileRepositoryProvider = Provider<FileRepository>((ref) {
  return FileRepository(ref.watch(databaseProvider));
});

final chunkRepositoryProvider = Provider<ChunkRepository>((ref) {
  return ChunkRepository(ref.watch(databaseProvider));
});
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(databaseProvider));
});

final encryptionEngineProvider = Provider<EncryptionEngine>((ref) {
  return EncryptionEngine();
});

final uploadOrchestratorProvider = Provider<UploadOrchestrator>((ref) {
  return UploadOrchestrator(ref.watch(encryptionEngineProvider));
});

final uploadQueueServiceProvider = Provider<UploadQueueService>((ref) {
  return UploadQueueService(
    ref,
    ref.watch(databaseProvider),
    ref.watch(settingsRepositoryProvider),
    ref.watch(telegramManagerProvider.notifier),
    ref.watch(uploadOrchestratorProvider),
  );
});

final downloadOrchestratorProvider = Provider<DownloadOrchestrator>((ref) {
  return DownloadOrchestrator(ref.watch(encryptionEngineProvider));
});

final downloadQueueServiceProvider = Provider<DownloadQueueService>((ref) {
  return DownloadQueueService(
    ref,
    ref.watch(databaseProvider),
    ref.watch(telegramManagerProvider.notifier),
    ref.watch(downloadOrchestratorProvider),
  );
});
