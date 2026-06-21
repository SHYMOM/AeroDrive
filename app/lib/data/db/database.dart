import 'dart:io' as io;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

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
  Shares,
  TransferQueue,
  FaceClusters,
  PhotoFaces,
  BackupHistory,
  Settings,
])
class AeroDriveDatabase extends _$AeroDriveDatabase {
  AeroDriveDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
      },
      onUpgrade: (m, from, to) async {
        if (from == 1) {
          // Destructive recreate for massive schema change between alpha and v2
          for (final table in allTables) {
            await m.deleteTable(table.actualTableName);
            await m.createTable(table);
          }
        }
      },
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = io.File(p.join(dbFolder.path, 'aerodrive.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
