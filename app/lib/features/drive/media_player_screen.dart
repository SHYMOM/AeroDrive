import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:cryptography/cryptography.dart';

import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/core/providers/security_providers.dart';
import 'package:aerodrive/features/telegram/telegram_service.dart';
import 'package:aerodrive/core/providers.dart';

class MediaPlayerScreen extends ConsumerStatefulWidget {
  final FileData file;

  const MediaPlayerScreen({
    super.key,
    required this.file,
  });

  @override
  ConsumerState<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends ConsumerState<MediaPlayerScreen> {
  Player? player;
  VideoController? controller;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  Future<void> _initStream() async {
    try {
      final kekBytes = ref.read(masterKeyProvider);
      if (kekBytes == null) {
        throw Exception("Vault is locked");
      }

      final fileHash = widget.file.sha256Hash;
      if (fileHash == null || fileHash.isEmpty) {
        throw Exception("File is not fully uploaded");
      }

      // Unwrap DEK
      final cipher = AesGcm.with256bits();
      final secretKey = await cipher.newSecretKeyFromBytes(kekBytes);
      
      final parts = fileHash.split(':');
      final nonce = base64Decode(parts[0]);
      final mac = base64Decode(parts[1]);
      final cipherText = base64Decode(parts[2]);

      final dekBytes = await cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: secretKey,
      );

      final db = ref.read(databaseProvider);
      final dbChunk = await (db.select(db.chunks)..where((c) => c.fileId.equals(widget.file.id))).getSingleOrNull();
      if (dbChunk == null || dbChunk.messageId == null || dbChunk.channelId == null) {
        throw Exception("Chunk metadata missing");
      }
      
      final telegram = ref.read(telegramServiceProvider.notifier);
      final message = await telegram.getMessage(dbChunk.channelId!, dbChunk.messageId!);
      final content = message['content'];
      if (content == null || content['@type'] != 'messageDocument') {
        throw Exception("Message is not a document");
      }
      final remoteFileId = content['document']['document']['id'];

      final dekBase64 = base64Encode(dekBytes);
      final url = 'http://localhost:8080/stream?file_id=$remoteFileId&size=${widget.file.size}&dek=${Uri.encodeComponent(dekBase64)}';
      
      player = Player();
      controller = VideoController(player!);
      await player!.open(Media(url));

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black45,
        elevation: 0,
        title: Text(widget.file.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : _error != null
                ? Text(_error!, style: const TextStyle(color: Colors.red))
                : Video(controller: controller!),
      ),
    );
  }
}

