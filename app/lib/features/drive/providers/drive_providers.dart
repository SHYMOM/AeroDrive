import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/providers/security_providers.dart';
import '../../../data/db/database.dart';

/// Manages the current folder ID being viewed by the user.
/// null = Root (Vault)
final currentFolderIdProvider = StateProvider<String?>((ref) => null);

/// Filter Drive screen to only show favorites
final isFavoriteOnlyProvider = StateProvider<bool>((ref) => false);

/// Tracks if we have already checked for a remote config during this session
final configCheckedProvider = StateProvider<bool>((ref) {
  ref.watch(isAppUnlockedProvider);
  return false;
});

/// Manages the breadcrumb path to the current folder.
final breadcrumbsProvider = FutureProvider<List<FolderData>>((ref) async {
  final currentId = ref.watch(currentFolderIdProvider);
  if (currentId == null) return [];

  final db = ref.watch(databaseProvider);

  final List<FolderData> breadcrumbs = [];
  String? iterId = currentId;

  // Traverse upwards to build breadcrumbs
  while (iterId != null) {
    final String safeId = iterId;
    final folder = await (db.select(db.folders)..where((f) => f.id.equals(safeId))).getSingleOrNull();
    if (folder == null) break;

    breadcrumbs.insert(0, folder);
    iterId = folder.parentId;
  }
  return breadcrumbs;
});

/// Controls whether the UI is in Grid or List view.
final isGridViewProvider = StateProvider<bool>((ref) => true);

/// Synchronous navigation stack: tracks the parent folder ID before each navigation.
/// Used by PopScope to navigate back without async DB calls.
final navigationStackProvider = StateProvider<List<String?>>((ref) => []);

/// Incremented after each rebuild/import to force DriveScreen to refetch.
final dbRebuildVersionProvider = StateProvider<int>((ref) => 0);

enum DriveSortCriteria { name, date, size, type }
enum DriveSortOrder { ascending, descending }
enum DriveSortCategory { none, images, videos, documents, programs, others }

class DriveSortOption {

  const DriveSortOption({
    required this.criteria,
    required this.order,
    required this.categoryPriority,
  });
  final DriveSortCriteria criteria;
  final DriveSortOrder order;
  final DriveSortCategory categoryPriority;

  DriveSortOption copyWith({
    DriveSortCriteria? criteria,
    DriveSortOrder? order,
    DriveSortCategory? categoryPriority,
  }) => DriveSortOption(
      criteria: criteria ?? this.criteria,
      order: order ?? this.order,
      categoryPriority: categoryPriority ?? this.categoryPriority,
    );
}

final driveSortOptionProvider = StateProvider<DriveSortOption>((ref) => const DriveSortOption(
  criteria: DriveSortCriteria.name,
  order: DriveSortOrder.ascending,
  categoryPriority: DriveSortCategory.none,
));

