import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../../core/logger.dart';
import '../../core/providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/providers/security_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/db/database.dart';
import '../../domain/streaming/streaming_server.dart';
import '../gallery/thumbnail_service.dart';
import '../sharing/share_dialog.dart';

enum AudioLoopMode {
  off,
  all,
  one,
}

class AudioPlayerScreen extends ConsumerStatefulWidget {
  const AudioPlayerScreen({
    super.key,
    required this.file,
    this.siblings,
    this.initialIndex = 0,
  });

  final FileData file;
  final List<FileData>? siblings;
  final int initialIndex;

  @override
  ConsumerState<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends ConsumerState<AudioPlayerScreen>
    with SingleTickerProviderStateMixin {
  Player? _player;
  bool _isLoading = true;
  String? _error;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  late List<FileData> _playlist;
  late int _currentIndex;
  bool _isShuffle = false;
  AudioLoopMode _loopMode = AudioLoopMode.all;
  double _playbackRate = 1.0;
  double _volume = 100.0;
  bool _isMuted = false;
  bool _isFavorite = false;

  late AnimationController _rotationController;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );

    // Initialize playlist
    if (widget.siblings != null && widget.siblings!.isNotEmpty) {
      _playlist = List<FileData>.from(widget.siblings!);
      _currentIndex = _playlist.indexWhere((f) => f.id == widget.file.id);
      if (_currentIndex < 0) _currentIndex = widget.initialIndex.clamp(0, _playlist.length - 1);
    } else {
      _playlist = [widget.file];
      _currentIndex = 0;
      _loadFolderSiblings();
    }

