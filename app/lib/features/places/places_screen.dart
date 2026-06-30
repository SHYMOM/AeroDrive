import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:drift/drift.dart' as drift;

class PlaceNode {
  final Place place;
  final int photoCount;

  PlaceNode(this.place, this.photoCount);
}

class PlaceHierarchy {
  final String country;
  final Map<String, List<PlaceNode>> states;

  PlaceHierarchy(this.country, this.states);
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

class PlacesScreen extends ConsumerWidget {
  const PlacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placesAsync = ref.watch(placesHierarchyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Places & Locations'),
      ),
      body: placesAsync.when(
        data: (hierarchies) {
          if (hierarchies.isEmpty) {
            return const Center(child: Text('No location data found in photos.'));
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
                return _CountrySection(hierarchy: hierarchy);
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }
}

class _CountrySection extends StatelessWidget {
  final PlaceHierarchy hierarchy;

  const _CountrySection({required this.hierarchy});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Premium Country Header
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [Colors.blue.shade800, Colors.indigo.shade900],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Stack(
            children: [
              const Positioned(
                right: -20,
                bottom: -20,
                child: Icon(Icons.public, size: 120, color: Colors.white10),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(
                    hierarchy.country,
                    style: const TextStyle(
                      fontSize: 32,
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
        
        // States and Cities
        ...hierarchy.states.entries.map((stateEntry) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stateEntry.key,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: stateEntry.value.map((cityNode) {
                    return InkWell(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Opening ${cityNode.photoCount} photos for ${cityNode.place.locality}')),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                          border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.2)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_city, size: 18, color: Colors.blueAccent),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cityNode.place.locality ?? 'Unknown',
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                                Text(
                                  '${cityNode.photoCount} photos',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        }),
      ],
    );
  }
}