/// Fetches the contents of the current folder, watches rebuild version, and applies sorting.
final folderContentsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(dbRebuildVersionProvider);
  final folderRepo = ref.watch(folderRepositoryProvider);
  final currentId = ref.watch(currentFolderIdProvider);
  final isFavOnly = ref.watch(isFavoriteOnlyProvider);
  
  Map<String, dynamic> contents;
  if (isFavOnly) {
    final db = ref.read(databaseProvider);
    final favFolders = await (db.select(db.folders)..where((f) => f.isFavorite.equals(true) & f.deletedAt.isNull())).get();
    final favFiles = await (db.select(db.files)..where((f) => f.isFavorite.equals(true) & f.deletedAt.isNull())).get();
    contents = {
      'folders': favFolders,
      'files': favFiles,
    };
  } else {
    contents = await folderRepo.getFolderContents(currentId);
  }

  final folders = List<FolderData>.from(contents['folders'] ?? []);
  final files = List<FileData>.from(contents['files'] ?? []);

  final sortOption = ref.watch(driveSortOptionProvider);

  // Helper to categorize files
  bool isImage(FileData f) => f.mimeType?.startsWith('image/') == true;
  bool isVideo(FileData f) => f.mimeType?.startsWith('video/') == true;
  bool isDoc(FileData f) {
    final m = (f.mimeType ?? '').toLowerCase();
    return m.contains('pdf') || m.startsWith('text/') || m.contains('document') || m.contains('msword') || m.contains('spreadsheet') || m.contains('presentation') || m.contains('excel') || m.contains('powerpoint') || m.contains('word');
  }
  bool isProgram(FileData f) {
    final m = (f.mimeType ?? '').toLowerCase();
    final name = f.name.toLowerCase();
    return m.contains('x-msdownload') || m.contains('octet-stream') || name.endsWith('.exe') || name.endsWith('.msi') || name.endsWith('.apk') || name.endsWith('.bat') || name.endsWith('.sh');
  }
  bool isOther(FileData f) => !isImage(f) && !isVideo(f) && !isDoc(f) && !isProgram(f);

  bool hasPriority(FileData f) {
    switch (sortOption.categoryPriority) {
      case DriveSortCategory.images: return isImage(f);
      case DriveSortCategory.videos: return isVideo(f);
      case DriveSortCategory.documents: return isDoc(f);
      case DriveSortCategory.programs: return isProgram(f);
      case DriveSortCategory.others: return isOther(f);
      case DriveSortCategory.none: return false;
    }
  }

  // Sort Folders
  folders.sort((a, b) {
    int cmp;
    switch (sortOption.criteria) {
      case DriveSortCriteria.name:
        cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case DriveSortCriteria.date:
        final da = a.createdAt ?? DateTime(0);
        final db = b.createdAt ?? DateTime(0);
        cmp = da.compareTo(db);
      default:
        cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }
    return sortOption.order == DriveSortOrder.ascending ? cmp : -cmp;
  });

  // Sort Files
  files.sort((a, b) {
    // 1. Category Priority
    if (sortOption.categoryPriority != DriveSortCategory.none) {
      final aPriority = hasPriority(a);
      final bPriority = hasPriority(b);
      if (aPriority && !bPriority) return -1;
      if (!aPriority && bPriority) return 1;
    }

    // 2. Main Criteria
    int cmp;
    switch (sortOption.criteria) {
      case DriveSortCriteria.name:
        cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case DriveSortCriteria.date:
        final da = a.createdAt ?? DateTime(0);
        final db = b.createdAt ?? DateTime(0);
        cmp = da.compareTo(db);
      case DriveSortCriteria.size:
        cmp = (a.size ?? 0).compareTo(b.size ?? 0);
      case DriveSortCriteria.type:
        final extA = a.name.contains('.') ? a.name.split('.').last.toLowerCase() : '';
        final extB = b.name.contains('.') ? b.name.split('.').last.toLowerCase() : '';
        cmp = extA.compareTo(extB);
        if (cmp == 0) {
          cmp = (a.mimeType ?? '').toLowerCase().compareTo((b.mimeType ?? '').toLowerCase());
        }
    }

    return sortOption.order == DriveSortOrder.ascending ? cmp : -cmp;
  });

  return {
    'folders': folders,
    'files': files,
  };
});

/// Recursively calculates the size of a folder and all its nested subfolders.
Future<int> calculateFolderSize(String folderId, AeroDriveDatabase db) async {
  var totalSize = 0;
  
  // Get all files directly in this folder
  final directFiles = await (db.select(db.files)
    ..where((f) => f.folderId.equals(folderId) & f.deletedAt.isNull())
  ).get();
  for (final file in directFiles) {
    totalSize += file.size ?? 0;
  }
  
  // Get all subfolders
  final subfolders = await (db.select(db.folders)
    ..where((f) => f.parentId.equals(folderId) & f.deletedAt.isNull())
  ).get();
  for (final sub in subfolders) {
    totalSize += await calculateFolderSize(sub.id, db);
  }
  
  return totalSize;
}

/// Provider family to recursively calculate size of a folder.
final folderSizeProvider = FutureProvider.family<int, String>((ref, folderId) async {
  final db = ref.watch(databaseProvider);
  ref.watch(dbRebuildVersionProvider); // Re-calculate size when DB rebuilds
  return calculateFolderSize(folderId, db);
});

