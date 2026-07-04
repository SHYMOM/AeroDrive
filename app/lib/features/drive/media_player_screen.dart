import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/logger.dart';
import '../../core/providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/providers/security_providers.dart';
import '../../data/db/database.dart';
import '../../domain/streaming/streaming_server.dart';
import '../sharing/share_dialog.dart';
import 'fullscreen_video_screen.dart';

class MediaPlayerScreen extends ConsumerStatefulWidget {

  const MediaPlayerScreen({
    super.key,
    required this.file,
    this.isActive = true,
    this.onNext,
  });
  final FileData file;
  final bool isActive;
  final VoidCallback? onNext;

  @override
  ConsumerState<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends ConsumerState<MediaPlayerScreen> {
  Player? player;
  VideoController? controller;
  bool _isLoading = true;
  String? _error;
  bool _waitingForUnlock = false;

  bool _isPlaying = true;
  bool _isLooping = true;
  bool _isFavorite = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  String _folderName = 'Top Level';
  int _folderItemCount = 0;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.file.isFavorite;
    Future.microtask(() async {
      final db = ref.read(databaseProvider);
      final settings = ref.read(settingsRepositoryProvider);
      final savedLooping = await settings.getSetting('media_player_loop');
      final f = await (db.select(db.files)..where((tbl) => tbl.id.equals(widget.file.id))).getSingleOrNull();
      if (mounted) {
        setState(() {
          if (savedLooping != null) _isLooping = savedLooping == 'true';
          if (f != null) _isFavorite = f.isFavorite;
        });
      }
    });
    _initStream();
    _loadFolderInfo();
  }

