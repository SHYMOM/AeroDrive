import 'dart:convert';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/data/repositories/settings_repository.dart';
import 'package:aerodrive/domain/sync/config_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AeroDriveDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AeroDriveDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        settingsRepositoryProvider.overrideWithValue(SettingsRepository(db)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('Cross-Device Drive State Sync Tests', () {
    test('applyRemoteDriveState moves active file to trash when remote config has it in trashed_files', () async {
      final configService = container.read(configSyncServiceProvider);

      // Insert an active file
      await db.into(db.files).insert(
        FilesCompanion.insert(
          id: 'test_file_1',
          name: 'vacation.mp4',
          size: const drift.Value(1024),
          createdAt: drift.Value(DateTime.now()),
        ),
      );

      var fileInDb = await (db.select(db.files)..where((f) => f.id.equals('test_file_1'))).getSingle();
      expect(fileInDb.deletedAt, isNull);

      // Apply remote drive state indicating file was trashed on PC
      final remoteConfig = {
        'trashed_files': {
          'test_file_1': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        'trashed_folders': <String, dynamic>{},
        'deleted_file_ids': <String>[],
        'deleted_folder_ids': <String>[],
      };

      final changed = await configService.applyRemoteDriveState(remoteConfig);
      expect(changed, isTrue);

      fileInDb = await (db.select(db.files)..where((f) => f.id.equals('test_file_1'))).getSingle();
      expect(fileInDb.deletedAt, isNotNull);
    });

    test('applyRemoteDriveState restores file when it is removed from remote trashed_files', () async {
      final configService = container.read(configSyncServiceProvider);

      // Insert a trashed file
      await db.into(db.files).insert(
        FilesCompanion.insert(
          id: 'test_file_restore',
          name: 'notes.txt',
          size: const drift.Value(512),
          deletedAt: drift.Value(DateTime.now()),
          createdAt: drift.Value(DateTime.now()),
        ),
      );

      var fileInDb = await (db.select(db.files)..where((f) => f.id.equals('test_file_restore'))).getSingle();
      expect(fileInDb.deletedAt, isNotNull);

      // Apply remote drive state where trashed_files is empty (file was restored on PC)
      final remoteConfig = {
        'trashed_files': <String, dynamic>{},
        'trashed_folders': <String, dynamic>{},
        'deleted_file_ids': <String>[],
        'deleted_folder_ids': <String>[],
      };

      final changed = await configService.applyRemoteDriveState(remoteConfig);
      expect(changed, isTrue);

      fileInDb = await (db.select(db.files)..where((f) => f.id.equals('test_file_restore'))).getSingle();
      expect(fileInDb.deletedAt, isNull);
    });

    test('applyRemoteDriveState permanently purges files and chunks present in deleted_file_ids', () async {
      final configService = container.read(configSyncServiceProvider);

      // Insert file and chunk
      await db.into(db.files).insert(
        FilesCompanion.insert(
          id: 'test_file_purge',
          name: 'old_video.mkv',
          size: const drift.Value(2048),
          createdAt: drift.Value(DateTime.now()),
        ),
      );

      await db.into(db.chunks).insert(
        ChunksCompanion.insert(
          id: 'chunk_1',
          fileId: const drift.Value('test_file_purge'),
          chunkIndex: const drift.Value(0),
          channelId: const drift.Value(12345),
          messageId: const drift.Value(67890),
        ),
      );

      // Apply remote drive state with tombstone in deleted_file_ids
      final remoteConfig = {
        'trashed_files': <String, dynamic>{},
        'trashed_folders': <String, dynamic>{},
        'deleted_file_ids': ['test_file_purge'],
        'deleted_folder_ids': <String>[],
      };

      final changed = await configService.applyRemoteDriveState(remoteConfig);
      expect(changed, isTrue);

      final fileCount = await (db.select(db.files)..where((f) => f.id.equals('test_file_purge'))).get();
      final chunkCount = await (db.select(db.chunks)..where((c) => c.fileId.equals('test_file_purge'))).get();
      expect(fileCount, isEmpty);
      expect(chunkCount, isEmpty);
    });

    test('applyRemoteDriveState soft-deletes folders and their sub-items', () async {
      final configService = container.read(configSyncServiceProvider);

      // Insert active folder
      await db.into(db.folders).insert(
        FoldersCompanion.insert(
          id: 'folder_123',
          name: 'Projects',
          createdAt: drift.Value(DateTime.now()),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );

      // Apply remote drive state indicating folder was trashed on PC
      final remoteConfig = {
        'trashed_files': <String, dynamic>{},
        'trashed_folders': {
          'folder_123': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        'deleted_file_ids': <String>[],
        'deleted_folder_ids': <String>[],
      };

      final changed = await configService.applyRemoteDriveState(remoteConfig);
      expect(changed, isTrue);

      final folderInDb = await (db.select(db.folders)..where((f) => f.id.equals('folder_123'))).getSingle();
      expect(folderInDb.deletedAt, isNotNull);
    });
  });
}
