import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart' as drift;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/logger.dart';
import '../../data/db/database.dart';

class FaceClusteringEngine {
  static const int embeddingDimension = 128;
  static const double similarityThreshold = 0.64;
  static const Uuid _uuid = Uuid();

  /// Extracts an illumination-invariant, 128-dimensional normalized feature embedding vector
  /// from a cropped face image combining Histogram of Oriented Gradients (HOG),
  /// facial chrominance (Cb/Cr), and vertical structural profile bands.
  static Float32List extractFaceEmbedding(img.Image faceImage, [Face? mlKitFace]) {
    // 1. Standardize face crop to 64x64
    final img.Image resizedColor = img.copyResize(faceImage, width: 64, height: 64);
    final img.Image gray = img.grayscale(resizedColor);

    final rawVector = Float32List(embeddingDimension);
    int vecIdx = 0;

    // 2. Spatial Histogram of Oriented Gradients (HOG) - 64 features (4x4 blocks x 4 gradient directions)
    // Invariant to lighting changes, captures contours of eyes, nose, lips, jawline
    const int numBlocksX = 4;
    const int numBlocksY = 4;
    const int blockSize = 16;

    for (int by = 0; by < numBlocksY; by++) {
      for (int bx = 0; bx < numBlocksX; bx++) {
        final startX = bx * blockSize;
        final startY = by * blockSize;
        final bins = [0.0, 0.0, 0.0, 0.0];

        for (int y = startY + 1; y < startY + blockSize - 1; y++) {
          for (int x = startX + 1; x < startX + blockSize - 1; x++) {
            final double dx = (gray.getPixel(x + 1, y).r - gray.getPixel(x - 1, y).r).toDouble();
            final double dy = (gray.getPixel(x, y + 1).r - gray.getPixel(x, y - 1).r).toDouble();
            final double mag = math.sqrt(dx * dx + dy * dy);
            if (mag < 1.0) continue;

            // Angle in degrees [0, 180)
            double angle = (math.atan2(dy, dx) * 180.0 / math.pi);
            if (angle < 0) angle += 180.0;

            // 4 orientation bins: [0°-45°: horizontal, 45°-90°: diagonal1, 90°-135°: vertical, 135°-180°: diagonal2]
            final int bin = (angle / 45.0).floor().clamp(0, 3);
            bins[bin] += mag;
          }
        }

        final double blockTotal = bins.reduce((a, b) => a + b);
        for (int b = 0; b < 4; b++) {
          if (vecIdx < 64) {
            rawVector[vecIdx++] = blockTotal > 0 ? (bins[b] / blockTotal) : 0.25;
          }
        }
      }
    }

    // 3. Facial Chrominance Distribution (Cb / Cr in YCbCr) - 32 features (4x4 blocks x 2 channels)
    // Chrominance (skin pigment/hue) is invariant to lighting brightness and shadow
    for (int by = 0; by < numBlocksY; by++) {
      for (int bx = 0; bx < numBlocksX; bx++) {
        final startX = bx * blockSize;
        final startY = by * blockSize;
        double sumCb = 0.0;
        double sumCr = 0.0;
        int count = 0;

        for (int y = startY; y < startY + blockSize; y++) {
          for (int x = startX; x < startX + blockSize; x++) {
            final pixel = resizedColor.getPixel(x, y);
            final double r = pixel.r.toDouble();
            final double g = pixel.g.toDouble();
            final double b = pixel.b.toDouble();

            final double cb = (-0.168736 * r - 0.331264 * g + 0.5 * b + 128.0) / 255.0;
            final double cr = (0.5 * r - 0.418688 * g - 0.081312 * b + 128.0) / 255.0;
            sumCb += cb;
            sumCr += cr;
            count++;
          }
        }

        if (vecIdx < 96) {
          rawVector[vecIdx++] = count > 0 ? (sumCb / count) : 0.5;
        }
        if (vecIdx < 96) {
          rawVector[vecIdx++] = count > 0 ? (sumCr / count) : 0.5;
        }
      }
    }

    // 4. Facial Geometry & Landmark Proportions - 32 features
    if (mlKitFace != null && mlKitFace.landmarks.isNotEmpty) {
      final box = mlKitFace.boundingBox;
      final bw = math.max(1.0, box.width);
      final bh = math.max(1.0, box.height);

      final leftEye = mlKitFace.landmarks[FaceLandmarkType.leftEye]?.position;
      final rightEye = mlKitFace.landmarks[FaceLandmarkType.rightEye]?.position;
      final nose = mlKitFace.landmarks[FaceLandmarkType.noseBase]?.position;
      final mouth = mlKitFace.landmarks[FaceLandmarkType.bottomMouth]?.position;
      final leftEar = mlKitFace.landmarks[FaceLandmarkType.leftEar]?.position;
      final rightEar = mlKitFace.landmarks[FaceLandmarkType.rightEar]?.position;

      if (leftEye != null && rightEye != null) {
        rawVector[vecIdx++] = (rightEye.x - leftEye.x).abs() / bw;
        rawVector[vecIdx++] = (rightEye.y - leftEye.y) / bw;
      }
      if (leftEye != null && nose != null) {
        rawVector[vecIdx++] = ((nose.x - leftEye.x).abs()) / bw;
        rawVector[vecIdx++] = ((nose.y - leftEye.y).abs()) / bh;
      }
      if (rightEye != null && nose != null) {
        rawVector[vecIdx++] = ((rightEye.x - nose.x).abs()) / bw;
        rawVector[vecIdx++] = ((rightEye.y - nose.y).abs()) / bh;
      }
      if (nose != null && mouth != null) {
        rawVector[vecIdx++] = ((mouth.y - nose.y).abs()) / bh;
        rawVector[vecIdx++] = ((mouth.x - nose.x).abs()) / bw;
      }
      if (leftEar != null && rightEar != null) {
        rawVector[vecIdx++] = (rightEar.x - leftEar.x).abs() / bw;
      }
    }

    // Vertical structural profile bands to complete 128 dimensions
    // Measures relative density of forehead (bands 0-3), eyes (bands 4-7),
    // nose (bands 8-11), and mouth/chin (bands 12-15)
    while (vecIdx < embeddingDimension) {
      final band = (vecIdx - 96) ~/ 2;
      final isVertical = (vecIdx % 2) == 1;
      double bandSum = 0.0;
      int bandCount = 0;

      if (!isVertical) {
        final startY = (band * 4).clamp(0, 60);
        for (int y = startY; y < startY + 4; y++) {
          for (int x = 8; x < 56; x++) {
            bandSum += gray.getPixel(x, y).r.toDouble() / 255.0;
            bandCount++;
          }
        }
      } else {
        final startX = (band * 4).clamp(0, 60);
        for (int y = 8; y < 56; y++) {
          for (int x = startX; x < startX + 4; x++) {
            bandSum += gray.getPixel(x, y).r.toDouble() / 255.0;
            bandCount++;
          }
        }
      }

      rawVector[vecIdx++] = bandCount > 0 ? (bandSum / bandCount) : 0.0;
    }

    // 5. Zero-center vector to remove common DC illumination bias, then normalize to unit sphere
    double sum = 0.0;
    for (int i = 0; i < embeddingDimension; i++) {
      sum += rawVector[i];
    }
    final double mean = sum / embeddingDimension;
    for (int i = 0; i < embeddingDimension; i++) {
      rawVector[i] -= mean;
    }

    return normalize(rawVector);
  }

