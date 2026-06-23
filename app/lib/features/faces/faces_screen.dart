import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:aerodrive/domain/ai/face_recognition_service.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/features/gallery/thumbnail_service.dart';

class FacesScreen extends ConsumerWidget {
  const FacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final faceService = ref.watch(faceRecognitionServiceProvider);
    final clustersAsync = ref.watch(faceClustersProvider);

    // Respect OS accessibility settings for "Reduce Motion"
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      appBar: AppBar(
        title: const Text('People & Faces'),
        actions: [
          IconButton(
            icon: const Icon(Icons.center_focus_strong_outlined),
            tooltip: 'Scan Drive for Faces',
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Scanning drive for new faces...')),
              );
              await faceService.scanLibrary();
              ref.invalidate(faceClustersProvider);
            },
          )
        ],
      ),
      body: clustersAsync.when(
        data: (clusters) {
          if (clusters.isEmpty) {
            return const Center(child: Text('No faces detected yet.'));
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.8,
            ),
            itemCount: clusters.length,
            itemBuilder: (context, index) {
              final cluster = clusters[index];
              final tile = _FaceTile(cluster: cluster);

              // Apply flutter_animate conditionally
              if (disableAnimations) return tile;

              return tile.animate()
                  .fadeIn(duration: 250.ms, delay: (index * 50).ms)
                  .slideY(begin: 0.05, end: 0, duration: 250.ms, curve: Curves.easeOutQuad);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }
}

class _FaceTile extends ConsumerWidget {
  final FaceCluster cluster;

  const _FaceTile({required this.cluster});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () {
        // Normally this navigates to a photo gallery for this person
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Opening ${cluster.photoCount} photos for ${cluster.label}')),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          Expanded(
            child: cluster.avatarFileId == null
                ? CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.grey.shade800,
                    child: const Icon(Icons.person, size: 50, color: Colors.white54),
                  )
                : FutureBuilder<File?>(
                    future: (() async {
                      final db = ref.read(databaseProvider);
                      final fileData = await (db.select(db.files)..where((f) => f.id.equals(cluster.avatarFileId!))).getSingleOrNull();
                      if (fileData == null) return null;
                      return ref.read(thumbnailServiceProvider).getThumbnail(fileData);
                    })(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.done && snapshot.data != null) {
                        return CircleAvatar(
                          radius: 50,
                          backgroundImage: FileImage(snapshot.data!),
                        );
                      }
                      return CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.grey.shade800,
                        child: const Icon(Icons.person, size: 50, color: Colors.white54),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            cluster.label,
            style: const TextStyle(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${cluster.photoCount} photos',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
