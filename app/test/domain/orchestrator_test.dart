import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aerodrive/domain/upload_orchestrator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UploadOrchestrator Tests', () {
    test('Adaptive chunk sizing calculates correct chunk sizes', () {
      const mb = 1024 * 1024;

      // <= 20MB -> single chunk
      expect(UploadOrchestrator.getOptimalChunkSize(5 * mb), 5 * mb);
      expect(UploadOrchestrator.getOptimalChunkSize(20 * mb), 20 * mb);

      // <= 500MB -> 20MB chunks
      expect(UploadOrchestrator.getOptimalChunkSize(100 * mb), 20 * mb);
      expect(UploadOrchestrator.getOptimalChunkSize(500 * mb), 20 * mb);

      // <= 2GB -> 25MB chunks
      expect(UploadOrchestrator.getOptimalChunkSize(1000 * mb), 25 * mb);
      expect(UploadOrchestrator.getOptimalChunkSize(2048 * mb), 25 * mb);

      // > 2GB (e.g. 4GB) -> 50MB chunks
      expect(UploadOrchestrator.getOptimalChunkSize(3000 * mb), 50 * mb);
      expect(UploadOrchestrator.getOptimalChunkSize(4096 * mb), 50 * mb);
    });

    test('computeFileHash computes correct SHA-256 in background isolate', () async {
      final tempDir = Directory.systemTemp.createTempSync('hash_test');
      final testFile = File('${tempDir.path}/test_hash.bin');

      final random = Random(42);
      final testData = List<int>.generate(2 * 1024 * 1024, (_) => random.nextInt(256));
      await testFile.writeAsBytes(testData);

      final hashResult = await UploadOrchestrator.computeFileHash(testFile);

      final expectedHash = await Sha256().hash(testData);
      final expectedHex = expectedHash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      expect(hashResult, equals(expectedHex));

      tempDir.deleteSync(recursive: true);
    });

    test('processSingleChunkForUpload encrypts chunk to disk', () async {
      final tempDir = Directory.systemTemp.createTempSync('chunk_test');
      final sourceFile = File('${tempDir.path}/source.bin');
      final chunkFile = '${tempDir.path}/chunk_0.bin';

      final random = Random(77);
      final testData = List<int>.generate(1024 * 1024, (_) => random.nextInt(256));
      await sourceFile.writeAsBytes(testData);

      final dekBytes = List<int>.generate(32, (_) => random.nextInt(256));
      final orchestrator = UploadOrchestrator();

      final outPath = await orchestrator.processSingleChunkForUpload(
        sourceFile: sourceFile,
        outputFilePath: chunkFile,
        startOffset: 0,
        chunkLength: 512 * 1024,
        dekBytes: dekBytes,
      );

      expect(File(outPath).existsSync(), isTrue);
      // GCM adds 12-byte nonce + 16-byte MAC
      expect(File(outPath).lengthSync(), equals(512 * 1024 + 28));

      tempDir.deleteSync(recursive: true);
    });
  });
}
