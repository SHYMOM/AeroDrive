import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/features/drive/media_player_screen.dart';
import 'package:aerodrive/features/preview/preview_router.dart';

class VideoGalleryScreen extends StatefulWidget {
  final List<FileData> files;
  final int initialIndex;

  const VideoGalleryScreen({
    super.key,
    required this.files,
    required this.initialIndex,
  });

  @override
  State<VideoGalleryScreen> createState() => _VideoGalleryScreenState();
}

class _VideoGalleryScreenState extends State<VideoGalleryScreen> {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          // We wrap the MediaPlayerScreen in a custom way so it fits vertically
          // and doesn't conflict with its own Scaffold/AppBar.
          // Since MediaPlayerScreen has its own Scaffold and AppBar, we can just render it.
          // The scroll gesture will be caught by PageView if MediaPlayerScreen doesn't consume it.
          return MediaPlayerScreen(file: widget.files[index]);
        },
      ),
    );
  }
}
