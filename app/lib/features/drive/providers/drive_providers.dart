import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/data/db/database.dart';

/// Manages the current folder ID being viewed by the user. 
/// null = Root (Vault)
final currentFolderIdProvider = StateProvider<String?>((ref) => null);

/// Manages the breadcrumb path to the current folder.
final breadcrumbsProvider = FutureProvider<List<FolderData>>((ref) async {
  final currentId = ref.watch(currentFolderIdProvider);
  if (currentId == null) return [];

  final folderRepo = ref.watch(folderRepositoryProvider);
  final db = ref.watch(databaseProvider);
  
  List<FolderData> breadcrumbs = [];
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

/// Fetches the contents of the current folder.
final folderContentsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final folderRepo = ref.watch(folderRepositoryProvider);
  final currentId = ref.watch(currentFolderIdProvider);
  
  return await folderRepo.getFolderContents(currentId);
});

/// Controls whether the UI is in Grid or List view.
final isGridViewProvider = StateProvider<bool>((ref) => true);
