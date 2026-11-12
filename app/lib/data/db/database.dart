import 'dart:io' as io;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [
  Folders,
  Files,
  Chunks,
  Channels,
  Accounts,
  Tags,
  FileTags,
  ShareLinks,
  TransferQueue,
  FaceClusters,
  PhotoFaces,
  BackupHistory,
  Settings,
  Thumbnails,
  ManifestMessages,
  ShareLinks,
  Places,
  FilePlaces,
])
class AeroDriveDatabase extends _$AeroDriveDatabase {
  AeroDriveDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 13;

  @override
  MigrationStrategy get migration => MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
      },
      onUpgrade: (m, from, to) async {
        Future<void> safeAddColumn(TableInfo table, GeneratedColumn column) async {
          try {
            final rows = await customSelect("PRAGMA table_info('${table.actualTableName}')").get();
            final colName = column.name.toLowerCase();
            final exists = rows.any((r) =>
                (r.data['name'] as String?)?.toLowerCase() == colName);
            if (exists) {
              return;
            }
          } catch (_) {}

          try {
            await m.addColumn(table, column);
          } catch (e) {
            final msg = e.toString().toLowerCase();
            if (msg.contains('duplicate column') || msg.contains('already exists')) {
              return;
            }
            rethrow;
          }
        }

        Future<void> safeCreateTable(TableInfo table) async {
          try {
            await m.createTable(table);
          } catch (e) {
            final msg = e.toString().toLowerCase();
            if (msg.contains('already exists')) {
              return;
            }
            rethrow;
          }
        }

        if (from < 2) {
          await m.createAll();
        }
        if (from < 3) {
          await safeAddColumn(files, files.sha256Hash);
        }
        if (from < 4) {
          await safeAddColumn(files, files.manifestMessageId);
          await safeAddColumn(files, files.version);
        }
        if (from < 5) {
          await safeAddColumn(files, files.encryptionNonce);
          await safeAddColumn(files, files.encryptionAlgo);
          await safeAddColumn(files, files.manifestVersion);
          await safeAddColumn(files, files.isFavorite);
          await safeAddColumn(channels, channels.isHidden);
          await safeAddColumn(accounts, accounts.telegramUserId);
          await safeAddColumn(accounts, accounts.phoneNumberMasked);
          await safeAddColumn(accounts, accounts.isActive);
          await safeCreateTable(thumbnails);
          await safeCreateTable(manifestMessages);
          await safeCreateTable(shareLinks);
        }
        if (from < 6) {
          await safeAddColumn(tags, tags.source);
          await safeCreateTable(places);
          await safeCreateTable(filePlaces);
        }
        if (from < 7) {
          await safeAddColumn(folders, folders.isFavorite);
        }
        if (from < 8) {
          await safeAddColumn(files, files.photoTakenAt);
        }
        if (from < 9) {
          await safeAddColumn(files, files.duration);
        }
        if (from < 10) {
          await safeAddColumn(files, files.thumbnailMessageId);
          await safeAddColumn(files, files.thumbnailChannelId);
          try {
            await m.deleteTable('photo_faces');
          } catch (_) {}
          await safeCreateTable(photoFaces);
        }
        if (from < 11) {
          // Phase 0: Add Channel purpose and auto-create columns
          await safeAddColumn(channels, channels.purpose);
          await safeAddColumn(channels, channels.descriptionCached);
          await safeAddColumn(channels, channels.isAutoCreated);
        }
        if (from < 12) {
          // Phase 0: Add dedicated DEK storage to TransferQueue
          await safeAddColumn(transferQueue, transferQueue.encryptedDek);
          await safeAddColumn(transferQueue, transferQueue.encryptionAlgo);
          await safeAddColumn(transferQueue, transferQueue.encryptionNonce);
          await safeAddColumn(transferQueue, transferQueue.streamingIv);
        }
        if (from < 13) {
          await safeAddColumn(folders, folders.isEncrypted);
        }
      },
    );
}

LazyDatabase _openConnection() => LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = io.File(p.join(dbFolder.path, 'aerodrive.sqlite'));
    return NativeDatabase.createInBackground(
      file,
      setup: (db) {
        db.execute('PRAGMA journal_mode=WAL;');
        db.execute('PRAGMA busy_timeout=30000;');
      },
    );
  });
