import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/db/database.dart';

/// Provides a singleton instance of the Drift database.
final databaseProvider = Provider<AeroDriveDatabase>((ref) {
  final db = AeroDriveDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Tracks whether the user has navigated past the splash screen.
/// Used to prevent redirecting back to splash after authentication.
final hasNavigatedPastSplashProvider = StateProvider<bool>((ref) => false);