  /// Calculates Cosine Similarity between two normalized unit embeddings.
  /// Result is in range [-1.0, 1.0], where 1.0 means identical.
  static double cosineSimilarity(Float32List a, Float32List b) {
    if (a.length != b.length) return 0.0;
    double dot = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot.clamp(-1.0, 1.0);
  }

  /// Normalizes a vector to unit length (L2 norm).
  static Float32List normalize(Float32List v) {
    double norm = 0.0;
    for (int i = 0; i < v.length; i++) {
      norm += v[i] * v[i];
    }
    norm = math.sqrt(norm);
    if (norm == 0.0 || norm.isNaN || norm.isInfinite) return v;

    final out = Float32List(v.length);
    for (int i = 0; i < v.length; i++) {
      out[i] = v[i] / norm;
    }
    return out;
  }

  /// Converts Float32List embedding to Uint8List for SQLite BLOB storage.
  static Uint8List embeddingToBlob(Float32List embedding) {
    return Uint8List.view(embedding.buffer, embedding.offsetInBytes, embedding.lengthInBytes);
  }

  /// Converts SQLite BLOB to Float32List embedding.
  static Float32List? blobToEmbedding(Uint8List? blob) {
    if (blob == null || blob.lengthInBytes != embeddingDimension * 4) return null;
    return Float32List.view(blob.buffer, blob.offsetInBytes, embeddingDimension);
  }

