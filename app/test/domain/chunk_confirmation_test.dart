import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aerodrive/data/db/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AeroDriveDatabase db;

  setUp(() {
    db = AeroDriveDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Chunk Confirmation & Lifecycle Integrity Tests', () {
    test('Chunks initially inserted with null messageId are unconfirmed', () async {
      const fileId = 'test-file-1';
      const totalChunks = 3;

      // Insert file record
      await db.into(db.files).insert(
        FilesCompanion.insert(
          id: fileId,
          name: 'test_56mb.rar',
          size: const drift.Value(56 * 1024 * 1024),
          totalChunks: const drift.Value(totalChunks),
          isChunked: const drift.Value(true),
          createdAt: drift.Value(DateTime.now()),
        ),
      );

      // Insert 3 chunks, initially with messageId: null (waiting for TDLib updateMessageSendSucceeded)
      for (var i = 0; i < totalChunks; i++) {
        await db.into(db.chunks).insert(
          ChunksCompanion.insert(
            id: 'chunk-$i',
            fileId: const drift.Value(fileId),
            chunkIndex: drift.Value(i),
            channelId: const drift.Value(1001),
            messageId: const drift.Value(null),
            size: const drift.Value(20 * 1024 * 1024),
          ),
        );
      }

      final chunks = await (db.select(db.chunks)..where((c) => c.fileId.equals(fileId))).get();
      expect(chunks.length, equals(3));

      // At this stage, 0 chunks are confirmed with real message IDs
      final confirmedChunks = chunks.where((c) => c.messageId != null && c.messageId! > 0).toList();
      expect(confirmedChunks.length, equals(0));

      final confirmedIndices = confirmedChunks.map((c) => c.chunkIndex).whereType<int>().toSet();
      final allIndicesConfirmed = List.generate(totalChunks, (i) => i).every((idx) => confirmedIndices.contains(idx));
      expect(allIndicesConfirmed, isFalse);
    });

    test('Partial chunk confirmation does not allow finalization', () async {
      const fileId = 'test-file-2';
      const totalChunks = 3;

      await db.into(db.files).insert(
        FilesCompanion.insert(
          id: fileId,
          name: 'partial_upload.rar',
          size: const drift.Value(56 * 1024 * 1024),
          totalChunks: const drift.Value(totalChunks),
          isChunked: const drift.Value(true),
          createdAt: drift.Value(DateTime.now()),
        ),
      );

      for (var i = 0; i < totalChunks; i++) {
        await db.into(db.chunks).insert(
          ChunksCompanion.insert(
            id: 'chunk-$fileId-$i',
            fileId: const drift.Value(fileId),
            chunkIndex: drift.Value(i),
            channelId: const drift.Value(1001),
            messageId: const drift.Value(null),
            size: const drift.Value(20 * 1024 * 1024),
          ),
        );
      }

      // Simulate updateMessageSendSucceeded for chunk 0 and chunk 1 only
      await (db.update(db.chunks)
        ..where((c) => c.fileId.equals(fileId))
        ..where((c) => c.chunkIndex.equals(0))
      ).write(const ChunksCompanion(messageId: drift.Value(42)));

      await (db.update(db.chunks)
        ..where((c) => c.fileId.equals(fileId))
        ..where((c) => c.chunkIndex.equals(1))
      ).write(const ChunksCompanion(messageId: drift.Value(43)));

      final chunks = await (db.select(db.chunks)..where((c) => c.fileId.equals(fileId))).get();
      final confirmedChunks = chunks.where((c) => c.messageId != null && c.messageId! > 0).toList();
      expect(confirmedChunks.length, equals(2));

      final confirmedIndices = confirmedChunks.map((c) => c.chunkIndex).whereType<int>().toSet();
      final allIndicesConfirmed = List.generate(totalChunks, (i) => i).every((idx) => confirmedIndices.contains(idx));
      // Chunk 2 is still null, so allIndicesConfirmed MUST be false!
      expect(allIndicesConfirmed, isFalse);
    });

    test('All chunks confirmed allows finalization and valid download', () async {
      const fileId = 'test-file-3';
      const totalChunks = 3;

      await db.into(db.files).insert(
        FilesCompanion.insert(
          id: fileId,
          name: 'complete_upload.rar',
          size: const drift.Value(56 * 1024 * 1024),
          totalChunks: const drift.Value(totalChunks),
          isChunked: const drift.Value(true),
          createdAt: drift.Value(DateTime.now()),
        ),
      );

      for (var i = 0; i < totalChunks; i++) {
        await db.into(db.chunks).insert(
          ChunksCompanion.insert(
            id: 'chunk-$fileId-$i',
            fileId: const drift.Value(fileId),
            chunkIndex: drift.Value(i),
            channelId: const drift.Value(1001),
            messageId: const drift.Value(null),
            size: const drift.Value(20 * 1024 * 1024),
          ),
        );
      }

      // Simulate updateMessageSendSucceeded for all 3 chunks
      for (var i = 0; i < totalChunks; i++) {
        await (db.update(db.chunks)
          ..where((c) => c.fileId.equals(fileId))
          ..where((c) => c.chunkIndex.equals(i))
        ).write(ChunksCompanion(messageId: drift.Value(100 + i)));
      }

      final chunks = await (db.select(db.chunks)..where((c) => c.fileId.equals(fileId))).get();
      final confirmedChunks = chunks.where((c) => c.messageId != null && c.messageId! > 0).toList();
      expect(confirmedChunks.length, equals(3));

      final confirmedIndices = confirmedChunks.map((c) => c.chunkIndex).whereType<int>().toSet();
      final allIndicesConfirmed = List.generate(totalChunks, (i) => i).every((idx) => confirmedIndices.contains(idx));
      expect(allIndicesConfirmed, isTrue);
    });
  });
}