    _isFavorite = currentFile.isFavorite;
    _initStreamForCurrent();
  }

  FileData get currentFile => _playlist[_currentIndex];

  Future<void> _loadFolderSiblings() async {
    final db = ref.read(databaseProvider);
    final folderId = widget.file.folderId;
    List<FileData> siblings;
    if (folderId != null) {
      siblings = await (db.select(db.files)
            ..where((f) => f.folderId.equals(folderId))
            ..where((f) => f.mimeType.like('audio/%') | f.name.like('%.mp3') | f.name.like('%.flac') | f.name.like('%.wav') | f.name.like('%.m4a') | f.name.like('%.ogg'))
            ..where((f) => f.deletedAt.isNull()))
          .get();
    } else {
      siblings = await (db.select(db.files)
            ..where((f) => f.folderId.isNull())
            ..where((f) => f.mimeType.like('audio/%') | f.name.like('%.mp3') | f.name.like('%.flac') | f.name.like('%.wav') | f.name.like('%.m4a') | f.name.like('%.ogg'))
            ..where((f) => f.deletedAt.isNull()))
          .get();
    }

    if (siblings.length > 1 && mounted) {
      setState(() {
        _playlist = siblings;
        final idx = _playlist.indexWhere((f) => f.id == widget.file.id);
        if (idx >= 0) _currentIndex = idx;
      });
    }
  }

  Future<void> _initStreamForCurrent() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _isFavorite = currentFile.isFavorite;
    });

    try {
      final masterKey = ref.read(masterKeyProvider);
      if (masterKey == null) {
        throw Exception('Vault is locked. Unlock to play audio.');
      }

      final streamingServer = ref.read(streamingServerProvider);
      if (streamingServer.port == 0) {
        await streamingServer.start();
      }

      final url = 'http://127.0.0.1:${streamingServer.port}/stream?id=${currentFile.id}';
      AppLogger.info('AudioPlayer: Opening stream $url for file ${currentFile.name}');

      if (_player == null) {
        _player = Player();
        _setupPlayerListeners();
      } else {
        await _player!.stop();
      }

      await _player!.open(Media(url), play: true);
      await _player!.setRate(_playbackRate);
      await _player!.setVolume(_isMuted ? 0 : _volume);

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _rotationController.repeat();
      }
    } catch (e, s) {
      AppLogger.error('AudioPlayer: Failed to play audio', e, s);
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _setupPlayerListeners() {
    _player!.stream.playing.listen((playing) {
      if (mounted) {
        setState(() => _isPlaying = playing);
        if (playing) {
          if (!_rotationController.isAnimating) {
            _rotationController.repeat();
          }
        } else {
          _rotationController.stop();
        }
      }
    });

    _player!.stream.position.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });

    _player!.stream.duration.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });

    _player!.stream.completed.listen((completed) {
      if (completed && mounted) {
        _handleTrackCompletion();
      }
    });
  }

  void _handleTrackCompletion() {
    switch (_loopMode) {
      case AudioLoopMode.one:
        _player?.seek(Duration.zero);
        _player?.play();
        break;
      case AudioLoopMode.all:
        _skipNext();
        break;
      case AudioLoopMode.off:
        if (_currentIndex < _playlist.length - 1) {
          _skipNext();
        } else {
          _player?.seek(Duration.zero);
          _player?.pause();
        }
        break;
    }
  }

  void _skipNext() {
    if (_playlist.isEmpty) return;
    int nextIndex;
    if (_isShuffle && _playlist.length > 1) {
      nextIndex = _random.nextInt(_playlist.length);
      if (nextIndex == _currentIndex) {
        nextIndex = (_currentIndex + 1) % _playlist.length;
      }
    } else {
      nextIndex = (_currentIndex + 1) % _playlist.length;
    }

    setState(() => _currentIndex = nextIndex);
    _initStreamForCurrent();
  }

  void _skipPrevious() {
    if (_position.inSeconds > 3) {
      _player?.seek(Duration.zero);
      return;
    }
    if (_playlist.isEmpty) return;
    int prevIndex;
    if (_isShuffle && _playlist.length > 1) {
      prevIndex = _random.nextInt(_playlist.length);
    } else {
      prevIndex = (_currentIndex - 1 + _playlist.length) % _playlist.length;
    }
    setState(() => _currentIndex = prevIndex);
    _initStreamForCurrent();
  }

  void _togglePlayPause() {
    if (_player == null) return;
    if (_isPlaying) {
      _player!.pause();
    } else {
      _player!.play();
    }
  }

  void _seekRelative(int seconds) {
    if (_player == null) return;
    final target = _position + Duration(seconds: seconds);
    final clamped = Duration(
      milliseconds: target.inMilliseconds.clamp(0, _duration.inMilliseconds),
    );
    _player!.seek(clamped);
  }

  void _toggleFavorite() async {
    final db = ref.read(databaseProvider);
    final newFav = !_isFavorite;
    setState(() => _isFavorite = newFav);

    await (db.update(db.files)..where((tbl) => tbl.id.equals(currentFile.id)))
        .write(FilesCompanion(isFavorite: drift.Value(newFav)));

    final idx = _playlist.indexWhere((f) => f.id == currentFile.id);
    if (idx >= 0) {
      _playlist[idx] = _playlist[idx].copyWith(isFavorite: newFav);
    }
  }

  void _cycleLoopMode() {
    setState(() {
      switch (_loopMode) {
        case AudioLoopMode.off:
          _loopMode = AudioLoopMode.all;
          break;
        case AudioLoopMode.all:
          _loopMode = AudioLoopMode.one;
          break;
        case AudioLoopMode.one:
          _loopMode = AudioLoopMode.off;
          break;
      }
    });
  }

  void _showPlaybackSpeedSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Playback Speed',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((rate) {
                final isSelected = (_playbackRate - rate).abs() < 0.05;
                return ChoiceChip(
                  label: Text('${rate}x'),
                  selected: isSelected,
                  selectedColor: AppColors.primary,
                  backgroundColor: AppColors.surface,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : AppColors.onSurfaceVariant,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _playbackRate = rate);
                      _player?.setRate(rate);
                      Navigator.pop(ctx);
                    }
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _showPlaylistDrawer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outline.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Queue (${_playlist.length} tracks)',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _isShuffle ? Icons.shuffle_rounded : Icons.shuffle,
                      color: _isShuffle ? AppColors.primary : AppColors.onSurfaceVariant,
                    ),
                    tooltip: 'Shuffle',
                    onPressed: () {
                      setState(() => _isShuffle = !_isShuffle);
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
            ),
            Divider(color: AppColors.outlineVariant, height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _playlist.length,
                itemBuilder: (context, index) {
                  final item = _playlist[index];
                  final isCurrent = index == _currentIndex;
                  return ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? AppColors.primary.withValues(alpha: 0.25)
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isCurrent
                            ? (_isPlaying ? Icons.equalizer_rounded : Icons.play_arrow_rounded)
                            : Icons.music_note_rounded,
                        color: isCurrent ? AppColors.primary : AppColors.onSurfaceVariant,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCurrent ? AppColors.primaryLight : Colors.white,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      _formatBytes(item.size),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    trailing: isCurrent
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Playing',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.primaryLight,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      if (index != _currentIndex) {
                        setState(() => _currentIndex = index);
                        _initStreamForCurrent();
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$m:$s';
    }
    return '$m:$s';
  }

  String _formatBytes(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    final i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _getFileExtension(String name) {
    final parts = name.split('.');
    if (parts.length > 1) {
      return parts.last.toUpperCase();
    }
    return 'AUDIO';
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ext = _getFileExtension(currentFile.name);
    final sizeStr = _formatBytes(currentFile.size);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 720;

            if (isDesktop) {
              return _buildDesktopLayout(ext, sizeStr);
            }
            return _buildMobileLayout(ext, sizeStr);
          },
        ),
      ),
    );
  }

  Widget _buildTopAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32, color: Colors.white),
            tooltip: 'Minimize',
            onPressed: () => Navigator.pop(context),
          ),
          Column(
            children: [
              Text(
                'PLAYING FROM DRIVE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${_currentIndex + 1} of ${_playlist.length}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.queue_music_rounded, color: Colors.white),
            tooltip: 'Queue',
            onPressed: _showPlaylistDrawer,
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(String ext, String sizeStr) {
    return Column(
      children: [
        _buildTopAppBar(),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  _buildVinylArt(size: 260),
                  const SizedBox(height: 28),
                  _buildWaveformVisualizer(),
                  const SizedBox(height: 28),
                  _buildTrackInfo(ext, sizeStr),
                  const SizedBox(height: 20),
                  _buildProgressBar(),
                  const SizedBox(height: 16),
                  _buildMainControls(),
                  const SizedBox(height: 16),
                  _buildSecondaryControls(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout(String ext, String sizeStr) {
    return Column(
      children: [
        _buildTopAppBar(),
        Expanded(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 880),
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildVinylArt(size: 300),
                        const SizedBox(height: 24),
                        _buildWaveformVisualizer(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 48),
                  Expanded(
                    flex: 6,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTrackInfo(ext, sizeStr),
                        const SizedBox(height: 24),
                        _buildProgressBar(),
                        const SizedBox(height: 20),
                        _buildMainControls(),
                        const SizedBox(height: 20),
                        _buildSecondaryControls(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVinylArt({required double size}) {
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.35),
              blurRadius: 40,
              spreadRadius: 4,
            ),
          ],
        ),
        child: AnimatedBuilder(
          animation: _rotationController,
          builder: (context, child) {
            return Transform.rotate(
              angle: _rotationController.value * 2 * pi,
              child: child,
            );
          },
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF1B1D28),
                  const Color(0xFF0F1017),
                  const Color(0xFF1E2132),
                  const Color(0xFF0A0B10),
                ],
                stops: const [0.3, 0.6, 0.85, 1.0],
              ),
              border: Border.all(
                color: AppColors.outline.withValues(alpha: 0.4),
                width: 2,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Vinyl grooves
                ...List.generate(4, (i) {
                  final radius = size * (0.35 + i * 0.12);
                  return Container(
                    width: radius,
                    height: radius,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.04),
                        width: 1.2,
                      ),
                    ),
                  );
                }),

                // Center vinyl label / album artwork
                Container(
                  width: size * 0.38,
                  height: size * 0.38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppColors.primaryDark, AppColors.primaryLight],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: size * 0.12,
                      height: size * 0.12,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF0A0B10),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.music_note_rounded,
                          color: AppColors.secondary,
                          size: size * 0.07,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWaveformVisualizer() {
    return SizedBox(
      height: 32,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(18, (index) {
          final barHeight = _isPlaying
              ? (10 + (sin(index * 0.7 + _position.inMilliseconds * 0.01).abs() * 22))
              : 6.0;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            width: 3.5,
            height: barHeight,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.secondary, AppColors.primaryLight],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTrackInfo(String ext, String sizeStr) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                currentFile.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      ext,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryLight,
                      ),
                    ),
                  ),
                  if (sizeStr.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      sizeStr,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(
            _isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: _isFavorite ? Colors.redAccent : AppColors.onSurfaceVariant,
            size: 28,
          ),
          onPressed: _toggleFavorite,
          tooltip: _isFavorite ? 'Unfavorite' : 'Favorite',
        ),
      ],
    );
  }

  Widget _buildProgressBar() {
    final posMs = _position.inMilliseconds.toDouble();
    final durMs = max(1.0, _duration.inMilliseconds.toDouble());
    final currentSliderVal = posMs.clamp(0.0, durMs);

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: AppColors.surfaceElevated,
            thumbColor: Colors.white,
            overlayColor: AppColors.primary.withValues(alpha: 0.3),
          ),
          child: Slider(
            value: currentSliderVal,
            max: durMs,
            onChanged: (val) {
              _player?.seek(Duration(milliseconds: val.toInt()));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(_position),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              Text(
                _formatDuration(_duration),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMainControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Shuffle
        IconButton(
          icon: Icon(
            _isShuffle ? Icons.shuffle_rounded : Icons.shuffle,
            color: _isShuffle ? AppColors.primary : AppColors.onSurfaceVariant,
            size: 24,
          ),
          tooltip: 'Shuffle',
          onPressed: () => setState(() => _isShuffle = !_isShuffle),
        ),

        // Skip Previous
        IconButton(
          icon: const Icon(Icons.skip_previous_rounded, size: 36, color: Colors.white),
          tooltip: 'Previous Track',
          onPressed: _skipPrevious,
        ),

        // -10s
        IconButton(
          icon: const Icon(Icons.replay_10_rounded, size: 28, color: Colors.white70),
          tooltip: '-10s',
          onPressed: () => _seekRelative(-10),
        ),

        // Play / Pause FAB
        Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [AppColors.primaryDark, AppColors.primaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.glowCyan,
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                  )
                : Icon(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 38,
                    color: Colors.white,
                  ),
            onPressed: _isLoading ? null : _togglePlayPause,
          ),
        ),

        // +10s
        IconButton(
          icon: const Icon(Icons.forward_10_rounded, size: 28, color: Colors.white70),
          tooltip: '+10s',
          onPressed: () => _seekRelative(10),
        ),

        // Skip Next
        IconButton(
          icon: const Icon(Icons.skip_next_rounded, size: 36, color: Colors.white),
          tooltip: 'Next Track',
          onPressed: _skipNext,
        ),

        // Loop Mode
        IconButton(
          icon: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                _loopMode == AudioLoopMode.off ? Icons.repeat : Icons.repeat_rounded,
                color: _loopMode != AudioLoopMode.off ? AppColors.primary : AppColors.onSurfaceVariant,
                size: 24,
              ),
              if (_loopMode == AudioLoopMode.one)
                const Positioned(
                  bottom: 0,
                  right: 0,
                  child: Text(
                    '1',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
          tooltip: 'Loop: ${_loopMode.name}',
          onPressed: _cycleLoopMode,
        ),
      ],
    );
  }

  Widget _buildSecondaryControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Playback Speed
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _showPlaybackSpeedSheet,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.speed_rounded, size: 18, color: AppColors.secondary),
                  const SizedBox(width: 6),
                  Text(
                    '${_playbackRate}x',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Volume Slider
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _isMuted || _volume == 0
                      ? Icons.volume_off_rounded
                      : (_volume < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
                  size: 20,
                  color: AppColors.onSurfaceVariant,
                ),
                tooltip: _isMuted ? 'Unmute' : 'Mute',
                onPressed: () {
                  setState(() => _isMuted = !_isMuted);
                  _player?.setVolume(_isMuted ? 0 : _volume);
                },
              ),
              SizedBox(
                width: 90,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    activeTrackColor: AppColors.secondary,
                    inactiveTrackColor: AppColors.surface,
                    thumbColor: AppColors.secondary,
                  ),
                  child: Slider(
                    value: _isMuted ? 0 : _volume,
                    max: 100,
                    onChanged: (val) {
                      setState(() {
                        _volume = val;
                        _isMuted = false;
                      });
                      _player?.setVolume(val);
                    },
                  ),
                ),
              ),
            ],
          ),

          // Share
          IconButton(
            icon: Icon(Icons.share_outlined, size: 20, color: AppColors.onSurfaceVariant),
            tooltip: 'Share',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => ShareDialog(file: currentFile),
              );
            },
          ),
        ],
      ),
    );
  }
}
