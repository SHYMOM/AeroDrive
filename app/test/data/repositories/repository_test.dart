import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/data/repositories/chunk_repository.dart';
import 'package:aerodrive/data/repositories/file_repository.dart';
import 'package:aerodrive/data/repositories/folder_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AeroDriveDatabase db;
  late FolderRepository folderRepo;
  late FileRepository fileRepo;
  late ChunkRepository chunkRepo;

  setUp(() {
    db = AeroDriveDatabase(NativeDatabase.memory());
    folderRepo = FolderRepository(db);
    fileRepo = FileRepository(db);
    chunkRepo = ChunkRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('FolderRepository Tests', () {
    test('createFolder limits path to 255 chars', () async {
      // Create a massive string to exceed 255 chars
      final longName = List.filled(300, 'A').join();
      
      expect(
        () => folderRepo.createFolder(name: longName),
        throwsA(isA<FolderNameTooLongException>()),
      );
    });

    test('trashFolder cascading soft delete via CTE', () async {
      final rootId = await folderRepo.createFolder(name: 'Root');
      final childId = await folderRepo.createFolder(name: 'Child', parentId: rootId);
      final grandChildId = await folderRepo.createFolder(name: 'GrandChild', parentId: childId);
      
      // Add a file deep inside
      await fileRepo.createFileEntry(
        name: 'test.txt',
        sha256Hash: 'hash123',
        sizeBytes: 100,
        mimeType: 'text/plain',
        folderId: grandChildId,
      );

      var files = await fileRepo.getFilesInFolder(grandChildId);
      expect(files.length, 1);

      // Trash the root folder
      await folderRepo.trashFolder(rootId);

      // The cascading CTE should have hard-deleted the folders and files since we used DELETE
      final remainingRoot = await folderRepo.getSubfolders(null);
      final remainingChild = await folderRepo.getSubfolders(rootId);
      final remainingGrandChild = await folderRepo.getSubfolders(childId);
      files = await fileRepo.getFilesInFolder(grandChildId);

      expect(remainingRoot.isEmpty, true);
      expect(remainingChild.isEmpty, true);
      expect(remainingGrandChild.isEmpty, true);
      expect(files.isEmpty, true);
    });
  });

  group('FileRepository Deduplication Tests', () {
    test('Zero Re-upload Deduplication works correctly', () async {
      const mockHash = 'deadbeef1234567890';

      // 1. User uploads File A
      final fileAId = await fileRepo.createFileEntry(
        name: 'holiday_video.mp4',
        sha256Hash: mockHash,
        sizeBytes: 1024 * 1024 * 50, // 50MB
        mimeType: 'video/mp4',
      );

      // System chunks File A and stores it in Telegram
      await chunkRepo.insertChunk(
        fileId: fileAId,
        chunkIndex: 0,
        channelId: 1001,
        messageId: 55,
        sizeBytes: 1024 * 1024 * 25,
        hash: 'chunk1hash',
      );
      await chunkRepo.insertChunk(
        fileId: fileAId,
        chunkIndex: 1,
        channelId: 1001,
        messageId: 56,
        sizeBytes: 1024 * 1024 * 25,
        hash: 'chunk2hash',
      );

      final chunksA = await chunkRepo.getChunksForFile(fileAId);
      expect(chunksA.length, 2);

      // 2. User tries to upload the exact same file (File B) into a different folder
      final folderId = await folderRepo.createFolder(name: 'Backups');
      
      final fileBId = await fileRepo.createFileEntry(
        name: 'copy_of_holiday_video.mp4',
        sha256Hash: mockHash,
        sizeBytes: 1024 * 1024 * 50,
        mimeType: 'video/mp4',
        folderId: folderId,
      );

      // Verify that File B was created successfully
      expect(fileBId, isNot(fileAId));

      // Verify Deduplication Magic: File B should instantly have isChunked == true
      // Note: getFileByHash returns the first match.
      // We should really query by ID to check isChunked.
      final allFiles = await fileRepo.getFilesInFolder(folderId);
      final fileBRecord = allFiles.firstWhere((f) => f.id == fileBId);
      
      expect(fileBRecord.isChunked, true);

      // Verify chunks were cloned
      final chunksB = await chunkRepo.getChunksForFile(fileBId);
      expect(chunksB.length, 2);
      expect(chunksB[0].messageId, 55);
      expect(chunksB[1].messageId, 56);
      expect(chunksB[0].fileId, fileBId); // Cloned chunks point to File B!
    });
  });
}
