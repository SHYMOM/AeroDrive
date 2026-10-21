import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/domain/streaming/streaming_server.dart';

void main() {
  group('StreamingServer Chunk Size & Plain Size Calculations', () {
    test('Calculates exact plaintext size for AES-GCM audio chunk with 28 bytes overhead', () {
      final container = ProviderContainer();
      final server = container.read(streamingServerProvider);

      // 3681068 is the encrypted size of a 3681040 byte audio file with 12B nonce + 16B MAC
      final rawChunks = [
        ChunkData(
          id: 'chunk-1',
          fileId: 'file-1',
          chunkIndex: 0,
          size: 3681068,
          messageId: 100,
          channelId: 200,
        ),
      ];

      final chunkInfos = server.buildChunkInfosForTesting(
        rawChunks: rawChunks,
        isCtr: false,
        dbFileSize: 3681068,
        totalChunks: 1,
      );

      expect(chunkInfos.length, equals(1));
      expect(chunkInfos.first.plainSize, equals(3681040));
      expect(chunkInfos.first.start, equals(0));
      expect(chunkInfos.first.end, equals(3681039));
      expect(chunkInfos.first.end + 1, equals(3681040));
    });

    test('Calculates exact plaintext size for multi-block AES-GCM chunk', () {
      final container = ProviderContainer();
      final server = container.read(streamingServerProvider);

      // 2 full 4MB blocks (4194304 * 2 = 8388608) + 2 blocks of 28B overhead (56B) + 1000B remainder + 28B overhead = 8389692B
      const plainSize = (2 * 4 * 1024 * 1024) + 1000;
      const cipherSize = plainSize + (3 * 28);

      final rawChunks = [
        ChunkData(
          id: 'chunk-1',
          fileId: 'file-2',
          chunkIndex: 0,
          size: cipherSize,
          messageId: 101,
          channelId: 201,
        ),
      ];

      final chunkInfos = server.buildChunkInfosForTesting(
        rawChunks: rawChunks,
        isCtr: false,
        dbFileSize: cipherSize,
        totalChunks: 1,
      );

      expect(chunkInfos.first.plainSize, equals(plainSize));
      expect(chunkInfos.first.end + 1, equals(plainSize));
    });

    test('Preserves byte-for-byte size in AES-CTR mode (0 bytes crypto overhead)', () {
      final container = ProviderContainer();
      final server = container.read(streamingServerProvider);

      const videoSize = 15490918;
      final rawChunks = [
        ChunkData(
          id: 'chunk-1',
          fileId: 'file-3',
          chunkIndex: 0,
          size: videoSize,
          messageId: 102,
          channelId: 202,
        ),
      ];

      final chunkInfos = server.buildChunkInfosForTesting(
        rawChunks: rawChunks,
        isCtr: true,
        dbFileSize: videoSize,
        totalChunks: 1,
      );

      expect(chunkInfos.first.plainSize, equals(videoSize));
      expect(chunkInfos.first.end + 1, equals(videoSize));
    });
  });
}
