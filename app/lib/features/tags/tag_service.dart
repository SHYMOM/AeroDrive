import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;
import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/core/providers.dart';

class TagService {
  final Ref _ref;

  TagService(this._ref);

  static const List<String> curatedColors = [
    '#FFB3BA', // Pastel Red
    '#FFDFBA', // Pastel Orange
    '#FFFFBA', // Pastel Yellow
    '#BAFFC9', // Pastel Green
    '#BAE1FF', // Pastel Blue
    '#E0BBE4', // Pastel Purple
    '#957DAD', // Muted Violet
    '#D291BC', // Muted Pink
    '#FEC8D8', // Soft Pink
    '#FFDFD3', // Peach
    '#A8E6CF', // Mint
    '#DCEDC1', // Lime
  ];

  Future<Tag> getOrCreateTag(String name, {String? hexColor}) async {
    final db = _ref.read(databaseProvider);
    final normalizedName = name.trim();

    final existingTag = await (db.select(db.tags)..where((t) => t.name.equals(normalizedName))).getSingleOrNull();
    if (existingTag != null) {
      return existingTag;
    }

    // Determine color
    String finalColor;
    if (hexColor != null && curatedColors.contains(hexColor.toUpperCase())) {
      finalColor = hexColor.toUpperCase();
    } else {
      // Round robin based on current tag count
      final countResult = await db.tags.count().getSingle();
      final index = countResult % curatedColors.length;
      finalColor = curatedColors[index];
    }

    final newTagId = const Uuid().v4();
    final companion = TagsCompanion.insert(
      id: newTagId,
      name: normalizedName,
      color: drift.Value(finalColor),
    );

    await db.into(db.tags).insert(companion);
    return Tag(id: newTagId, name: normalizedName, color: finalColor);
  }

  Future<void> attachTagToFile(String fileId, String tagId) async {
    final db = _ref.read(databaseProvider);
    final linkExists = await (db.select(db.fileTags)..where((ft) => ft.fileId.equals(fileId) & ft.tagId.equals(tagId))).getSingleOrNull();
    if (linkExists == null) {
      await db.into(db.fileTags).insert(
        FileTagsCompanion.insert(
          fileId: fileId,
          tagId: tagId,
        )
      );
    }
  }

  Future<void> removeTagFromFile(String fileId, String tagId) async {
    final db = _ref.read(databaseProvider);
    await (db.delete(db.fileTags)..where((ft) => ft.fileId.equals(fileId) & ft.tagId.equals(tagId))).go();
  }

  Future<List<Tag>> getTagsForFile(String fileId) async {
    final db = _ref.read(databaseProvider);
    final query = db.select(db.tags).join([
      drift.innerJoin(db.fileTags, db.fileTags.tagId.equalsExp(db.tags.id)),
    ])..where(db.fileTags.fileId.equals(fileId));

    final results = await query.get();
    return results.map((row) => row.readTable(db.tags)).toList();
  }

  Stream<List<Tag>> watchAllTags() {
    final db = _ref.read(databaseProvider);
    return (db.select(db.tags)..orderBy([(t) => drift.OrderingTerm.asc(t.name)])).watch();
  }
}

final tagServiceProvider = Provider<TagService>((ref) {
  return TagService(ref);
});
