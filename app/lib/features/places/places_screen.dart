import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as latlong2;

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/db/database.dart';
import '../gallery/thumbnail_service.dart';
import '../preview/preview_router.dart';
import 'places_service.dart';

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
  // Automatically backfill any missing place records from photo EXIF GPS & timeline
  await ref.read(placesServiceProvider).backfillPlaces();

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
  bool _isMapView = false;

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
          icon: Icon(_selectedPlace != null ? Icons.arrow_back : Icons.close, color: Theme.of(context).colorScheme.onSurface),
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
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_selectedPlace == null)
            IconButton(
              icon: Icon(
                _isMapView ? Icons.view_list_rounded : Icons.map_rounded,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              tooltip: _isMapView ? 'Switch to List View' : 'Switch to World Map',
              onPressed: () => setState(() => _isMapView = !_isMapView),
            ),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.3),
            radius: 1.8,
            colors: [
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
              Theme.of(context).colorScheme.secondary.withValues(alpha: 0.05),
              AppColors.background,
              AppColors.background,
            ],
          ),
        ),
        child: _selectedPlace != null
            ? _buildPlaceFilesGrid()
            : (_isMapView ? _buildPlacesMap(placesAsync) : _buildPlacesList(placesAsync)),
      ),
    );
  }

  Widget _buildPlaceFilesGrid() {
    if (_isLoadingFiles) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_placeFiles.isEmpty) {
      return Center(child: Text('No photos at this location.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)));
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
          return Center(child: Text('No location data found in photos.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)));
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
                        colors: [Theme.of(context).colorScheme.primary.withValues(alpha: 0.7), Theme.of(context).colorScheme.surface],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          right: -10,
                          bottom: -10,
                          child: Icon(Icons.public, size: 100, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1)),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              hierarchy.country,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.onSurface,
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
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.location_city, size: 16, color: Theme.of(context).colorScheme.primary),
                                          const SizedBox(width: 8),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                cityNode.place.locality ?? 'Unknown',
                                                style: TextStyle(fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
                                              ),
                                              Text(
                                                '${cityNode.photoCount} photos',
                                                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
      error: (err, stack) => Center(child: Text('Error: $err', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
    );
  }

  Widget _buildPlacesMap(AsyncValue<List<PlaceHierarchy>> placesAsync) {
    return placesAsync.when(
      data: (hierarchies) {
        final List<PlaceNode> nodesWithCoords = [];
        for (final h in hierarchies) {
          for (final stateList in h.states.values) {
            for (final node in stateList) {
              if (node.place.latitude != null && node.place.longitude != null) {
                nodesWithCoords.add(node);
              }
            }
          }
        }

        if (nodesWithCoords.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.map_outlined, size: 64, color: Theme.of(context).colorScheme.outlineVariant),
                const SizedBox(height: 16),
                Text(
                  'No GPS coordinates found for places yet.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          );
        }

        final double avgLat = nodesWithCoords.map((n) => n.place.latitude!).reduce((a, b) => a + b) / nodesWithCoords.length;
        final double avgLng = nodesWithCoords.map((n) => n.place.longitude!).reduce((a, b) => a + b) / nodesWithCoords.length;

        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: FlutterMap(
            options: MapOptions(
              initialCenter: latlong2.LatLng(avgLat, avgLng),
              initialZoom: 4.0,
              minZoom: 2.0,
              maxZoom: 18.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.aerodrive.aerodrive',
              ),
              MarkerLayer(
                markers: nodesWithCoords.map((node) {
                  return Marker(
                    point: latlong2.LatLng(node.place.latitude!, node.place.longitude!),
                    width: 76,
                    height: 76,
                    child: GestureDetector(
                      onTap: () => _loadPlaceFiles(node.place),
                      child: _PlaceMarkerBadge(node: node),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
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
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
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

class _PlaceMarkerBadge extends StatelessWidget {
  const _PlaceMarkerBadge({required this.node});
  final PlaceNode node;

  @override
  Widget build(BuildContext context) {
    final cityName = node.place.locality ?? 'Place';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.photo_library, size: 12, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                '${node.photoCount}',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            cityName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ),
        const Icon(Icons.arrow_drop_down, color: Colors.black87, size: 16),
      ],
    );
  }
}

