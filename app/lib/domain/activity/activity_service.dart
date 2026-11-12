import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../data/db/database.dart';

enum DriveActivityType {
  upload,
  createFolder,
  rename,
  colorChange,
  share,
  move,
  trash,
  restore,
}

class DriveActivityEvent {
  const DriveActivityEvent({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.timestamp,
    this.fileId,
    this.folderId,
    this.fileName,
    this.fileSize,
    this.mimeType,
    this.colorHex,
  });

  factory DriveActivityEvent.fromJson(Map<String, dynamic> json) => DriveActivityEvent(
        id: json['id'] as String? ?? const Uuid().v4(),
        type: DriveActivityType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => DriveActivityType.upload,
        ),
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
        fileId: json['fileId'] as String?,
        folderId: json['folderId'] as String?,
        fileName: json['fileName'] as String?,
        fileSize: json['fileSize'] as int?,
        mimeType: json['mimeType'] as String?,
        colorHex: json['colorHex'] as String?,
      );

  final String id;
  final DriveActivityType type;
  final String title;
  final String description;
  final DateTime timestamp;
  final String? fileId;
  final String? folderId;
  final String? fileName;
  final int? fileSize;
  final String? mimeType;
  final String? colorHex;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'description': description,
        'timestamp': timestamp.toIso8601String(),
        'fileId': fileId,
        'folderId': folderId,
        'fileName': fileName,
        'fileSize': fileSize,
        'mimeType': mimeType,
        'colorHex': colorHex,
      };
}

class ActivityService {
  ActivityService(this._ref);

  final Ref _ref;
  final List<DriveActivityEvent> _events = [];
  bool _initialized = false;

  Future<File> _getFile() async {
    final docs = await getApplicationDocumentsDirectory();
    return File(p.join(docs.path, 'aerodrive_activity_logs.json'));
  }