  @override
  void didUpdateWidget(covariant MediaPlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        player?.play();
      } else {
        player?.pause();
      }
    }
  }

  Future<void> _loadFolderInfo() async {
    final db = ref.read(databaseProvider);
    if (widget.file.folderId != null) {
      final folder = await (db.select(db.folders)..where((f) => f.id.equals(widget.file.folderId!))).getSingleOrNull();
      if (folder != null) {
        setState(() => _folderName = folder.name);
      }
      final countExpr = db.files.id.count();
      final countQuery = await (db.selectOnly(db.files)
        ..addColumns([countExpr])
        ..where(db.files.folderId.equals(widget.file.folderId!))
        ..where(db.files.mimeType.like('video/%')))
          .getSingle();
      setState(() => _folderItemCount = countQuery.read(countExpr) ?? 0);
    } else {
      final countExpr = db.files.id.count();
      final countQuery = await (db.selectOnly(db.files)
        ..addColumns([countExpr])
        ..where(db.files.folderId.isNull())
        ..where(db.files.mimeType.like('video/%')))
          .getSingle();
      setState(() => _folderItemCount = countQuery.read(countExpr) ?? 0);
    }
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
      
      player = Player();
      controller = VideoController(player!);
      
      player!.stream.playing.listen((playing) {
        if (mounted) setState(() => _isPlaying = playing);
      });
      
      player!.stream.position.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });
      
      player!.stream.duration.listen((dur) {
        if (mounted) setState(() => _duration = dur);
      });

      player!.stream.completed.listen((completed) {
        if (completed) {
          if (_isLooping) {
            player?.seek(Duration.zero);
            player?.play();
          } else {
            widget.onNext?.call();
          }
        }
      });

      try {
        await player!.open(Media(url), play: widget.isActive);
        await player!.setPlaylistMode(PlaylistMode.none); // Handle looping manually

        if (mounted) {
          setState(() => _isLoading = false);
        }
      } catch (e) {
        player?.dispose();
        player = null;
        controller = null;
        rethrow;
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



  void _togglePlayPause() {
    if (player == null) return;
    if (_isPlaying) {
      player!.pause();
    } else {
      player!.play();
    }
  }

  Future<void> _toggleFavorite() async {
    final db = ref.read(databaseProvider);
    final newFav = !_isFavorite;
    await (db.update(db.files)..where((f) => f.id.equals(widget.file.id))).write(
      FilesCompanion(isFavorite: drift.Value(newFav))
    );
    setState(() => _isFavorite = newFav);
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline, color: Colors.white),
                title: const Text('Details', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showDetailsDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showDeleteConfirm();
                },
              ),
            ],
          ),
        ),
    );
  }

  Future<void> _showDeleteConfirm() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: const Text('Delete Video', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete "${widget.file.name}"?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.blueAccent))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (player != null) player!.pause();
      final fileRepo = ref.read(fileRepositoryProvider);
      await fileRepo.softDelete(widget.file.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Video moved to trash')));
        Navigator.pop(context); // Go back after deleting
      }
    }
  }

  void _showDetailsDialog() {
    final sizeStr = widget.file.size != null ? '${(widget.file.size! / 1024 / 1024).toStringAsFixed(2)} MB' : 'Unknown';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: const Text('Video Details', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Name: ${widget.file.name}', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text('Folder: $_folderName', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text('Size: $sizeStr', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text('Duration: ${_formatDuration(_duration)}', style: const TextStyle(color: Colors.white70)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close', style: TextStyle(color: Colors.blueAccent))),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    final String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    if (d.inHours > 0) {
      return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
    }
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  void dispose() {
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(isAppUnlockedProvider, (prev, next) {
      if (next && _waitingForUnlock) {
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Video Player Layer
          GestureDetector(
            onTap: _togglePlayPause,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _waitingForUnlock
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.lock, size: 64, color: Colors.white30),
                            const SizedBox(height: 16),
                            const Text('Encryption Error', style: TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            const Text(
                              'Secure streaming could not be established.\nPlease restart the application.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : _error != null
                        ? Center(
                            child: Column(
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
                            ),
                          )
                        : Video(
                            controller: controller!,
                            controls: NoVideoControls, // Remove default controls
                          ),
          ),

          // Play/Pause Center Indicator (shows briefly when paused)
          if (!_isPlaying && !_isLoading && _error == null && !_waitingForUnlock)
            Center(
              child: GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                  padding: const EdgeInsets.all(16),
                  child: const Icon(Icons.play_arrow, size: 64, color: Colors.white),
                ),
              ),
            ),

          // 2. Top-Left Back Button Overlay
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // 3. Right Column Action Buttons
          if (!_isLoading && _error == null && !_waitingForUnlock)
            Positioned(
              right: 16,
              bottom: 100,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildActionButton(
                    icon: Icons.play_arrow,
                    label: 'Play',
                    onTap: () {
                      if (player != null) player!.pause();
                      Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(
                          builder: (_) => FullscreenVideoScreen(file: widget.file),
                        ),
                      ).then((_) {
                        if (widget.isActive && mounted) player?.play();
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  _buildActionButton(
                    icon: _isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: _isFavorite ? Colors.redAccent : Colors.white,
                    label: 'Like',
                    onTap: _toggleFavorite,
                  ),
                  const SizedBox(height: 24),
                  _buildActionButton(
                    icon: Icons.reply,
                    label: 'Share',
                    onTap: () {
                      if (player != null) player!.pause();
                      showDialog(
                        context: context,
                        builder: (ctx) => ShareDialog(file: widget.file),
                      ).then((_) {
                        if (widget.isActive && mounted) player?.play();
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  _buildActionButton(
                    icon: Icons.more_horiz,
                    label: 'More',
                    onTap: _showMoreOptions,
                  ),
                ],
              ),
            ),

          // 4. Bottom Information Overlay
          if (!_isLoading && _error == null && !_waitingForUnlock)
            Positioned(
              left: 16,
              right: 80,
              bottom: 32,
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Loop Toggle
                    GestureDetector(
                      onTap: () {
                        final newLooping = !_isLooping;
                        setState(() => _isLooping = newLooping);
                        ref.read(settingsRepositoryProvider).setSetting('media_player_loop', newLooping.toString());
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _isLooping ? Colors.blueAccent.withValues(alpha: 0.5) : Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.loop, color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Folder Info
                  Row(
                    children: [
                      const Icon(Icons.folder, color: Colors.yellowAccent, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        _folderName,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '($_folderItemCount videos)',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Title and Info
                  Text(
                    widget.file.name,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),
                  // Custom Progress Bar
                  Row(
                    children: [
                      Text(_formatDuration(_position), style: const TextStyle(color: Colors.white, fontSize: 12)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SliderTheme(
                          data: const SliderThemeData(
                            trackHeight: 2,
                            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
                            activeTrackColor: Colors.white,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: Colors.white,
                          ),
                          child: Slider(
                            value: _position.inMilliseconds.toDouble(),
                            max: _duration.inMilliseconds.toDouble() > 0 ? _duration.inMilliseconds.toDouble() : 1.0,
                            onChanged: (val) {
                              player?.seek(Duration(milliseconds: val.toInt()));
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(_formatDuration(_duration), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({required IconData icon, required String label, required VoidCallback onTap, Color color = Colors.white}) => GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Colors.black45,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
}