  /// Finds the best matching existing face cluster for the given face embedding,
  /// or creates a new cluster if similarity < similarityThreshold.
  static Future<String> findOrCreateCluster({
    required AeroDriveDatabase db,
    required Float32List newEmbedding,
    Face? mlKitFace,
  }) async {
    final existingClusters = await db.select(db.faceClusters).get();

    String? bestClusterId;
    double bestSimilarity = -1.0;
    Float32List? bestClusterEmbedding;

    for (final cluster in existingClusters) {
      if (cluster.embedding != null) {
        final emb = blobToEmbedding(cluster.embedding);
        if (emb != null) {
          final sim = cosineSimilarity(newEmbedding, emb);
          if (sim > bestSimilarity) {
            bestSimilarity = sim;
            bestClusterId = cluster.id;
            bestClusterEmbedding = emb;
          }
        }
      }
    }

    // Match found! Assign to existing cluster and update running average embedding
    if (bestClusterId != null && bestSimilarity >= similarityThreshold) {
      AppLogger.info('FaceClustering: Matched existing cluster $bestClusterId (similarity: ${bestSimilarity.toStringAsFixed(3)})');

      if (bestClusterEmbedding != null) {
        final updated = Float32List(embeddingDimension);
        for (int i = 0; i < embeddingDimension; i++) {
          updated[i] = 0.85 * bestClusterEmbedding[i] + 0.15 * newEmbedding[i];
        }
        final normalizedUpdated = normalize(updated);
        await (db.update(db.faceClusters)..where((fc) => fc.id.equals(bestClusterId!))).write(
          FaceClustersCompanion(embedding: drift.Value(embeddingToBlob(normalizedUpdated)))
        );
      }

      return bestClusterId;
    }

    // No match: Create new face cluster
    final newClusterId = _uuid.v4();
    await db.into(db.faceClusters).insert(
      FaceClustersCompanion.insert(
        id: newClusterId,
        embedding: drift.Value(embeddingToBlob(newEmbedding)),
      ),
      mode: drift.InsertMode.insertOrIgnore,
    );
    AppLogger.info('FaceClustering: Created new face cluster $newClusterId');
    return newClusterId;
  }

