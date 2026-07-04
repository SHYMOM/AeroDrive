import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/db/database.dart';
import 'tag_service.dart';

final fileTagsProvider = FutureProvider.family<List<Tag>, String>((ref, fileId) async {
  final service = ref.watch(tagServiceProvider);
  // By watching, we ensure updates happen, but we need a stream to update UI in real-time.
  // Actually, let's use a StreamProvider to auto-refresh chips when tags are changed!
  return service.getTagsForFile(fileId);
});

// Better to use StreamProvider for real-time UI updates
final fileTagsStreamProvider = StreamProvider.family<List<Tag>, String>((ref, fileId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.tags).join([
    drift.innerJoin(db.fileTags, db.fileTags.tagId.equalsExp(db.tags.id)),
  ])..where(db.fileTags.fileId.equals(fileId))).watch().map((results) => results.map((row) => row.readTable(db.tags)).toList());
});
