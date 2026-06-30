import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/core/providers/security_providers.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/domain/streaming/streaming_server.dart';
import 'package:aerodrive/core/logger.dart';

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
  bool _waitingForUnlock = false;

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  Future<void> _initStream() async {
    try {
      final kekBytes = ref.read(masterKeyProvider);
      if (kekBytes == null) {
        AppLogger.warning('MediaPlayerScreen: Vault is locked, prompting unlock');
        if (mounted) {
          setState(() {
            _waitingForUnlock = true;
            _isLoading = false;
          });
        }
        return;
      }

      final streamingServer = ref.read(streamingServerProvider);
      if (streamingServer.port == 0) {
        AppLogger.info('MediaPlayerScreen: Starting streaming server...');
        await streamingServer.start();
      }
      final url = 'http://127.0.0.1:${streamingServer.port}/stream?id=${widget.file.id}';
      AppLogger.info('MediaPlayerScreen: Streaming URL = $url');
      
      player = Player();
      controller = VideoController(player!);
      
      try {
        await player!.open(Media(url));
        AppLogger.info('MediaPlayerScreen: Player opened media successfully');

        if (mounted) {
          setState(() => _isLoading = false);
        }
      } catch (e) {
        player?.dispose();
        player = null;
        controller = null;
        rethrow; // Pass to outer catch
      }
    } catch (e) {
      AppLogger.error('MediaPlayerScreen: Failed to init stream', e);
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _onUnlockPressed() {
    if (mounted) {
      AppLogger.info('MediaPlayerScreen: Navigating to lock screen');
      context.push('/lock');
    }
  }

  @override
  void dispose() {
    player?.dispose();
    ref.read(streamingServerProvider).stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch for vault unlock to auto-restart stream
    ref.listen<bool>(isAppUnlockedProvider, (prev, next) {
      if (next && _waitingForUnlock) {
        AppLogger.info('MediaPlayerScreen: Vault unlocked, retrying stream');
        setState(() {
          _waitingForUnlock = false;
          _isLoading = true;
          _error = null;
        });
        _initStream();
      }
    });

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
        actions: [
          IconButton(
            icon: const Icon(Icons.download, color: Colors.white70),
            tooltip: 'Download',
            onPressed: () async {
              final db = ref.read(databaseProvider);
              await db.into(db.transferQueue).insert(
                TransferQueueCompanion.insert(
                  id: const Uuid().v4(),
                  fileId: drift.Value(widget.file.id),
                  type: drift.Value('DOWNLOAD_FILE'),
                  status: drift.Value('PENDING'),
                  priority: drift.Value(1),
                  createdAt: drift.Value(DateTime.now()),
                ),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Queued for download...')),
                );
              }
            },
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Center(
        child: _isLoading
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Preparing stream...', style: TextStyle(color: Colors.white70)),
                ],
              )
            : _waitingForUnlock
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock, size: 64, color: Colors.white30),
                      const SizedBox(height: 16),
                      const Text('Vault is locked', style: TextStyle(color: Colors.white70, fontSize: 18)),
                      const SizedBox(height: 8),
                      const Text('Unlock to play this video', style: TextStyle(color: Colors.white38, fontSize: 14)),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _onUnlockPressed,
                        icon: const Icon(Icons.lock_open),
                        label: const Text('Unlock Vault'),
                      ),
                    ],
                  )
                : _error != null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
                          const SizedBox(height: 16),
                          Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: () {
                              setState(() {
                                _error = null;
                                _isLoading = true;
                              });
                              _initStream();
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      )
                    : Video(controller: controller!),
      ),
    );
  }
}