  Future<void> _init() async {
    if (_initialized) return;
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> list = jsonDecode(content) as List<dynamic>;
        _events.clear();
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            _events.add(DriveActivityEvent.fromJson(item));
          }
        }
      }
    } catch (_) {}
    _initialized = true;
  }

  Future<void> _persist() async {
    try {
      final file = await _getFile();
      final data = jsonEncode(_events.take(200).map((e) => e.toJson()).toList());
      await file.writeAsString(data);
    } catch (_) {}
  }

  Future<void> recordEvent(DriveActivityEvent event) async {
    await _init();
    _events.insert(0, event);
    if (_events.length > 200) {
      _events.removeRange(200, _events.length);
    }
    await _persist();
    _ref.read(activityVersionProvider.notifier).state++;
  }

  Future<void> recordUpload(FileData file) async {
    await recordEvent(
      DriveActivityEvent(
        id: const Uuid().v4(),
        type: DriveActivityType.upload,
        title: 'Uploaded ${file.name}',
        description: 'Encrypted with AES-256-GCM & synced to Telegram',
        timestamp: file.createdAt ?? DateTime.now(),
        fileId: file.id,
        folderId: file.folderId,
        fileName: file.name,
        fileSize: file.size,
        mimeType: file.mimeType,
      ),
    );
  }

  Future<void> recordCreateFolder(FolderData folder) async {
    await recordEvent(
      DriveActivityEvent(
        id: const Uuid().v4(),
        type: DriveActivityType.createFolder,
        title: 'Created folder "${folder.name}"',
        description: 'Directory created in AeroDrive cloud',
        timestamp: folder.createdAt ?? DateTime.now(),
        folderId: folder.id,
        fileName: folder.name,
      ),
    );
  }

  Future<void> recordRename({
    FileData? file,
    FolderData? folder,
    required String oldName,
    required String newName,
  }) async {
    await recordEvent(
      DriveActivityEvent(
        id: const Uuid().v4(),
        type: DriveActivityType.rename,
        title: 'Renamed to "$newName"',
        description: 'Previous name was "$oldName"',
        timestamp: DateTime.now(),
        fileId: file?.id,
        folderId: folder?.id,
        fileName: newName,
      ),
    );
  }

  Future<void> recordColorChange({
    required FolderData folder,
    required String colorHex,
  }) async {
    await recordEvent(
      DriveActivityEvent(
        id: const Uuid().v4(),
        type: DriveActivityType.colorChange,
        title: 'Updated folder color',
        description: 'Applied new theme palette to "${folder.name}"',
        timestamp: DateTime.now(),
        folderId: folder.id,
        fileName: folder.name,
        colorHex: colorHex,
      ),
    );
  }

  Future<void> recordShare({FileData? file, FolderData? folder}) async {
    final name = file?.name ?? folder?.name ?? 'item';
    await recordEvent(
      DriveActivityEvent(
        id: const Uuid().v4(),
        type: DriveActivityType.share,
        title: 'Created share link',
        description: 'Generated secure share link for "$name"',
        timestamp: DateTime.now(),
        fileId: file?.id,
        folderId: folder?.id,
        fileName: name,
      ),
    );
  }

  Future<void> recordTrash({FileData? file, FolderData? folder}) async {
    final name = file?.name ?? folder?.name ?? 'item';
    await recordEvent(
      DriveActivityEvent(
        id: const Uuid().v4(),
        type: DriveActivityType.trash,
        title: 'Moved "$name" to Trash',
        description: 'Item can be restored from Trash bin',
        timestamp: DateTime.now(),
        fileId: file?.id,
        folderId: folder?.id,
        fileName: name,
      ),
    );
  }

  Future<List<DriveActivityEvent>> getEvents({
    FileData? file,
    FolderData? folder,
  }) async {
    await _init();

    // 1. If explicit file, filter by fileId
    if (file != null) {
      final matches = _events.where((e) => e.fileId == file.id).toList();
      if (matches.isEmpty) {
        // Synthesize initial events from file metadata (strictly newest-first)
        final created = file.createdAt ?? DateTime.now();
        final synths = [
          DriveActivityEvent(
            id: 'synth_sync_${file.id}',
            type: DriveActivityType.upload,
            title: 'Synchronized with Telegram Cloud',
            description: 'Stored across data channels',
            timestamp: file.updatedAt ?? created.add(const Duration(seconds: 2)),
            fileId: file.id,
            fileName: file.name,
            fileSize: file.size,
            mimeType: file.mimeType,
          ),
          DriveActivityEvent(
            id: 'synth_enc_${file.id}',
            type: DriveActivityType.upload,
            title: 'Encrypted with AES-256-GCM',
            description: 'Zero-Knowledge payload stored',
            timestamp: created.add(const Duration(seconds: 1)),
            fileId: file.id,
            fileName: file.name,
            fileSize: file.size,
            mimeType: file.mimeType,
          ),
          DriveActivityEvent(
            id: 'synth_upload_${file.id}',
            type: DriveActivityType.upload,
            title: 'Uploaded ${file.name}',
            description: 'File added to AeroDrive',
            timestamp: created,
            fileId: file.id,
            fileName: file.name,
            fileSize: file.size,
            mimeType: file.mimeType,
          ),
        ];
        synths.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return synths;
      }
      matches.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return matches;
    }

    // 2. If explicit folder, combine folder events + child files
    if (folder != null) {
      final db = _ref.read(databaseProvider);
      final recentChildFiles = await (db.select(db.files)
            ..where((f) => f.folderId.equals(folder.id) & f.deletedAt.isNull())
            ..orderBy([(f) => drift.OrderingTerm.desc(f.createdAt)])
            ..limit(10))
          .get();

      final matches = _events.where((e) => e.folderId == folder.id).toList();
      final seenFileIds = matches.map((e) => e.fileId).whereType<String>().toSet();

      final result = List<DriveActivityEvent>.from(matches);

      for (final cf in recentChildFiles) {
        if (!seenFileIds.contains(cf.id)) {
          result.add(
            DriveActivityEvent(
              id: 'synth_cf_${cf.id}',
              type: DriveActivityType.upload,
              title: 'Uploaded ${cf.name}',
              description: 'Added to "${folder.name}"',
              timestamp: cf.createdAt ?? DateTime.now(),
              fileId: cf.id,
              folderId: folder.id,
              fileName: cf.name,
              fileSize: cf.size,
              mimeType: cf.mimeType,
            ),
          );
        }
      }

      // Ensure the "Created folder" creation event exists (using folder's original createdAt)
      final hasFolderCreation = result.any((e) => e.type == DriveActivityType.createFolder);
      if (!hasFolderCreation) {
        result.add(
          DriveActivityEvent(
            id: 'synth_folder_${folder.id}',
            type: DriveActivityType.createFolder,
            title: 'Created folder "${folder.name}"',
            description: 'Directory created in AeroDrive cloud',
            timestamp: folder.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
            folderId: folder.id,
            fileName: folder.name,
          ),
        );
      }

      // Strictly newest-first sorting (Created folder lands at the very bottom)
      result.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return result;
    }

    // 3. Root/Global events: combine recorded events + top recent uploads
    final db = _ref.read(databaseProvider);
    final recentFiles = await (db.select(db.files)
          ..where((f) => f.deletedAt.isNull())
          ..orderBy([(f) => drift.OrderingTerm.desc(f.createdAt)])
          ..limit(20))
        .get();

    final result = List<DriveActivityEvent>.from(_events);
    final seenIds = result.map((e) => e.fileId).whereType<String>().toSet();

    for (final f in recentFiles) {
      if (!seenIds.contains(f.id)) {
        result.add(
          DriveActivityEvent(
            id: 'synth_global_${f.id}',
            type: DriveActivityType.upload,
            title: 'Uploaded ${f.name}',
            description: 'Encrypted with AES-256-GCM',
            timestamp: f.createdAt ?? DateTime.now(),
            fileId: f.id,
            folderId: f.folderId,
            fileName: f.name,
            fileSize: f.size,
            mimeType: f.mimeType,
          ),
        );
      }
    }

    result.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return result;
  }
}

final activityVersionProvider = StateProvider<int>((ref) => 0);

final activityServiceProvider = Provider<ActivityService>((ref) {
  return ActivityService(ref);
});

final driveActivityEventsProvider = FutureProvider.family<List<DriveActivityEvent>, ({String? fileId, String? folderId})>((ref, arg) async {
  ref.watch(activityVersionProvider);
  final service = ref.watch(activityServiceProvider);
  final db = ref.watch(databaseProvider);

  FileData? file;
  FolderData? folder;

  if (arg.fileId != null) {
    file = await (db.select(db.files)..where((f) => f.id.equals(arg.fileId!))).getSingleOrNull();
  } else if (arg.folderId != null) {
    folder = await (db.select(db.folders)..where((f) => f.id.equals(arg.folderId!))).getSingleOrNull();
  }

  return service.getEvents(file: file, folder: folder);
});
