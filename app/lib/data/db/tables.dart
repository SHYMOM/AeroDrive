import 'package:drift/drift.dart';

@DataClassName('FolderData')
class Folders extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get name => text()();
  TextColumn get parentId => text().nullable().references(Folders, #id)();
  BoolColumn get isVault => boolean().withDefault(const Constant(false))();
  TextColumn get color => text().nullable()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// 2. Files
@DataClassName('FileData')
class Files extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get name => text()();
  TextColumn get folderId => text().nullable().references(Folders, #id)();
  IntColumn get size => integer().nullable()();
  TextColumn get mimeType => text().nullable()();
  TextColumn get sha256Hash => text().nullable()(); // SHA-256 for deduplication (non-unique — multiple files can share same hash)
  BoolColumn get isEncrypted => boolean().withDefault(const Constant(false))();
  BoolColumn get isChunked => boolean().withDefault(const Constant(false))();
  IntColumn get totalChunks => integer().withDefault(const Constant(1))();
  TextColumn get encryptionNonce => text().nullable()(); // Base64 nonce
  TextColumn get encryptionAlgo => text().nullable()(); // 'AES-256-GCM' | 'AES-256-CTR'
  IntColumn get manifestVersion => integer().withDefault(const Constant(1))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  TextColumn get thumbnailPath => text().nullable()();
  IntColumn get thumbnailSize => integer().nullable()();
  DateTimeColumn get thumbnailLastAccess => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get manifestMessageId => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get photoTakenAt => dateTime().nullable()();
  IntColumn get duration => integer().nullable()(); // video or audio duration in seconds
  IntColumn get thumbnailMessageId => integer().nullable()();
  IntColumn get thumbnailChannelId => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// 3. File Chunks
@DataClassName('ChunkData')
class Chunks extends Table {
  TextColumn get id => text()();
  TextColumn get fileId => text().nullable().references(Files, #id)();
  IntColumn get chunkIndex => integer().nullable()();
  IntColumn get channelId => integer().nullable()();
  IntColumn get messageId => integer().nullable()();
  IntColumn get size => integer().nullable()();
  TextColumn get hash => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// 4. Channels
class Channels extends Table {
  IntColumn get id => integer()(); // Telegram channel ID
  TextColumn get name => text().nullable()();
  TextColumn get accountId => text().nullable()();
  IntColumn get messagesCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastUsed => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isHidden => boolean().withDefault(const Constant(false))(); // Duress-mode hidden channels

  @override
  Set<Column> get primaryKey => {id};
}

// 5. Accounts
class Accounts extends Table {
  TextColumn get id => text()();
  IntColumn get telegramUserId => integer().nullable()();
  TextColumn get phoneNumber => text().nullable()();
  TextColumn get phoneNumberMasked => text().nullable()();
  BlobColumn get sessionData => blob().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// 6. Tags
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();
  TextColumn get color => text().nullable()();
  TextColumn get source => text().withDefault(const Constant('USER'))(); // USER, ML_VISION, ML_EXIF

  @override
  Set<Column> get primaryKey => {id};
}

// 7. File-Tag Mapping
class FileTags extends Table {
  TextColumn get fileId => text().references(Files, #id)();
  TextColumn get tagId => text().references(Tags, #id)();

  @override
  Set<Column> get primaryKey => {fileId, tagId};
}

// 8. Share Links
@DataClassName('ShareLinkData')
class ShareLinks extends Table {
  TextColumn get id => text()();
  TextColumn get fileId => text().nullable().references(Files, #id)();
  TextColumn get folderId => text().nullable().references(Folders, #id)();
  TextColumn get token => text().nullable().unique()();
  TextColumn get passwordHash => text().nullable()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  IntColumn get maxDownloads => integer().nullable()();
  IntColumn get downloadCount => integer().withDefault(const Constant(0))();
  BoolColumn get burnAfterReading => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// 9. Upload/Download Queue
class TransferQueue extends Table {
  TextColumn get id => text()();
  TextColumn get fileId => text().nullable()(); 
  TextColumn get type => text().nullable()();
  TextColumn get status => text().nullable()();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  IntColumn get bytesTransferred => integer().withDefault(const Constant(0))();
  IntColumn get totalBytes => integer().nullable()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// 10. Face Clusters (Local AI)
class FaceClusters extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().nullable()();
  BlobColumn get embedding => blob().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// 11. Photo-Face Mapping
class PhotoFaces extends Table {
  TextColumn get id => text()();
  TextColumn get fileId => text().references(Files, #id)();
  TextColumn get faceClusterId => text().references(FaceClusters, #id)();
  RealColumn get confidence => real().nullable()();
  RealColumn get boxLeft => real().nullable()();
  RealColumn get boxTop => real().nullable()();
  RealColumn get boxWidth => real().nullable()();
  RealColumn get boxHeight => real().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// 12. Backup History
class BackupHistory extends Table {
  TextColumn get id => text()();
  TextColumn get type => text().nullable()();
  TextColumn get filePath => text().nullable()();
  IntColumn get fileSize => integer().nullable()();
  IntColumn get fileCount => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  BoolColumn get isEncrypted => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

// 13. Settings
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

// 14. Thumbnails
@DataClassName('ThumbnailData')
class Thumbnails extends Table {
  TextColumn get fileId => text().references(Files, #id)();
  BlobColumn get encryptedBlob => blob()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();

  @override
  Set<Column> get primaryKey => {fileId};
}

// 15. Manifest Messages (Zero-DB Recovery tracking)
@DataClassName('ManifestMessageData')
class ManifestMessages extends Table {
  TextColumn get id => text()();
  IntColumn get channelId => integer().nullable()();
  IntColumn get telegramMessageId => integer().nullable()();
  IntColumn get manifestVersion => integer().nullable()();
  TextColumn get payloadJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}


// 16. Places
class Places extends Table {
  TextColumn get id => text()();
  TextColumn get country => text().nullable()();
  TextColumn get adminArea => text().nullable()(); // State/Province
  TextColumn get locality => text().nullable()(); // City
  TextColumn get subLocality => text().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
}

// 17. File-Place Mapping
class FilePlaces extends Table {
  TextColumn get fileId => text().references(Files, #id)();
  TextColumn get placeId => text().references(Places, #id)();

  @override
  Set<Column> get primaryKey => {fileId, placeId};
}
