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
import 'package:aerodrive/domain/streaming/streaming_server.dart';

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

      final streamingServer = ref.read(streamingServerProvider);
      final url = 'http://127.0.0.1:${streamingServer.port}/stream?id=${widget.file.id}';
      
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

