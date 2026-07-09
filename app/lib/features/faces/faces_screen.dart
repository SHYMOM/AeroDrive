import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' as drift;
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:collection/collection.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/db/database.dart';
import '../gallery/thumbnail_service.dart';
import '../preview/preview_router.dart';

class FaceClusterModel {
  final String id;
  final String? name;
  final File? cropFile;
  final List<FileData> photos;

  FaceClusterModel({
    required this.id,
    this.name,
    this.cropFile,
    required this.photos,
  });
}

final faceClustersProvider = FutureProvider<List<FaceClusterModel>>((ref) async {
  final db = ref.watch(databaseProvider);
  
  final clusters = await db.select(db.faceClusters).get();
  final mappings = await db.select(db.photoFaces).get();
  
  final cacheDir = await getApplicationSupportDirectory();
  final facesDir = Directory('${cacheDir.path}/faces');
  if (!await facesDir.exists()) {
    await facesDir.create(recursive: true);
  }
  
  List<File> cropFiles = [];
  if (await facesDir.exists()) {
    cropFiles = facesDir.listSync().whereType<File>().toList();
  }

  final List<FaceClusterModel> list = [];
  const uuid = Uuid();

  for (final cluster in clusters) {
    // Find associated files
    final fileIds = mappings.where((m) => m.faceClusterId == cluster.id).map((m) => m.fileId).toList();
    if (fileIds.isEmpty) continue;

    final photos = await (db.select(db.files)
      ..where((f) => f.id.isIn(fileIds) & f.deletedAt.isNull())
    ).get();

    if (photos.isEmpty) continue;

    // Find cover crop file matching cluster.id
    var coverFile = cropFiles.firstWhereOrNull(
      (f) => f.path.split(Platform.pathSeparator).last.startsWith(cluster.id),
    );

    if (coverFile == null && photos.isNotEmpty) {
      try {
        final firstFile = photos.first;
        final mapping = mappings.firstWhereOrNull((m) => m.faceClusterId == cluster.id && m.fileId == firstFile.id);
        if (mapping != null && mapping.boxLeft != null && mapping.boxTop != null && mapping.boxWidth != null && mapping.boxHeight != null) {
          final thumbFile = await ref.read(thumbnailServiceProvider).getThumbnail(firstFile);
          if (thumbFile != null && await thumbFile.exists()) {
            final bytes = await thumbFile.readAsBytes();
            final thumbImage = img.decodeImage(bytes);
            if (thumbImage != null) {
              final int x = (mapping.boxLeft! * thumbImage.width).toInt().clamp(0, thumbImage.width);
              final int y = (mapping.boxTop! * thumbImage.height).toInt().clamp(0, thumbImage.height);
              final int w = (mapping.boxWidth! * thumbImage.width).toInt().clamp(1, thumbImage.width - x);
              final int h = (mapping.boxHeight! * thumbImage.height).toInt().clamp(1, thumbImage.height - y);

              if (w > 0 && h > 0) {
                final cropped = img.copyCrop(thumbImage, x: x, y: y, width: w, height: h);
                final faceFile = File('${facesDir.path}/${cluster.id}_${uuid.v4()}.png');
                await faceFile.writeAsBytes(img.encodePng(cropped));
                coverFile = faceFile;
                debugPrint('Dynamic Face Crop: Generated cover crop for cluster ${cluster.id} from local thumbnail');
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Dynamic Face Crop: Failed to generate cover crop for ${cluster.id}: $e');
      }
    }

    list.add(FaceClusterModel(
      id: cluster.id,
      name: cluster.name,
      cropFile: coverFile,
      photos: photos,
    ));
  }

  return list;
});

class FacesScreen extends ConsumerStatefulWidget {
  const FacesScreen({super.key});

  @override
  ConsumerState<FacesScreen> createState() => _FacesScreenState();
}

class _FacesScreenState extends ConsumerState<FacesScreen> {
  FaceClusterModel? _selectedCluster;
  bool _isSelectionMode = false;
  final Set<String> _selectedClusterIds = {};

  Future<void> _renameCluster(FaceClusterModel cluster) async {
    final controller = TextEditingController(text: cluster.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Name this person', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter name',
            hintStyle: TextStyle(color: Colors.white30),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );

    if (newName == null) return;

    final db = ref.read(databaseProvider);
    await (db.update(db.faceClusters)..where((fc) => fc.id.equals(cluster.id))).write(
      FaceClustersCompanion(name: drift.Value(newName.isEmpty ? null : newName))
    );

    ref.invalidate(faceClustersProvider);
    if (_selectedCluster?.id == cluster.id) {
      setState(() {
        _selectedCluster = FaceClusterModel(
          id: cluster.id,
          name: newName.isEmpty ? null : newName,
          cropFile: cluster.cropFile,
          photos: cluster.photos,
        );
      });
    }
  }

  Future<void> _mergeSelectedClusters() async {
    if (_selectedClusterIds.length < 2) return;

    final clusters = await ref.read(faceClustersProvider.future);
    final selectedModels = clusters.where((c) => _selectedClusterIds.contains(c.id)).toList();

    // Identify target cluster (prefer the one that already has a name, or the first one)
    final target = selectedModels.firstWhereOrNull((c) => c.name != null && c.name!.isNotEmpty) ?? selectedModels.first;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Merge Face Clusters', style: TextStyle(color: Colors.white)),
        content: Text(
          'Do you want to merge these ${_selectedClusterIds.length} people under the name "${target.name ?? 'Unnamed Person'}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Merge', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final db = ref.read(databaseProvider);

    for (final model in selectedModels) {
      if (model.id == target.id) continue;

      // Update mapping references to the target cluster ID
      await (db.update(db.photoFaces)..where((pf) => pf.faceClusterId.equals(model.id))).write(
        PhotoFacesCompanion(faceClusterId: drift.Value(target.id))
      );

      // Delete the old cluster entry
      await (db.delete(db.faceClusters)..where((fc) => fc.id.equals(model.id))).go();
    }

    setState(() {
      _isSelectionMode = false;
      _selectedClusterIds.clear();
    });

    ref.invalidate(faceClustersProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Successfully merged people clusters.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clustersAsync = ref.watch(faceClustersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(_selectedCluster != null ? Icons.arrow_back : Icons.close, color: Colors.white),
          onPressed: () {
            if (_selectedCluster != null) {
              setState(() {
                _selectedCluster = null;
              });
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(
          _selectedCluster != null 
              ? (_selectedCluster!.name ?? 'Unnamed Person') 
              : 'People & Faces',
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_selectedCluster == null) ...[
            if (_isSelectionMode) ...[
              IconButton(
                icon: const Icon(Icons.merge_type, color: AppColors.primary),
                tooltip: 'Merge Selected',
                onPressed: _selectedClusterIds.length >= 2 ? _mergeSelectedClusters : null,
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _isSelectionMode = false;
                    _selectedClusterIds.clear();
                  });
                },
              ),
            ] else
              IconButton(
                icon: const Icon(Icons.select_all, color: Colors.white),
                tooltip: 'Select to Merge',
                onPressed: () {
                  setState(() {
                    _isSelectionMode = true;
                  });
                },
              ),
          ] else
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white),
              tooltip: 'Rename',
              onPressed: () => _renameCluster(_selectedCluster!),
            ),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.3),
            radius: 1.8,
            colors: [
              const Color(0xFF3B82F6).withValues(alpha: 0.15),
              const Color(0xFF8B5CF6).withValues(alpha: 0.05),
              AppColors.background,
              AppColors.background,
            ],
          ),
        ),
        child: _selectedCluster != null
            ? _buildClusterPhotosGrid()
            : _buildClustersList(clustersAsync),
      ),
    );
  }

  Widget _buildClustersList(AsyncValue<List<FaceClusterModel>> clustersAsync) {
    return clustersAsync.when(
      data: (clusters) {
        if (clusters.isEmpty) {
          return const Center(child: Text('No faces detected yet.', style: TextStyle(color: Colors.white54)));
        }

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.85,
          ),
          itemCount: clusters.length,
          itemBuilder: (context, index) {
            final cluster = clusters[index];
            final isSelected = _selectedClusterIds.contains(cluster.id);

            return GestureDetector(
              onTap: () {
                if (_isSelectionMode) {
                  setState(() {
                    if (isSelected) {
                      _selectedClusterIds.remove(cluster.id);
                    } else {
                      _selectedClusterIds.add(cluster.id);
                    }
                  });
                } else {
                  setState(() {
                    _selectedCluster = cluster;
                  });
                }
              },
              onLongPress: () {
                if (!_isSelectionMode) {
                  setState(() {
                    _isSelectionMode = true;
                    _selectedClusterIds.add(cluster.id);
                  });
                }
              },
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected 
                            ? AppColors.primary 
                            : Colors.white.withValues(alpha: 0.05),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: cluster.cropFile != null
                              ? Image.file(cluster.cropFile!, fit: BoxFit.cover)
                              : Container(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  child: const Icon(Icons.person, color: Colors.white30, size: 28),
                                ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Column(
                            children: [
                              Text(
                                cluster.name ?? 'Unnamed',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                              Text(
                                '${cluster.photos.length} photos',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check, size: 12, color: Colors.black),
                      ),
                    ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms, delay: (index * 50).ms);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.white))),
    );
  }

  Widget _buildClusterPhotosGrid() {
    final siblingPhotos = _selectedCluster!.photos;
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: siblingPhotos.length,
      itemBuilder: (context, index) {
        final file = siblingPhotos[index];
        return _FaceGridItem(file: file, siblings: siblingPhotos);
      },
    );
  }
}

class _FaceGridItem extends ConsumerWidget {
  const _FaceGridItem({required this.file, required this.siblings});
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

final Uint8List kTransparentImage = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);
