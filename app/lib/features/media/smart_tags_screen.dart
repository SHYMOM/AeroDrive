import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/db/database.dart';
import '../gallery/thumbnail_service.dart';
import 'media_screen.dart';

class SmartTagsScreen extends ConsumerStatefulWidget {
  const SmartTagsScreen({super.key});

  @override
  ConsumerState<SmartTagsScreen> createState() => _SmartTagsScreenState();
}

class _SmartTagsScreenState extends ConsumerState<SmartTagsScreen> {
  Tag? _selectedTag;
  List<FileData> _tagFiles = [];
  bool _isLoadingFiles = false;

  Future<void> _loadTagFiles(Tag tag) async {
    setState(() {
      _selectedTag = tag;
      _isLoadingFiles = true;
    });

    final db = ref.read(databaseProvider);
    final mappings = await (db.select(db.fileTags)..where((ft) => ft.tagId.equals(tag.id))).get();
    
    if (mappings.isEmpty) {
      if (mounted) {
        setState(() {
          _tagFiles = [];
          _isLoadingFiles = false;
        });
      }
      return;
    }

    final fileIds = mappings.map((m) => m.fileId).toList();
    final files = await (db.select(db.files)
      ..where((f) => f.id.isIn(fileIds) & f.deletedAt.isNull())
    ).get();

    if (mounted) {
      setState(() {
        _tagFiles = files;
        _isLoadingFiles = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final exploreAsync = ref.watch(exploreDataProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (_selectedTag != null) {
              setState(() {
                _selectedTag = null;
                _tagFiles = [];
              });
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(
          _selectedTag != null ? 'Tag: ${_selectedTag!.name}' : 'Smart Tags',
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.3),
            radius: 1.8,
            colors: [
              const Color(0xFF7C3AED).withValues(alpha: 0.15),
              const Color(0xFF00E5FF).withValues(alpha: 0.05),
              AppColors.background,
              AppColors.background,
            ],
          ),
        ),
        child: _selectedTag != null 
            ? _buildTagFilesView()
            : _buildTagsGridView(exploreAsync),
      ),
    );
  }

  Widget _buildTagFilesView() {
    if (_isLoadingFiles) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_tagFiles.isEmpty) {
      return const Center(
        child: Text('No files have this tag.', style: TextStyle(color: Colors.white54)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: _tagFiles.length,
      itemBuilder: (context, index) {
        final file = _tagFiles[index];
        return _LocalGalleryItem(file: file);
      },
    );
  }

  Widget _buildTagsGridView(AsyncValue<Map<String, dynamic>> exploreAsync) => exploreAsync.when(
      data: (exploreData) {
        final smartTags = exploreData['smartTags'] as List<Map<String, dynamic>>;
        
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.1,
          ),
          itemCount: smartTags.length,
          itemBuilder: (context, index) {
            final tagInfo = smartTags[index];
            final name = tagInfo['name'] as String;
            final count = tagInfo['count'] as int;
            final fileCover = tagInfo['cover'] as FileData?;
            
            final tagData = Tag(id: name.toLowerCase(), name: name, source: 'ML_VISION');

            return GestureDetector(
              onTap: () => _loadTagFiles(tagData),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (fileCover != null)
                      _LocalCoverImage(file: fileCover)
                    else
                      _buildFallbackGradient(name),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 12,
                      left: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '$count items',
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.white))),
    );

  Widget _buildFallbackGradient(String name) {
    IconData icon;
    Color color;
    switch (name.toLowerCase()) {
      case 'food':
        icon = Icons.restaurant;
        color = Colors.orangeAccent;
      case 'buildings':
        icon = Icons.apartment;
        color = Colors.lightBlueAccent;
      case 'ocean':
        icon = Icons.waves;
        color = Colors.blue;
      default:
        icon = Icons.local_offer_outlined;
        color = AppColors.primary;
    }
    return ColoredBox(
      color: color.withValues(alpha: 0.1),
      child: Center(child: Icon(icon, color: color, size: 36)),
    );
  }
}

class _LocalCoverImage extends ConsumerWidget {
  const _LocalCoverImage({required this.file});
  final FileData file;

  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder<File?>(
      future: ref.read(thumbnailServiceProvider).getThumbnail(file),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.file(snapshot.data!, fit: BoxFit.cover);
        }
        return Container(color: Colors.white.withValues(alpha: 0.05));
      },
    );
}

class _LocalGalleryItem extends ConsumerWidget {
  const _LocalGalleryItem({required this.file});
  final FileData file;

  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder<File?>(
      future: ref.read(thumbnailServiceProvider).getThumbnail(file),
      builder: (context, snapshot) {
        final hasThumb = snapshot.hasData && snapshot.data != null;
        return Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasThumb)
                Image.file(snapshot.data!, fit: BoxFit.cover)
              else if (file.mimeType?.startsWith('video/') == true)
                const Icon(Icons.videocam, color: Colors.white, size: 28)
              else
                const Icon(Icons.image_not_supported, color: Colors.grey, size: 20),
            ],
          ),
        );
      },
    );
}
