import 'package:flutter/material.dart';
import '../../data/db/database.dart';
import 'decrypted_image_viewer.dart';
import 'preview_router.dart';

class ImageGalleryScreen extends StatefulWidget {

  const ImageGalleryScreen({
    super.key,
    required this.files,
    required this.initialIndex,
  });
  final List<FileData> files;
  final int initialIndex;

  @override
  State<ImageGalleryScreen> createState() => _ImageGalleryScreenState();
}

class _ImageGalleryScreenState extends State<ImageGalleryScreen> {
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
    final currentFile = widget.files[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black45,
        elevation: 0,
        title: Text(currentFile.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          PreviewFavoriteButton(file: currentFile),
          PreviewDownloadButton(fileId: currentFile.id),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.files.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemBuilder: (context, index) => DecryptedImageViewer(file: widget.files[index]),
      ),
    );
  }
}
