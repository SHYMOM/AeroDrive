import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/db/database.dart';
import '../../domain/streaming/streaming_server.dart';
import '../drive/media_player_screen.dart';

class VideoGalleryScreen extends ConsumerStatefulWidget {

  const VideoGalleryScreen({
    super.key,
    required this.files,
    required this.initialIndex,
  });
  final List<FileData> files;
  final int initialIndex;

  @override
  ConsumerState<VideoGalleryScreen> createState() => _VideoGalleryScreenState();
}

class _VideoGalleryScreenState extends ConsumerState<VideoGalleryScreen> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final file in widget.files) {
      ref.read(streamingServerProvider).cancelStreamsForFile(file.id);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        scrollDirection: Axis.vertical,
        controller: _pageController,
        itemCount: widget.files.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemBuilder: (context, index) {
          final file = widget.files[index];
          final isActive = index == _currentIndex;
          return MediaPlayerScreen(
            key: ValueKey(file.id),
            file: file,
            isActive: isActive,
            onNext: () {
              if (index < widget.files.length - 1) {
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              }
            },
          );
        },
      ),
    );
}
