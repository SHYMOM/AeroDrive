import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:cryptography/cryptography.dart';

import 'package:aerodrive/core/logger.dart';
import 'package:aerodrive/features/telegram/telegram_service.dart';
import 'package:aerodrive/core/providers/security_providers.dart';

class StreamingServer {
  final Ref ref;
  HttpServer? _server;
  static const int _plainBlockSize = 4 * 1024 * 1024; // 4 MB
  static const int _cryptoBlockSize = _plainBlockSize + 12 + 16; // 4MB + 12 (nonce) + 16 (mac)

  StreamingServer(this.ref);

  Future<void> start() async {
    if (_server != null) return;
    
    final router = Router();
    router.get('/stream', _handleStream);

    _server = await shelf_io.serve(router.call, InternetAddress.loopbackIPv4, 8080);
    AppLogger.info('Streaming server running on http://localhost:8080');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<Response> _handleStream(Request request) async {
    try {
      final fileIdStr = request.url.queryParameters['file_id'];
      final sizeStr = request.url.queryParameters['size'];
      final dekBase64 = request.url.queryParameters['dek'];

      if (fileIdStr == null || sizeStr == null || dekBase64 == null) {
        return Response(400, body: 'Missing required parameters');
      }

      final fileId = int.parse(fileIdStr);
      final plainFileSize = int.parse(sizeStr);
      final dekBytes = base64Decode(dekBase64);

      // Handle Range Header
      final rangeHeader = request.headers['range'];
      int start = 0;
      int end = plainFileSize - 1;

      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        final parts = rangeHeader.substring(6).split('-');
        if (parts[0].isNotEmpty) start = int.parse(parts[0]);
        if (parts.length > 1 && parts[1].isNotEmpty) {
          end = int.parse(parts[1]);
        }
      }

      if (start >= plainFileSize) {
        return Response(416, headers: {'Content-Range': 'bytes */$plainFileSize'});
      }

      end = min(end, plainFileSize - 1);
      final contentLength = end - start + 1;

      final headers = {
        'Content-Type': 'video/mp4', // Default, player will probe
        'Accept-Ranges': 'bytes',
        'Content-Length': contentLength.toString(),
        'Content-Range': 'bytes $start-$end/$plainFileSize',
      };

      // Create stream
      final stream = _createDecryptionStream(fileId, start, end, plainFileSize, dekBytes);

      return Response(
        206, // Partial Content
        headers: headers,
        body: stream,
      );
    } catch (e, s) {
      AppLogger.error('Streaming error', e, s);
      return Response.internalServerError(body: e.toString());
    }
  }

  Stream<List<int>> _createDecryptionStream(
    int fileId,
    int startPlain,
    int endPlain,
    int totalPlainSize,
    List<int> dekBytes,
  ) async* {
    final telegram = ref.read(telegramServiceProvider.notifier);
    final cipher = AesGcm.with256bits();
    final secretKey = await cipher.newSecretKeyFromBytes(dekBytes);

    int currentPlainOffset = startPlain;

    while (currentPlainOffset <= endPlain) {
      final blockIndex = currentPlainOffset ~/ _plainBlockSize;
      final blockStartPlain = blockIndex * _plainBlockSize;
      
      final blockStartCrypto = blockIndex * _cryptoBlockSize;
      
      // Request this crypto block from Telegram
      // We must read exactly one full crypto block (or remainder of file) to decrypt it
      // Wait, we just need to get the file path.
      
      final tgFile = await telegram.sendRequest({
        "@type": "getFile",
        "file_id": fileId
      });

      // Issue download command for this specific chunk
      await telegram.sendRequest({
        "@type": "downloadFile",
        "file_id": fileId,
        "priority": 32,
        "offset": blockStartCrypto,
        "limit": _cryptoBlockSize,
        "synchronous": true
      });

      // We need to wait until the bytes are downloaded to disk.
      final localPath = await _waitForFileChunk(telegram, fileId, blockStartCrypto, _cryptoBlockSize);
      if (localPath == null) {
        throw Exception("Failed to download chunk");
      }

      // Read the encrypted block from disk
      final file = File(localPath);
      final randomAccess = await file.open(mode: FileMode.read);
      await randomAccess.setPosition(blockStartCrypto);
      
      // Determine how many crypto bytes to read (last block might be smaller)
      // The total crypto size isn't easily known, but we can read up to _cryptoBlockSize
      final cryptoBytes = await randomAccess.read(_cryptoBlockSize);
      await randomAccess.close();

      if (cryptoBytes.length < 28) {
         throw Exception("Crypto chunk too small");
      }

      final nonce = cryptoBytes.sublist(0, 12);
      final macBytes = cryptoBytes.sublist(12, 28);
      final cipherText = cryptoBytes.sublist(28);

      final decryptedData = await cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
        secretKey: secretKey,
      );

      // Slice out the requested portion from this decrypted block
      final offsetInBlock = currentPlainOffset - blockStartPlain;
      final remainingRequested = endPlain - currentPlainOffset + 1;
      
      final chunkToSend = decryptedData.sublist(
        offsetInBlock,
        min(decryptedData.length, offsetInBlock + remainingRequested),
      );

      yield chunkToSend;
      
      currentPlainOffset += chunkToSend.length;
    }
  }

  Future<String?> _waitForFileChunk(TelegramService telegram, int fileId, int offset, int limit) async {
    // Basic polling loop to check if the chunk is downloaded in TDLib's local file
    // In a production app, we would listen to updateFile events for better efficiency
    for (int i = 0; i < 50; i++) {
      final fileInfo = await telegram.sendRequest({
        "@type": "getFile",
        "file_id": fileId
      });
      
      final localPath = fileInfo['local']['path'];
      final downloadedSize = fileInfo['local']['downloaded_size'];
      final isCompleted = fileInfo['local']['is_downloading_completed'];

      // If we have a local path, let's check if the bytes we need are present
      if (localPath != null && localPath.toString().isNotEmpty) {
        final file = File(localPath);
        if (await file.exists()) {
           final size = await file.length();
           // TDLib downloads might not be strictly sequential if requested with offset
           // But generally if size > offset + 28, we might have it.
           // A safer check is to use readFilePart which fails if not present
           try {
              final partInfo = await telegram.sendRequest({
                "@type": "readFilePart",
                "file_id": fileId,
                "offset": offset,
                "count": min(limit, 28) // Try to read just the header
              });
              if (partInfo['data'] != null && partInfo['data'].toString().isNotEmpty) {
                 return localPath;
              }
           } catch(e) {
              // Not ready
           }
        }
      }
      
      if (isCompleted == true && localPath != null) {
        return localPath;
      }
      
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return null;
  }
}

final streamingServerProvider = Provider<StreamingServer>((ref) {
  return StreamingServer(ref);
});
