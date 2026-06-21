import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/data/repositories/folder_repository.dart';
import 'package:aerodrive/data/repositories/file_repository.dart';
import 'package:aerodrive/data/repositories/chunk_repository.dart';

final folderRepositoryProvider = Provider<FolderRepository>((ref) {
  return FolderRepository(ref.watch(databaseProvider));
});

final fileRepositoryProvider = Provider<FileRepository>((ref) {
  return FileRepository(ref.watch(databaseProvider));
});

final chunkRepositoryProvider = Provider<ChunkRepository>((ref) {
  return ChunkRepository(ref.watch(databaseProvider));
});
