import 'package:flutter/material.dart';

import '../../data/db/database.dart';
import '../drive/media_player_screen.dart';
import 'decrypted_image_viewer.dart';
import 'preview_router.dart';

class MediaGalleryScreen extends StatefulWidget {

  const MediaGalleryScreen({
    super.key,
    required this.files,
    required this.initialIndex,
  });
  final List<FileData> files;
  final int initialIndex;

  @override
  State<MediaGalleryScreen> createState() => _MediaGalleryScreenState();
}

class _MediaGalleryScreenState extends State<MediaGalleryScreen> {
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
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.files.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemBuilder: (context, index) {
          final file = widget.files[index];
          final isVideo = file.mimeType?.startsWith('video/') == true;

          if (isVideo) {
            return MediaPlayerScreen(
              key: ValueKey(file.id),
              file: file,
              isActive: _currentIndex == index,
            );
          } else {
            return Stack(
              fit: StackFit.expand,
              children: [
                DecryptedImageViewer(file: file),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top, bottom: 12),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.black54, Colors.transparent],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Expanded(
                          child: Text(
                            file.name,
                            style: const TextStyle(color: Colors.white, fontSize: 18),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        PreviewDownloadButton(fileId: file.id),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }
        },
      ),
    );
}
