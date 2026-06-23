import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:aerodrive/features/gallery/gallery_screen.dart';
import 'package:aerodrive/features/gallery/people_screen.dart';

enum MediaView { photos, people }

class MediaScreen extends StatefulWidget {
  const MediaScreen({super.key});

  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> {
  MediaView _currentView = MediaView.photos;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text('Media'),
            floating: true,
            pinned: true,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(60),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: SegmentedButton<MediaView>(
                  segments: const [
                    ButtonSegment(
                      value: MediaView.photos,
                      icon: Icon(Icons.photo_library),
                      label: Text('Photos'),
                    ),
                    ButtonSegment(
                      value: MediaView.people,
                      icon: Icon(Icons.people),
                      label: Text('People'),
                    ),
                  ],
                  selected: {_currentView},
                  onSelectionChanged: (Set<MediaView> newSelection) {
                    setState(() {
                      _currentView = newSelection.first;
                    });
                  },
                ),
              ),
            ),
          ),
          SliverFillRemaining(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.05, 0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOut,
                  )),
                  child: FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                );
              },
              child: KeyedSubtree(
                key: ValueKey(_currentView),
                child: _currentView == MediaView.photos 
                  ? const GalleryScreenContent() 
                  : const PeopleScreenContent(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
