import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/db/database.dart';
import '../gallery/thumbnail_service.dart';
import '../preview/preview_router.dart';

class PlaceNode {
  PlaceNode(this.place, this.photoCount);
  final Place place;
  final int photoCount;
}

class PlaceHierarchy {
  PlaceHierarchy(this.country, this.states);
  final String country;
  final Map<String, List<PlaceNode>> states;
}

final placesHierarchyProvider = FutureProvider<List<PlaceHierarchy>>((ref) async {
  final db = ref.read(databaseProvider);
  
  final placesRows = await db.select(db.places).get();
  
  final filePlacesRows = await db.select(db.filePlaces).get();
  final counts = <String, int>{};
  for (final fp in filePlacesRows) {
    counts[fp.placeId] = (counts[fp.placeId] ?? 0) + 1;
  }
  
  final hierarchy = <String, Map<String, List<PlaceNode>>>{};
  
  for (final place in placesRows) {
    final count = counts[place.id] ?? 0;
    if (count == 0) continue;
    
    final country = place.country ?? 'Unknown Country';
    final state = place.adminArea ?? 'Unknown State';
    
    hierarchy.putIfAbsent(country, () => {});
    hierarchy[country]!.putIfAbsent(state, () => []);
    hierarchy[country]![state]!.add(PlaceNode(place, count));
  }
  
  return hierarchy.entries.map((e) => PlaceHierarchy(e.key, e.value)).toList();
});

class PlacesScreen extends ConsumerStatefulWidget {
  const PlacesScreen({super.key});

  @override
  ConsumerState<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends ConsumerState<PlacesScreen> {
  Place? _selectedPlace;
  List<FileData> _placeFiles = [];
  bool _isLoadingFiles = false;

  Future<void> _loadPlaceFiles(Place place) async {
    setState(() {
      _selectedPlace = place;
      _isLoadingFiles = true;
    });

    final db = ref.read(databaseProvider);
    final mappings = await (db.select(db.filePlaces)..where((fp) => fp.placeId.equals(place.id))).get();
    
    if (mappings.isEmpty) {
      if (mounted) {
        setState(() {
          _placeFiles = [];
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
        _placeFiles = files;
        _isLoadingFiles = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final placesAsync = ref.watch(placesHierarchyProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(_selectedPlace != null ? Icons.arrow_back : Icons.close, color: Colors.white),
          onPressed: () {
            if (_selectedPlace != null) {
              setState(() {
                _selectedPlace = null;
                _placeFiles = [];
              });
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(
          _selectedPlace != null ? (_selectedPlace!.locality ?? 'Unknown Place') : 'Places & Locations',
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.3),
            radius: 1.8,
            colors: [
              const Color(0xFF10B981).withValues(alpha: 0.15),
              const Color(0xFF3B82F6).withValues(alpha: 0.05),
              AppColors.background,
              AppColors.background,
            ],
          ),
        ),
        child: _selectedPlace != null
            ? _buildPlaceFilesGrid()
            : _buildPlacesList(placesAsync),
      ),
    );
  }

  Widget _buildPlaceFilesGrid() {
    if (_isLoadingFiles) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_placeFiles.isEmpty) {
      return const Center(child: Text('No photos at this location.', style: TextStyle(color: Colors.white54)));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: _placeFiles.length,
      itemBuilder: (context, index) {
        final file = _placeFiles[index];
        return _PlaceGridItem(file: file, siblings: _placeFiles);
      },
    );
  }

  Widget _buildPlacesList(AsyncValue<List<PlaceHierarchy>> placesAsync) {
    return placesAsync.when(
      data: (hierarchies) {
        if (hierarchies.isEmpty) {
          return const Center(child: Text('No location data found in photos.', style: TextStyle(color: Colors.white54)));
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(placesHierarchyProvider);
          },
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: hierarchies.length,
            itemBuilder: (context, index) {
              final hierarchy = hierarchies[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    height: 100,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [Colors.teal.shade800, Colors.blueGrey.shade900],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        const Positioned(
                          right: -10,
                          bottom: -10,
                          child: Icon(Icons.public, size: 100, color: Colors.white10),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              hierarchy.country,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...hierarchy.states.entries.map((stateEntry) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stateEntry.key,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: stateEntry.value.map((cityNode) => InkWell(
                                    onTap: () => _loadPlaceFiles(cityNode.place),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.03),
                                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.location_city, size: 16, color: Colors.tealAccent),
                                          const SizedBox(width: 8),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                cityNode.place.locality ?? 'Unknown',
                                                style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white, fontSize: 13),
                                              ),
                                              Text(
                                                '${cityNode.photoCount} photos',
                                                style: const TextStyle(fontSize: 11, color: Colors.white54),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  )).toList(),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      )),
                ],
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.white))),
    );
  }
}

class _PlaceGridItem extends ConsumerWidget {
  const _PlaceGridItem({required this.file, required this.siblings});
  final FileData file;
  final List<FileData> siblings;

  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder<File?>(
        future: ref.read(thumbnailServiceProvider).getThumbnail(file),
        builder: (context, snapshot) {
          final hasThumb = snapshot.hasData && snapshot.data != null;
          return GestureDetector(
            onTap: () {
              PreviewRouter.openPreview(context, file, siblings: siblings);
            },
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: hasThumb
                  ? Image.file(snapshot.data!, fit: BoxFit.cover)
                  : const Center(child: CircularProgressIndicator()),
            ),
          );
        },
      );
}