/// Fetches the real counts of categories for the Quick Access dashboard.
final quickAccessStatsProvider = FutureProvider<Map<String, int>>((ref) async {
  final db = ref.watch(databaseProvider);
  ref.watch(dbRebuildVersionProvider); // Re-calculate stats on changes
  
  final files = await (db.select(db.files)..where((f) => f.deletedAt.isNull())).get();
  final folders = await (db.select(db.folders)..where((f) => f.deletedAt.isNull())).get();

  var imageCount = 0;
  var videoCount = 0;
  var audioCount = 0;
  var docCount = 0;

  for (final f in files) {
    final mime = (f.mimeType ?? '').toLowerCase();
    if (mime.startsWith('image/')) {
      imageCount++;
    } else if (mime.startsWith('video/')) {
      videoCount++;
    } else if (mime.startsWith('audio/')) {
      audioCount++;
    } else if (mime.contains('pdf') || mime.startsWith('text/') || mime.contains('document') || mime.contains('msword') || mime.contains('spreadsheet') || mime.contains('presentation') || mime.contains('excel') || mime.contains('powerpoint') || mime.contains('word')) {
      docCount++;
    }
  }

  final favFilesCount = files.where((f) => f.isFavorite).length;
  final favFoldersCount = folders.where((f) => f.isFavorite).length;

  return {
    'Favorites': favFilesCount + favFoldersCount,
    'Images': imageCount,
    'Videos': videoCount,
    'Documents': docCount,
    'Audios': audioCount,
  };
});

/// Providers to manage multiple item selection mode.
final selectedItemsProvider = StateProvider<Set<String>>((ref) => {});
final isSelectionModeProvider = StateProvider<bool>((ref) => false);

/// Finds a cover file (image or video) recursively or directly inside a folder.
final folderCoverFileProvider = FutureProvider.family<FileData?, String>((ref, folderId) async {
  final db = ref.watch(databaseProvider);
  ref.watch(dbRebuildVersionProvider);
  
  // Try to find an image or video inside the folder directly
  final directCover = await (db.select(db.files)
    ..where((f) => f.folderId.equals(folderId) & (f.mimeType.like('image/%') | f.mimeType.like('video/%')))
    ..where((f) => f.deletedAt.isNull())
    ..limit(1)
  ).getSingleOrNull();
  
  if (directCover != null) return directCover;
  
  // If not found directly, check subfolders
  final subfolders = await (db.select(db.folders)..where((f) => f.parentId.equals(folderId) & f.deletedAt.isNull())).get();
  for (final sub in subfolders) {
    final subCover = await (db.select(db.files)
      ..where((f) => f.folderId.equals(sub.id) & (f.mimeType.like('image/%') | f.mimeType.like('video/%')))
      ..where((f) => f.deletedAt.isNull())
      ..limit(1)
    ).getSingleOrNull();
    if (subCover != null) return subCover;
  }
  
  // Try any file in the folder if no image/video exists
  final anyFile = await (db.select(db.files)
    ..where((f) => f.folderId.equals(folderId))
    ..where((f) => f.deletedAt.isNull())
    ..limit(1)
  ).getSingleOrNull();
  
  return anyFile;
});

/// Computes the total number of files and folders inside a directory.
final folderItemsCountProvider = FutureProvider.family<int, String>((ref, folderId) async {
  final db = ref.watch(databaseProvider);
  ref.watch(dbRebuildVersionProvider);
  
  final files = await (db.select(db.files)..where((f) => f.folderId.equals(folderId) & f.deletedAt.isNull())).get();
  final subfolders = await (db.select(db.folders)..where((f) => f.parentId.equals(folderId) & f.deletedAt.isNull())).get();
  
  return files.length + subfolders.length;
});

/// Calculates total storage used based on Chunk size sum
final totalStorageProvider = StreamProvider.autoDispose<int>((ref) {
  final db = ref.watch(databaseProvider);
  ref.watch(dbRebuildVersionProvider);

  return db.customSelect('SELECT SUM(size) AS total FROM chunks;').watchSingle().map((row) => row.read<int>('total') ?? 0);
});

/// Reads the saved file icon style setting ('Minimal', 'Filled', 'Colored', 'Outlined').
/// Watches [settingsUpdateProvider] so changing the setting in Appearance triggers a refresh.
final fileIconStyleProvider = FutureProvider<String>((ref) async {
  ref.watch(settingsUpdateProvider);
  final settings = ref.read(settingsRepositoryProvider);
  return await settings.getSetting('app_file_icon_style') ?? 'Colored';
});