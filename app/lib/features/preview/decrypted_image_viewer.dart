import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/logger.dart';
import '../../core/providers.dart';
import '../../core/providers/security_providers.dart';
import '../../core/security/master_key_provider.dart';
import '../../data/crypto/encryption_engine.dart';
import '../../data/db/database.dart';
import '../telegram/telegram_manager.dart';

class DecryptedImageViewer extends ConsumerStatefulWidget {

  const DecryptedImageViewer({super.key, required this.file});
  final FileData file;

  @override
  ConsumerState<DecryptedImageViewer> createState() => _DecryptedImageViewerState();
}

class _DecryptedImageViewerState extends ConsumerState<DecryptedImageViewer> {
  Uint8List? _decryptedBytes;
  bool _isLoading = true;
  String? _error;
  final TransformationController _transformationController = TransformationController();
  bool _panEnabled = false;
  bool _waitingForUnlock = false;

  @override
  void initState() {
    super.initState();
    _loadDecryptedImage();
    _transformationController.addListener(_onScaleChanged);
  }

  void _onScaleChanged() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final shouldEnablePan = scale > 1.0;
    if (_panEnabled != shouldEnablePan) {
      if (mounted) {
        setState(() => _panEnabled = shouldEnablePan);
      }
    }
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onScaleChanged);
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _loadDecryptedImage() async {
    try {
      final file = widget.file;
      final masterKeyBytes = MasterKeyProvider.instance.key;
      if (masterKeyBytes == null) {
        if (mounted) {
          setState(() { _waitingForUnlock = true; _isLoading = false; });
        }
        return;
      }

      final db = ref.read(databaseProvider);
      final engine = EncryptionEngine();

      final dekResult = await engine.unwrapDek(file.sha256Hash!, masterKeyBytes);
      final dekBytes = dekResult[0]!;
      final ctrIv = dekResult[1];

      // 1. Try thumbnail first (as placeholder)
      final thumb = await (db.select(db.thumbnails)..where((t) => t.fileId.equals(file.id))).getSingleOrNull();
      if (thumb != null && thumb.encryptedBlob.isNotEmpty) {
        AppLogger.info('Loading thumbnail for ${file.id} as placeholder');
        try {
          final cipher = AesGcm.with256bits();
          final secretKey = await cipher.newSecretKeyFromBytes(masterKeyBytes);
          final thumbNonce = thumb.encryptedBlob.sublist(0, 12);
          final thumbMac = Mac(thumb.encryptedBlob.sublist(12, 28));
          final thumbCipherText = thumb.encryptedBlob.sublist(28);
          final thumbPlain = await cipher.decrypt(
            SecretBox(thumbCipherText, nonce: thumbNonce, mac: thumbMac),
            secretKey: secretKey,
          );
          if (mounted) {
            setState(() {
              _decryptedBytes = Uint8List.fromList(thumbPlain);
              _isLoading = false;
            });
          }
        } catch (e) {
          AppLogger.error('Failed to decrypt thumbnail', e);
        }
      }

      // 2. Load the original chunks in the background/foreground
      final chunks = await (db.select(db.chunks)
        ..where((c) => c.fileId.equals(file.id))
        ..orderBy([(c) => OrderingTerm.asc(c.chunkIndex)])
      ).get();

      if (chunks.isEmpty) {
        if (_decryptedBytes == null && mounted) {
          setState(() { _error = 'No chunk data found'; _isLoading = false; });
        }
        return;
      }

      final manager = ref.read(telegramManagerProvider.notifier);
      final bytesBuilder = BytesBuilder();
      var processedBytes = 0;

      for (final chunk in chunks) {
        if (chunk.messageId == null || chunk.channelId == null) continue;

        final telegram = manager.getClient('primary');
        final message = await telegram.getMessage(chunk.channelId!, chunk.messageId!);

        final content = message['content'];
        int? remoteFileId;
        if (content != null && content['@type'] == 'messageDocument') {
          remoteFileId = content['document']['document']['id'] as int?;
        }

        if (remoteFileId == null) {
          AppLogger.warning('No remote file ID for chunk ${chunk.chunkIndex}');
          continue;
        }

        final int chunkSize = chunk.size ?? (20 * 1024 * 1024);
        final chunkBytes = await _downloadFullChunk(telegram, remoteFileId, chunkSize);
        if (chunkBytes.isEmpty) {
          AppLogger.warning('Empty chunk data for ${chunk.chunkIndex}');
          continue;
        }

        final decryptedBlock = await engine.decryptBytes(
          data: chunkBytes,
          dekBytes: dekBytes,
          ctrIv: ctrIv,
          globalByteOffset: processedBytes, // CRITICAL: pass offset for CTR mode multi-chunk decryption
        );
        bytesBuilder.add(decryptedBlock);
        processedBytes += decryptedBlock.length;
      }

      final fullBytes = bytesBuilder.toBytes();
      if (fullBytes.isEmpty) {
        if (_decryptedBytes == null && mounted) {
          setState(() { _error = 'Decrypted data is empty'; _isLoading = false; });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _decryptedBytes = fullBytes;
          _isLoading = false;
        });
      }
    } catch (e, s) {
      AppLogger.error('Failed to decrypt image', e, s);
      if (_decryptedBytes == null && mounted) {
        setState(() { _error = 'Failed to decrypt: $e'; _isLoading = false; });
      }
    }
  }

  Future<Uint8List> _downloadFullChunk(dynamic telegram, int fileId, int expectedSize) async {
    final res = await telegram.sendRequest({
      "@type": "downloadFile",
      "file_id": fileId,
      "priority": 32,
      "synchronous": true,
    });
    final file = res['file'] as Map<String, dynamic>? ?? res;
    final local = file['local'] as Map<String, dynamic>?;
    if (local == null) return Uint8List(0);

    final localPath = local['path'] as String?;
    if (localPath == null || localPath.isEmpty) return Uint8List(0);

    // If synchronous download didn't complete, poll with getFile
    if (local['is_downloading_completed'] != true) {
      for (var i = 0; i < 60; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        final getFileRes = await telegram.sendRequest({
          "@type": "getFile",
          "file_id": fileId,
        });
        final getFileLocal = getFileRes['local'] as Map<String, dynamic>?;
        if (getFileLocal != null && getFileLocal['is_downloading_completed'] == true) {
          final path = getFileLocal['path'] as String?;
          if (path != null && path.isNotEmpty) {
            final f = File(path);
            if (await f.exists()) return f.readAsBytes();
          }
          break;
        }
        // Also check if download failed
        if (getFileRes['@type'] == 'error') break;
      }
      return Uint8List(0);
    }

    final f = File(localPath);
    if (!await f.exists()) return Uint8List(0);
    return f.readAsBytes();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(isAppUnlockedProvider, (prev, next) {
      if (next && _waitingForUnlock) {
        setState(() { _waitingForUnlock = false; _isLoading = true; _error = null; });
        _loadDecryptedImage();
      } else if (!next) {
        setState(() => _waitingForUnlock = true);
      }
    });

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_waitingForUnlock) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock, size: 64, color: Colors.white30),
            const SizedBox(height: 16),
            const Text('Encryption Error', style: TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text(
              'Your secure connection could not be established.\nPlease restart the application.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      );
    }    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
        ),
      );
    }

    if (_decryptedBytes != null) {
      return InteractiveViewer(
        transformationController: _transformationController,
        panEnabled: _panEnabled,
        child: Center(
          child: Image.memory(
            _decryptedBytes!,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.broken_image, size: 64, color: Colors.white24),
                  const SizedBox(height: 16),
                  Text('Failed to render image: $error'),
                ],
              ),
          ),
        ),
      );
    }

    return const Center(child: Text('No data'));
  }
}
