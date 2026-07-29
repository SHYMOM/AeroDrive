import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/logger.dart';
import '../../data/db/database.dart';
import '../../domain/streaming/streaming_server.dart';

class FullscreenVideoScreen extends ConsumerStatefulWidget {

  const FullscreenVideoScreen({super.key, required this.file});
  final FileData file;

  @override
  ConsumerState<FullscreenVideoScreen> createState() => _FullscreenVideoScreenState();
}

class _FullscreenVideoScreenState extends ConsumerState<FullscreenVideoScreen> {
  Player? player;
  VideoController? controller;
  bool _isLoading = true;
  String? _error;

  bool _isPlaying = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _showControls = true;
  Timer? _hideControlsTimer;
  double _playbackSpeed = 1;

  @override
  void initState() {
    super.initState();
    // Initially hide status bar
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initStream();
    _startHideControlsTimer();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideControlsTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  Future<void> _initStream() async {
    try {
      final streamingServer = ref.read(streamingServerProvider);
      if (streamingServer.port == 0) {
        await streamingServer.start();
      }
      final url = 'http://127.0.0.1:${streamingServer.port}/stream?id=${widget.file.id}';

      player = Player();
      controller = VideoController(player!);

      player!.stream.playing.listen((playing) {
        if (mounted) {
          setState(() => _isPlaying = playing);
          if (playing) {
            _startHideControlsTimer();
          } else {
            _hideControlsTimer?.cancel();
            setState(() => _showControls = true);
          }
        }
      });

      player!.stream.position.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });

      player!.stream.duration.listen((dur) {
        if (mounted) setState(() => _duration = dur);
      });

      player!.stream.videoParams.listen((params) {
        if (mounted) {
          final w = params.w ?? 0;
          final h = params.h ?? 0;
          if (w > 0 && h > 0) {
            if (w > h) {
              // Landscape
              SystemChrome.setPreferredOrientations([
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]);
            } else {
              // Portrait
              SystemChrome.setPreferredOrientations([
                DeviceOrientation.portraitUp,
                DeviceOrientation.portraitDown,
              ]);
            }
          }
        }
      });

      await player!.open(Media(url));

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      AppLogger.error('FullscreenVideoScreen: Failed to init stream', e);
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _seekRelative(int seconds) {
    if (player == null) return;
    final newPos = _position + Duration(seconds: seconds);
    player!.seek(newPos < Duration.zero ? Duration.zero : newPos);
    _startHideControlsTimer();
  }

  void _changeSpeed() {
    if (player == null) return;
    setState(() {
      if (_playbackSpeed == 1.0) {
        _playbackSpeed = 1.25;
      } else if (_playbackSpeed == 1.25) {
        _playbackSpeed = 1.5;
      } else if (_playbackSpeed == 1.5) {
        _playbackSpeed = 2.0;
      } else {
        _playbackSpeed = 1.0;
      }
    });
    player!.setRate(_playbackSpeed);
    _startHideControlsTimer();
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
    _hideControlsTimer?.cancel();
    player?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Video Layer
          GestureDetector(
            onTap: _toggleControls,
            onDoubleTapDown: (details) {
              final screenWidth = MediaQuery.of(context).size.width;
              if (details.globalPosition.dx < screenWidth / 2) {
                _seekRelative(-10);
              } else {
                _seekRelative(10);
              }
            },
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
                            const SizedBox(height: 16),
                            Text(_error!, style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
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
                        controls: NoVideoControls,
                      ),
          ),

          // Controls Overlay
          if (_showControls && !_isLoading && _error == null)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: SafeArea(
                  child: Column(
                    children: [
                      // Top Bar
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                              onPressed: () => Navigator.pop(context),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                widget.file.name,
                                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.speed, color: Colors.white),
                              onPressed: _changeSpeed,
                              tooltip: 'Playback Speed (${_playbackSpeed}x)',
                            ),
                            Text(
                              '${_playbackSpeed}x',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ),
                      
                      const Spacer(),

                      // Center Controls
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.replay_10, color: Colors.white, size: 48),
                            onPressed: () => _seekRelative(-10),
                          ),
                          const SizedBox(width: 48),
                          GestureDetector(
                            onTap: () {
                              if (player == null) return;
                              if (_isPlaying) {
                                player!.pause();
                              } else {
                                player!.play();
                              }
                              _startHideControlsTimer();
                            },
                            child: Container(
                              decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
                              padding: const EdgeInsets.all(16),
                              child: Icon(
                                _isPlaying ? Icons.pause : Icons.play_arrow,
                                size: 64,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 48),
                          IconButton(
                            icon: const Icon(Icons.forward_10, color: Colors.white, size: 48),
                            onPressed: () => _seekRelative(10),
                          ),
                        ],
                      ),

                      const Spacer(),

                      // Bottom Progress Bar
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                        child: Row(
                          children: [
                            Text(_formatDuration(_position), style: const TextStyle(color: Colors.white)),
                            const SizedBox(width: 16),
                            Expanded(
                              child: SliderTheme(
                                data: const SliderThemeData(
                                  trackHeight: 4,
                                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
                                  overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
                                  activeTrackColor: Colors.blueAccent,
                                  inactiveTrackColor: Colors.white24,
                                  thumbColor: Colors.blueAccent,
                                ),
                                child: Slider(
                                  value: _position.inMilliseconds.toDouble(),
                                  max: _duration.inMilliseconds.toDouble() > 0 ? _duration.inMilliseconds.toDouble() : 1.0,
                                  onChanged: (val) {
                                    player?.seek(Duration(milliseconds: val.toInt()));
                                    _startHideControlsTimer();
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(_formatDuration(_duration), style: const TextStyle(color: Colors.white70)),
                            const SizedBox(width: 16),
                            IconButton(
                              icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
}
