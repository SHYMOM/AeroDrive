import 'dart:io' as io;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'database.g.dart';

// ─────────────────────────────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────────────────────────────

/// Upload status for individual chunks.
enum UploadStatus { pending, uploading, done, failed }

/// Upload queue entry status.
enum QueueEntryStatus { queued, inProgress, completed, failed, paused }

// ─────────────────────────────────────────────────────────────────────
// Tables
// ─────────────────────────────────────────────────────────────────────

/// Virtual folder hierarchy.
class Folders extends Table {
  TextColumn get id => text()();
  TextColumn get parentId => text().nullable().references(Folders, #id)();
  TextColumn get name => text().withLength(min: 1, max: 255)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isTrashed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get trashedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// File metadata — source of truth for every stored file.
class Files extends Table {
  TextColumn get id => text()();
  TextColumn get folderId => text().references(Folders, #id)();
  TextColumn get name => text().withLength(min: 1, max: 512)();
  TextColumn get mimeType => text().withDefault(const Constant('application/octet-stream'))();
  IntColumn get sizeBytes => integer()();
  TextColumn get sha256Hash => text()();
  TextColumn get encryptionNonce => text().nullable()();
  TextColumn get encryptionAlgo => text().withDefault(const Constant('AES-256-GCM'))();
  IntColumn get manifestVersion => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isTrashed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get trashedAt => dateTime().nullable()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Individual encrypted chunks uploaded to Telegram.
class Chunks extends Table {
  TextColumn get id => text()();
  TextColumn get fileId => text().references(Files, #id)();
  IntColumn get chunkIndex => integer()();
  TextColumn get channelId => text().references(Channels, #id)();
  TextColumn get accountId => text().references(Accounts, #id)();
  IntColumn get telegramMessageId => integer().nullable()();
  TextColumn get telegramFileId => text().nullable()();
  IntColumn get sizeBytes => integer()();
  TextColumn get chunkHash => text()();
  IntColumn get uploadStatus => intEnum<UploadStatus>()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Telegram channels used as storage destinations.
class Channels extends Table {
  TextColumn get id => text()();
  IntColumn get telegramChatId => integer()();
  TextColumn get displayName => text().withLength(min: 1, max: 255)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isHidden => boolean().withDefault(const Constant(false))();
  IntColumn get quotaUsedBytes => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Linked Telegram accounts with encrypted session data.
class Accounts extends Table {
  TextColumn get id => text()();
  IntColumn get telegramUserId => integer()();
  TextColumn get phoneNumberMasked => text()();
  BlobColumn get sessionEncrypted => blob()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Hidden manifest messages for version tracking.
class ManifestMessages extends Table {
  TextColumn get id => text()();
  TextColumn get channelId => text().references(Channels, #id)();
  IntColumn get telegramMessageId => integer()();
  IntColumn get manifestVersion => integer()();
  TextColumn get payloadJson => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Encrypted thumbnail blobs for file previews.
class Thumbnails extends Table {
  TextColumn get fileId => text().references(Files, #id)();
  BlobColumn get encryptedBlob => blob()();
  IntColumn get width => integer()();
  IntColumn get height => integer()();

  @override
  Set<Column> get primaryKey => {fileId};
}

/// Share link metadata for file/folder sharing.
class ShareLinks extends Table {
  TextColumn get id => text()();
  TextColumn get fileId => text().nullable()();
  TextColumn get folderId => text().nullable()();
  TextColumn get token => text().unique()();
  TextColumn get passwordHash => text().nullable()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  IntColumn get maxDownloads => integer().nullable()();
  IntColumn get downloadCount => integer().withDefault(const Constant(0))();
  BoolColumn get burnAfterReading => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Persisted upload queue — survives app restarts.
class UploadQueueEntries extends Table {
  TextColumn get id => text()();
  TextColumn get filePath => text()();
  IntColumn get status => intEnum<QueueEntryStatus>()();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  TextColumn get targetFolderId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────────────────────────────────────────────────
// Database
// ─────────────────────────────────────────────────────────────────────

@DriftDatabase(tables: [
  Folders,
  Files,
  Chunks,
  Channels,
  Accounts,
  ManifestMessages,
  Thumbnails,
  ShareLinks,
  UploadQueueEntries,
])
class AeroDriveDatabase extends _$AeroDriveDatabase {
  AeroDriveDatabase() : super(_openConnection());

  /// Bump this whenever you change the schema and add a migration.
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
      },
      onUpgrade: (m, from, to) async {
        // Future migrations go here.
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