  /// Clusters existing un-clustered or duplicate face clusters in SQLite into unified person folders.
  /// Scans cached face crops, computes robust LBP/color embeddings, and merges clusters with similarity >= similarityThreshold.
  static Future<int> clusterExistingFaces(AeroDriveDatabase db, {bool forceRecompute = false}) async {
    try {
      final cacheDir = await getApplicationSupportDirectory();
      final facesDir = Directory('${cacheDir.path}/faces');
      if (!await facesDir.exists()) return 0;

      final allFaceFiles = facesDir.listSync().whereType<File>().toList();
      if (allFaceFiles.isEmpty) return 0;

      final clusters = await db.select(db.faceClusters).get();
      if (clusters.length < 2) return 0;

      final Map<String, Float32List> clusterEmbeddings = {};

      for (final cluster in clusters) {
        if (!forceRecompute && cluster.embedding != null) {
          final emb = blobToEmbedding(cluster.embedding);
          if (emb != null) {
            clusterEmbeddings[cluster.id] = emb;
            continue;
          }
        }

        // Compute embedding from disk face crop
        final match = allFaceFiles.firstWhere(
          (f) => f.path.split(Platform.pathSeparator).last.startsWith(cluster.id),
          orElse: () => File(''),
        );

        if (match.path.isNotEmpty && await match.exists()) {
          try {
            final bytes = await match.readAsBytes();
            final decoded = img.decodeImage(bytes);
            if (decoded != null) {
              final emb = extractFaceEmbedding(decoded);
              clusterEmbeddings[cluster.id] = emb;

              // Save updated robust embedding to database
              await (db.update(db.faceClusters)..where((fc) => fc.id.equals(cluster.id))).write(
                FaceClustersCompanion(embedding: drift.Value(embeddingToBlob(emb)))
              );
            }
          } catch (_) {}
        }
      }

      if (clusterEmbeddings.length < 2) return 0;

      // Group clusters that belong to the same person
      final clusterIds = clusterEmbeddings.keys.toList();
      final Map<String, String> mergeTo = {}; // duplicateClusterId -> primaryClusterId

      for (int i = 0; i < clusterIds.length; i++) {
        final idA = clusterIds[i];
        final rootA = _findRoot(mergeTo, idA);
        final embA = clusterEmbeddings[idA]!;

        for (int j = i + 1; j < clusterIds.length; j++) {
          final idB = clusterIds[j];
          final rootB = _findRoot(mergeTo, idB);

          if (rootA == rootB) continue;

          final embB = clusterEmbeddings[idB]!;
          final sim = cosineSimilarity(embA, embB);

          if (sim >= similarityThreshold) {
            AppLogger.info('FaceClustering: Merging duplicate face cluster $idB into $rootA (similarity: ${sim.toStringAsFixed(3)})');
            mergeTo[rootB] = rootA;
          }
        }
      }

      int mergedCount = 0;
      for (final entry in mergeTo.entries) {
        final dupId = entry.key;
        final targetId = _findRoot(mergeTo, dupId);
        if (dupId == targetId) continue;

        // Preserve name if duplicate has a name and target doesn't
        final dupCluster = clusters.firstWhereOrNull((c) => c.id == dupId);
        final targetCluster = clusters.firstWhereOrNull((c) => c.id == targetId);
        if (dupCluster?.name != null && dupCluster!.name!.isNotEmpty &&
            (targetCluster?.name == null || targetCluster!.name!.isEmpty)) {
          await (db.update(db.faceClusters)..where((fc) => fc.id.equals(targetId))).write(
            FaceClustersCompanion(name: drift.Value(dupCluster.name))
          );
        }

        // Reassign all photo_faces mappings to primary cluster
        await (db.update(db.photoFaces)..where((pf) => pf.faceClusterId.equals(dupId))).write(
          PhotoFacesCompanion(faceClusterId: drift.Value(targetId))
        );

        // Delete duplicate cluster
        await (db.delete(db.faceClusters)..where((fc) => fc.id.equals(dupId))).go();
        mergedCount++;
      }

      if (mergedCount > 0) {
        AppLogger.info('FaceClustering: Successfully merged $mergedCount duplicate face clusters into unified person folders!');
      }

      return mergedCount;
    } catch (e, s) {
      AppLogger.error('FaceClustering: Failed to cluster existing faces', e, s);
      return 0;
    }
  }

  static String _findRoot(Map<String, String> parent, String id) {
    if (!parent.containsKey(id)) return id;
    final root = _findRoot(parent, parent[id]!);
    parent[id] = root; // path compression
    return root;
  }
}
