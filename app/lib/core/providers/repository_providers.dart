import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/crypto/encryption_engine.dart';
import '../../data/repositories/chunk_repository.dart';
import '../../data/repositories/file_repository.dart';
import '../../data/repositories/folder_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/download_orchestrator.dart';
import '../../domain/download_queue_service.dart';
import '../../domain/upload_orchestrator.dart';
import '../../domain/upload_queue_service.dart';
import '../../features/api/api_service.dart';
import '../../features/telegram/telegram_manager.dart';
import '../providers.dart';

final folderRepositoryProvider = Provider<FolderRepository>((ref) => FolderRepository(ref.watch(databaseProvider)));

final fileRepositoryProvider = Provider<FileRepository>((ref) => FileRepository(ref.watch(databaseProvider)));

final chunkRepositoryProvider = Provider<ChunkRepository>((ref) => ChunkRepository(ref.watch(databaseProvider)));
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) => SettingsRepository(ref.watch(databaseProvider)));

// Bug #2 fix: track settings version instead of invalidating the repository
final settingsUpdateProvider = StateProvider<int>((ref) => 0);

final encryptionEngineProvider = Provider<EncryptionEngine>((ref) => EncryptionEngine());

final uploadOrchestratorProvider = Provider<UploadOrchestrator>((ref) => UploadOrchestrator());

final uploadQueueServiceProvider = Provider<UploadQueueService>((ref) {
  final service = UploadQueueService(
    ref,
    ref.watch(databaseProvider),
    ref.watch(settingsRepositoryProvider),
    ref.watch(telegramManagerProvider.notifier),
    ref.watch(uploadOrchestratorProvider),
  );
  ref.onDispose(() => service.dispose());
  return service;
});

final downloadOrchestratorProvider = Provider<DownloadOrchestrator>((ref) => DownloadOrchestrator());

final downloadQueueServiceProvider = Provider<DownloadQueueService>((ref) {
  final service = DownloadQueueService(
    ref,
    ref.watch(databaseProvider),
    ref.watch(telegramManagerProvider.notifier),
    ref.watch(downloadOrchestratorProvider),
  );
  ref.onDispose(() => service.dispose());
  return service;
});

final apiServiceProvider = Provider<ApiService>((ref) {
  // ApiService is started/stopped explicitly; provider just exposes the instance.
  return ApiService(container: ref.container);
});
