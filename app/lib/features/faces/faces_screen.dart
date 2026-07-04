import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:path_provider/path_provider.dart';

final facesListProvider = FutureProvider<List<File>>((ref) async {
  final cacheDir = await getApplicationSupportDirectory();
  final facesDir = Directory('${cacheDir.path}/faces');
  if (!await facesDir.exists()) return [];

  final files = facesDir.listSync().whereType<File>().toList();
  // Sort by last modified descending
  files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  return files;
});

class FacesScreen extends ConsumerWidget {
  const FacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facesAsync = ref.watch(facesListProvider);
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      appBar: AppBar(
        title: const Text('People & Faces'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Gallery',
            onPressed: () {
              ref.invalidate(facesListProvider);
            },
          )
        ],
      ),
      body: facesAsync.when(
        data: (faces) {
          if (faces.isEmpty) {
            return const Center(child: Text('No faces detected yet.'));
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(facesListProvider);
            },
            child: MasonryGridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverSimpleGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
              ),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              itemCount: faces.length,
              itemBuilder: (context, index) {
                final file = faces[index];
                
                final child = ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      // Using a transparent memory image as a placeholder for FadeInImage
                      // so we get a smooth fade in when the actual file image loads.
                      FadeInImage(
                        placeholder: MemoryImage(kTransparentImage),
                        image: FileImage(file),
                        fit: BoxFit.cover,
                        fadeInDuration: const Duration(milliseconds: 300),
                      ),
                      Positioned.fill(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              // Extract file ID from face image filename (format: fileId_index.jpg)
                              // Extract file ID from face image filename
                              // Supports both legacy (fileId_index.jpg) and new (clusterId_fileId.jpg) formats.
                              final filename = file.path.split(Platform.pathSeparator).last;
                              final parts = filename.split('_');
                              String fileId = filename.split('.').first;
                              if (parts.length >= 2) {
                                final secondPart = parts[1].split('.').first;
                                // Legacy index is short (e.g. 0, 1), new fileId is a UUID (length > 5)
                                if (secondPart.length > 5) {
                                  fileId = secondPart;
                                } else {
                                  fileId = parts[0];
                                }
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Tapped face from file: $fileId')),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                );

                if (disableAnimations) return child;

                return child.animate()
                    .fadeIn(duration: 250.ms, delay: ((index % 12) * 50).ms)
                    .slideY(begin: 0.05, end: 0, duration: 250.ms, curve: Curves.easeOutQuad);
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

// 1x1 transparent pixel for the placeholder
final Uint8List kTransparentImage = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);
