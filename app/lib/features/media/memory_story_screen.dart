import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../data/db/database.dart';
import '../gallery/thumbnail_service.dart';

class MemoryStoryScreen extends ConsumerStatefulWidget {
  const MemoryStoryScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.files,
    this.initialIndex = 0,
  });

  final String title;
  final String subtitle;
  final List<FileData> files;
  final int initialIndex;

  @override
  ConsumerState<MemoryStoryScreen> createState() => _MemoryStoryScreenState();
}

class _MemoryStoryScreenState extends ConsumerState<MemoryStoryScreen>
    with SingleTickerProviderStateMixin {
  late int _currentIndex;
  late AnimationController _progressController;
  final Map<String, File?> _cachedThumbs = {};

  static const Duration _storyDuration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.files.length - 1);

    _progressController = AnimationController(
      vsync: this,
      duration: _storyDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _nextStory();
        }
      });

    _preloadCurrentAndNext();
    _progressController.forward();
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  Future<void> _preloadCurrentAndNext() async {
    if (widget.files.isEmpty) return;

    final currentFile = widget.files[_currentIndex];
    if (!_cachedThumbs.containsKey(currentFile.id)) {
      final thumb = await ref.read(thumbnailServiceProvider).getThumbnail(currentFile);
      if (mounted) {
        setState(() {
          _cachedThumbs[currentFile.id] = thumb;
        });
      }
    }

    // Preload next image in background
    if (_currentIndex + 1 < widget.files.length) {
      final nextFile = widget.files[_currentIndex + 1];
      if (!_cachedThumbs.containsKey(nextFile.id)) {
        ref.read(thumbnailServiceProvider).getThumbnail(nextFile).then((thumb) {
          if (mounted) {
            _cachedThumbs[nextFile.id] = thumb;
          }
        });
      }
    }
  }

  void _nextStory() {
    if (_currentIndex < widget.files.length - 1) {
      setState(() {
        _currentIndex++;
      });
      _preloadCurrentAndNext();
      _progressController.reset();
      _progressController.forward();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _previousStory() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
      _preloadCurrentAndNext();
      _progressController.reset();
      _progressController.forward();
    } else {
      _progressController.reset();
      _progressController.forward();
    }
  }

  void _onTapDown(TapDownDetails details) {
    _progressController.stop();
  }

  void _onTapUp(TapUpDetails details) {
    _progressController.forward();

    final screenWidth = MediaQuery.of(context).size.width;
    if (details.globalPosition.dx < screenWidth * 0.35) {
      _previousStory();
    } else {
      _nextStory();
    }
  }

  void _onTapCancel() {
    _progressController.forward();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.files.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Text('No photos in this memory', style: TextStyle(color: Colors.white70))),
      );
    }

    final currentFile = widget.files[_currentIndex];
    final thumbFile = _cachedThumbs[currentFile.id];

    final date = currentFile.photoTakenAt ?? currentFile.createdAt;
    final dateStr = date != null ? DateFormat('MMMM d, yyyy').format(date) : '';

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Ken Burns Animated Photo
            AnimatedBuilder(
              animation: _progressController,
              builder: (context, child) {
                final scale = 1.0 + (_progressController.value * 0.08);
                return Transform.scale(
                  scale: scale,
                  child: Center(
                    child: thumbFile != null && thumbFile.existsSync()
                        ? Image.file(
                            thumbFile,
                            fit: BoxFit.contain,
                            width: double.infinity,
                            height: double.infinity,
                          )
                        : const CircularProgressIndicator(color: AppColors.primary),
                  ),
                );
              },
            ),

            // 2. Vignette Gradients
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.85),
                  ],
                  stops: const [0.0, 0.2, 0.7, 1.0],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),

            // 3. Top Segmented Progress Bar & Header
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  children: [
                    // Segmented bars
                    Row(
                      children: List.generate(widget.files.length, (index) {
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2.0),
                            child: AnimatedBuilder(
                              animation: _progressController,
                              builder: (context, _) {
                                double value = 0.0;
                                if (index < _currentIndex) {
                                  value = 1.0;
                                } else if (index == _currentIndex) {
                                  value = _progressController.value;
                                }
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value: value,
                                    backgroundColor: Colors.white.withValues(alpha: 0.25),
                                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                    minHeight: 2.5,
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 12),

                    // Top Bar (Title & Close Button)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                widget.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              dateStr,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white, size: 24),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // 4. Bottom Info Overlay (Subtitle & Details)
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.subtitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(color: Colors.black87, blurRadius: 10),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.photo_library_outlined, color: Colors.white.withValues(alpha: 0.7), size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '${_currentIndex + 1} of ${widget.files.length}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                      ),
                      if (currentFile.name.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          '•  ${currentFile.name}',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
