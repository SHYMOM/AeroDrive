import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../db/database.dart';

class FolderPathTooLongException implements Exception {
  FolderPathTooLongException([this.message = 'Folder path too long. Please use shorter names (max 255 chars).']);
  final String message;
  @override
  String toString() => message;
}

class FolderNameTooLongException implements Exception {
  FolderNameTooLongException([this.message = 'Folder name exceeds 200 characters.']);
  final String message;
  @override
  String toString() => message;
}

class FolderRepository {

  FolderRepository(this._db);
  final AeroDriveDatabase _db;
  final Uuid _uuid = const Uuid();

  /// Recursively resolves the full path string of a folder to enforce limits.
  Future<String> getFolderPath(String? folderId) async {
    if (folderId == null) return '/';
    
    // We traverse up the tree to build the path.
    var path = '';
    String? currentId = folderId;
    
    while (currentId != null) {
      final String safeId = currentId;
      final folder = await (_db.select(_db.folders)..where((f) => f.id.equals(safeId))).getSingleOrNull();
      if (folder == null) break;
      
      path = '/${folder.name}$path';
      currentId = folder.parentId;
    }
    
    return path.isEmpty ? '/' : path;
  }

  Future<String> createFolder({required String name, String? parentId, String? color}) async {
    if (name.length > 200) {
      throw FolderNameTooLongException();
    }

    final parentPath = await getFolderPath(parentId);
    final newPath = parentPath == '/' ? '/$name' : '$parentPath/$name';
    
    if (newPath.length > 255) {
      throw FolderPathTooLongException();
    }

    final id = _uuid.v4();
    await _db.into(_db.folders).insert(
      FoldersCompanion.insert(
        id: id,
        name: name,
        parentId: Value(parentId),
        color: Value(color),
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return id;
  }
  
  Future<void> updateFolder(String folderId, {String? newName, String? newColor}) async {
    final now = DateTime.now();
    await (_db.update(_db.folders)..where((f) => f.id.equals(folderId))).write(
      FoldersCompanion(
        name: newName != null ? Value(newName) : const Value.absent(),
        color: newColor != null ? Value(newColor) : const Value.absent(),
        updatedAt: Value(now),
      ),
    );
  }

  /// Retrieves the immediate children (folders and files) of a given folder.
  Future<List<FolderData>> getSubfolders(String? parentId) {
    final query = _db.select(_db.folders);
    if (parentId == null) {
      query.where((f) => f.parentId.isNull());
    } else {
      query.where((f) => f.parentId.equals(parentId));
    }
    return query.get();
  }

  /// Retrieves both folders and files in a specific directory
  Future<Map<String, dynamic>> getFolderContents(String? parentId) async {
    final foldersQuery = _db.select(_db.folders)
      ..where((f) => parentId == null ? f.parentId.isNull() : f.parentId.equals(parentId))
      ..where((f) => f.deletedAt.isNull());
      
    final filesQuery = _db.select(_db.files)
      ..where((f) => parentId == null ? f.folderId.isNull() : f.folderId.equals(parentId))
      ..where((f) => f.deletedAt.isNull());

    final folders = await foldersQuery.get();
    final files = await filesQuery.get();

    return {
      'folders': folders,
      'files': files,
    };
  }

  /// Soft deletes a folder and ALL its nested subfolders and files using a Recursive CTE.
  Future<void> trashFolder(String folderId) async {
    final int nowSecs = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    const fileQuery = '''
      WITH RECURSIVE folder_tree AS (
        SELECT id FROM folders WHERE id = ?1
        UNION ALL
        SELECT f.id FROM folders f
        INNER JOIN folder_tree ft ON f.parent_id = ft.id
      )
      UPDATE files SET deleted_at = ?2 WHERE folder_id IN folder_tree;
    ''';

    const query = '''
      WITH RECURSIVE folder_tree AS (
        SELECT id FROM folders WHERE id = ?1
        UNION ALL
        SELECT f.id FROM folders f
        INNER JOIN folder_tree ft ON f.parent_id = ft.id
      )
      UPDATE folders SET deleted_at = ?2 WHERE id IN folder_tree;
    ''';

    await _db.customStatement('PRAGMA foreign_keys = ON;');
    await _db.transaction(() async {
      await _db.customStatement(fileQuery, [folderId, nowSecs]);
      await _db.customStatement(query, [folderId, nowSecs]);
    });
  }

  Future<void> restoreFolder(String folderId) async {
    // 1. Get the folder
    final folder = await (_db.select(_db.folders)..where((f) => f.id.equals(folderId))).getSingleOrNull();
    if (folder == null) return;

    // 2. Check for collision in the parent
    if (folder.parentId != null) {
      final existing = await (_db.select(_db.folders)
        ..where((f) => f.parentId.equals(folder.parentId!) & f.name.equals(folder.name) & f.deletedAt.isNull()))
        .getSingleOrNull();
      
      if (existing != null) {
        // Collision exists. Rename.
        await (_db.update(_db.folders)..where((f) => f.id.equals(folderId))).write(
          FoldersCompanion(name: Value('${folder.name} (Restored)')),
        );
      }
    }

    // 3. Recursive soft-restore via CTE
    const fileQuery = '''
      WITH RECURSIVE folder_tree AS (
        SELECT id FROM folders WHERE id = ?
        UNION ALL
        SELECT f.id FROM folders f
        INNER JOIN folder_tree ft ON f.parent_id = ft.id
      )
      UPDATE files SET deleted_at = NULL WHERE folder_id IN folder_tree;
    ''';

    const query = '''
      WITH RECURSIVE folder_tree AS (
        SELECT id FROM folders WHERE id = ?
        UNION ALL
        SELECT f.id FROM folders f
        INNER JOIN folder_tree ft ON f.parent_id = ft.id
      )
      UPDATE folders SET deleted_at = NULL WHERE id IN folder_tree;
    ''';

    await _db.transaction(() async {
      await _db.customStatement(fileQuery, [folderId]);
      await _db.customStatement(query, [folderId]);
    });
  }
}
