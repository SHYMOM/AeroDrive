import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart' as drift;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/logger.dart';
import '../../data/db/database.dart';

class FaceClusteringEngine {
  static const int embeddingDimension = 128;
  static const double similarityThreshold = 0.72;
  static const Uuid _uuid = Uuid();

  /// Extracts a 128-dimensional normalized feature embedding vector from a cropped face image.
  /// Combines spatial 8x8 block luminance/contrast with facial structural band frequencies.
  static Float32List extractFaceEmbedding(img.Image faceImage, [Face? mlKitFace]) {
    // 1. Standardize face crop to 64x64 grayscale
    final img.Image resized = img.copyResize(faceImage, width: 64, height: 64);
    final img.Image gray = img.grayscale(resized);

    final rawVector = Float32List(embeddingDimension);
    int vecIdx = 0;

    // 2. Spatial 8x8 Block Grid (64 cells) - Average luminance and local contrast
    for (int by = 0; by < 8; by++) {
      for (int bx = 0; bx < 8; bx++) {
        double sum = 0.0;
        double sumSq = 0.0;
        int count = 0;

        for (int y = by * 8; y < (by + 1) * 8; y++) {
          for (int x = bx * 8; x < (bx + 1) * 8; x++) {
            final pixel = gray.getPixel(x, y);
            final lum = pixel.r.toDouble() / 255.0; // grayscale r=g=b
            sum += lum;
            sumSq += lum * lum;
            count++;
          }
        }

        final mean = sum / count;
        final variance = math.max(0.0, (sumSq / count) - (mean * mean));
        final stdDev = math.sqrt(variance);

        // Even indices get mean luminance, odd indices get contrast/edge density
        if (vecIdx < 64) {
          rawVector[vecIdx++] = mean;
        }
      }
    }

    // 3. Structural horizontal and vertical band profiles (32 values)
    // Eyes band (rows 16-28), Nose band (rows 28-42), Mouth band (rows 42-56)
    for (int band = 0; band < 16; band++) {
      final yStart = band * 4;
      double bandMean = 0.0;
      for (int y = yStart; y < yStart + 4; y++) {
        for (int x = 0; x < 64; x++) {
          bandMean += gray.getPixel(x, y).r.toDouble() / 255.0;
        }
      }
      if (vecIdx < 96) {
        rawVector[vecIdx++] = bandMean / 256.0;
      }
    }

    for (int col = 0; col < 16; col++) {
      final xStart = col * 4;
      double colMean = 0.0;
      for (int y = 0; y < 64; y++) {
        for (int x = xStart; x < xStart + 4; x++) {
          colMean += gray.getPixel(x, y).r.toDouble() / 255.0;
        }
      }
      if (vecIdx < 96) {
        rawVector[vecIdx++] = colMean / 256.0;
      }
    }

    // 4. Facial Landmark Geometry (32 values) if ML Kit Face is present,
    // otherwise fallback to center-to-edge radial gradient signatures
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
        final eyeDist = (rightEye.x - leftEye.x).abs() / bw;
        final eyeSlope = (rightEye.y - leftEye.y) / bw;
        rawVector[vecIdx++] = eyeDist;
        rawVector[vecIdx++] = eyeSlope;
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

    // Fill remaining elements up to 128 with radial symmetry values
    while (vecIdx < embeddingDimension) {
      final rIndex = vecIdx - 96;
      final r = (rIndex + 1) * 2;
      double circleSum = 0.0;
      int circleCount = 0;
      for (double angle = 0; angle < 2 * math.pi; angle += 0.3) {
        final cx = (32 + r * math.cos(angle)).round().clamp(0, 63);
        final cy = (32 + r * math.sin(angle)).round().clamp(0, 63);
        circleSum += gray.getPixel(cx, cy).r.toDouble() / 255.0;
        circleCount++;
      }
      rawVector[vecIdx++] = circleCount > 0 ? (circleSum / circleCount) : 0.0;
    }

    // 5. Unit Normalization: ||v|| = 1.0 (enables fast dot-product Cosine Similarity)
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
  /// Scans cached face crops, computes embeddings, and merges clusters with similarity >= similarityThreshold.
  static Future<int> clusterExistingFaces(AeroDriveDatabase db) async {
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
        if (cluster.embedding != null) {
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

              // Save to database
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
