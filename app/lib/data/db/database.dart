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
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
      },
      onUpgrade: (m, from, to) async {
        if (from < 2) {
          await m.createAll();
        }
        if (from < 3) {
          await m.addColumn(files, files.sha256Hash);
        }
        if (from < 4) {
          await m.addColumn(files, files.manifestMessageId);
          await m.addColumn(files, files.version);
        }
        if (from < 5) {
          await m.addColumn(files, files.encryptionNonce);
          await m.addColumn(files, files.encryptionAlgo);
          await m.addColumn(files, files.manifestVersion);
          await m.addColumn(files, files.isFavorite);
          await m.addColumn(channels, channels.isHidden);
          await m.addColumn(accounts, accounts.telegramUserId);
          await m.addColumn(accounts, accounts.phoneNumberMasked);
          await m.addColumn(accounts, accounts.isActive);
          await m.createTable(thumbnails);
          await m.createTable(manifestMessages);
          await m.createTable(shareLinks);
        }
        if (from < 6) {
          await m.addColumn(tags, tags.source);
          await m.createTable(places);
          await m.createTable(filePlaces);
        }
        if (from < 7) {
          await m.addColumn(folders, folders.isFavorite);
        }
        if (from < 8) {
          await m.addColumn(files, files.photoTakenAt);
        }
        if (from < 9) {
          await m.addColumn(files, files.duration);
        }
        if (from < 10) {
          await m.addColumn(files, files.thumbnailMessageId);
          await m.addColumn(files, files.thumbnailChannelId);
          try {
            await m.deleteTable('photo_faces');
          } catch (_) {}
          await m.createTable(photoFaces);
        }
      },
    );
}

LazyDatabase _openConnection() => LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = io.File(p.join(dbFolder.path, 'aerodrive.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
