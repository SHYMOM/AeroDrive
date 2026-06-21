import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/data/db/database.dart';

/// Provides a singleton instance of the Drift database.
final databaseProvider = Provider<AeroDriveDatabase>((ref) {
  final db = AeroDriveDatabase();
  ref.onDispose(db.close);
  return db;
});
