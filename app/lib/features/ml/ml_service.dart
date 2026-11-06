import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/logger.dart';
import '../../core/providers.dart';
import '../../data/db/database.dart';
import '../../domain/ai/face_clustering_engine.dart';
import '../gallery/thumbnail_service.dart';
import '../tags/tag_service.dart';

class CropTaskArgs {

  CropTaskArgs({
    required this.imagePath,
    required this.outputPath,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
  final String imagePath;
  final String outputPath;
  final int left;
  final int top;
  final int width;
  final int height;
}

Future<void> _cropFaceIsolate(CropTaskArgs args) async {
  final imageBytes = await File(args.imagePath).readAsBytes();
  final decodedImage = img.decodeImage(imageBytes);
  if (decodedImage == null) return;

  // Add 10% padding to the bounding box for a better crop
  final int padX = (args.width * 0.1).toInt();
  final int padY = (args.height * 0.1).toInt();

  final int x = (args.left - padX).clamp(0, decodedImage.width);
  final int y = (args.top - padY).clamp(0, decodedImage.height);
  final int w = (args.width + padX * 2).clamp(0, decodedImage.width - x);
  final int h = (args.height + padY * 2).clamp(0, decodedImage.height - y);

  final cropped = img.copyCrop(decodedImage, x: x, y: y, width: w, height: h);
  // Enhance face profile with slight saturation, contrast, and brightness boost
  final enhanced = img.adjustColor(
    cropped,
    contrast: 1.15,
    brightness: 1.05,
    saturation: 1.1,
  );
  final resized = img.copyResize(enhanced, width: 256, height: 256); // uniform size
  final jpg = img.encodeJpg(resized, quality: 85);

  final outFile = File(args.outputPath);
  await outFile.parent.create(recursive: true);
  await outFile.writeAsBytes(jpg);
}

class MLService {

  MLService(this._ref);
  final Ref _ref;

  Future<void> processImage(FileData file) async {
    if (file.mimeType == null || !file.mimeType!.startsWith('image/')) return;

    if (!Platform.isAndroid && !Platform.isIOS) {
      AppLogger.info('ML Kit skipped: Not on Android/iOS');
      return;
    }

    try {
      final thumbnailFile = await _ref.read(thumbnailServiceProvider).getThumbnail(file);
      if (thumbnailFile == null) return;

      final inputImage = InputImage.fromFile(thumbnailFile);
      
      // 1. Image Labeling
      final labelerOptions = ImageLabelerOptions(confidenceThreshold: 0.7);
      final imageLabeler = ImageLabeler(options: labelerOptions);
      final labels = await imageLabeler.processImage(inputImage);
      imageLabeler.close();

      final tagService = _ref.read(tagServiceProvider);
      for (final label in labels) {
        final tagName = label.label.toLowerCase();
        final tag = await tagService.getOrCreateTag(tagName);
        await tagService.attachTagToFile(file.id, tag.id);
      }
      AppLogger.info('Successfully labeled ${file.name} with ${labels.length} tags.');

      // 2. Face Detection (Accurate mode, detects multiple faces & small faces in group photos)
      final faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableLandmarks: true,
          enableClassification: true,
          performanceMode: FaceDetectorMode.accurate,
          minFaceSize: 0.03, // Detect small faces in multi-person photos
        ),
      );
      
      final faces = await faceDetector.processImage(inputImage);
      faceDetector.close();
      
      if (faces.isNotEmpty) {
        AppLogger.info('Found ${faces.length} faces in ${file.name}');
        
        final cacheDir = await getApplicationSupportDirectory();
        final facesDir = Directory('${cacheDir.path}/faces');
        if (!await facesDir.exists()) {
          await facesDir.create(recursive: true);
        }
        final db = _ref.read(databaseProvider);
        const uuid = Uuid();

        for (var i = 0; i < faces.length; i++) {
          final face = faces[i];
          final tempCropId = uuid.v4();
          final cropPath = '${facesDir.path}/${tempCropId}_${file.id}.jpg';

          // Crop in background
          await compute(_cropFaceIsolate, CropTaskArgs(
            imagePath: thumbnailFile.path,
            outputPath: cropPath,
            left: face.boundingBox.left.toInt(),
            top: face.boundingBox.top.toInt(),
            width: face.boundingBox.width.toInt(),
            height: face.boundingBox.height.toInt(),
          ));

          // Compute embedding and find/cluster with existing people
          String clusterId;
          final cropFile = File(cropPath);
          if (await cropFile.exists()) {
            final cropBytes = await cropFile.readAsBytes();
            final decodedCrop = img.decodeImage(cropBytes);
            if (decodedCrop != null) {
              final embedding = FaceClusteringEngine.extractFaceEmbedding(decodedCrop, face);
              clusterId = await FaceClusteringEngine.findOrCreateCluster(
                db: db,
                newEmbedding: embedding,
                mlKitFace: face,
              );
              // Rename crop file so it matches the clustered person id
              final finalPath = '${facesDir.path}/${clusterId}_${file.id}.jpg';
              if (finalPath != cropPath) {
                try {
                  await cropFile.rename(finalPath);
                } catch (_) {}
              }
            } else {
              clusterId = tempCropId;
            }
          } else {
            clusterId = tempCropId;
          }

          // Link photo to person cluster
          await db.into(db.photoFaces).insert(
            PhotoFacesCompanion.insert(
              id: uuid.v4(),
              fileId: file.id,
              faceClusterId: clusterId,
              confidence: const drift.Value(0.9),
              boxLeft: drift.Value(face.boundingBox.left),
              boxTop: drift.Value(face.boundingBox.top),
              boxWidth: drift.Value(face.boundingBox.width),
              boxHeight: drift.Value(face.boundingBox.height),
            ),
            mode: drift.InsertMode.insertOrIgnore,
          );
        }
      }

    } catch (e, s) {
      AppLogger.error('Failed to run ML processing', e, s);
    }
  }

  Future<void> processImageBatch(List<FileData> files) async {
    for (final file in files) {
      await processImage(file);
    }
  }
}

final mlServiceProvider = Provider<MLService>(MLService.new);
