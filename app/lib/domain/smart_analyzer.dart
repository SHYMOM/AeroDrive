import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:aerodrive/core/logger.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:drift/drift.dart' as drift;
import 'package:image/image.dart' as img;

class SmartAnalyzer {
  final AeroDriveDatabase _db;
  final Uuid _uuid = const Uuid();

  SmartAnalyzer(this._db);

  Future<void> analyzeAndStore(File imageFile, String fileId) async {
    try {
      final isDesktop = kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS;
      List<String> labels = [];
      List<Rect> faceRects = [];

      if (isDesktop) {
        // Mock data for desktop testing
        labels = ['Nature', 'Sky', 'Outdoor', 'Pet'];
        // Fake a face rect in the center
        final decoded = await img.decodeImageFile(imageFile.path);
        if (decoded != null) {
          final hw = decoded.width / 4;
          final hh = decoded.height / 4;
          faceRects.add(Rect.fromLTWH(decoded.width / 2 - hw/2, decoded.height / 2 - hh/2, hw, hh));
        }
      } else {
        // Native ML Kit execution
        final inputImage = InputImage.fromFile(imageFile);
        
        // Labels
        final labeler = ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.7));
        final mlLabels = await labeler.processImage(inputImage);
        labels = mlLabels.map((l) => l.label).toList();
        labeler.close();

        // Faces
        final faceDetector = FaceDetector(options: FaceDetectorOptions(enableContours: false, enableLandmarks: false));
        final faces = await faceDetector.processImage(inputImage);
        faceRects = faces.map((f) => f.boundingBox).toList();
        faceDetector.close();
      }

      await _storeLabels(labels, fileId);
      if (faceRects.isNotEmpty) {
        await _processAndStoreFaces(imageFile, faceRects, fileId);
      }
    } catch (e) {
      AppLogger.error('SmartAnalyzer failed for $fileId', e);
    }
  }

  Future<void> _storeLabels(List<String> labels, String fileId) async {
    for (final label in labels) {
      // Find or create tag
      var tag = await (_db.select(_db.tags)..where((t) => t.name.equals(label))).getSingleOrNull();
      if (tag == null) {
        final tagId = _uuid.v4();
        await _db.into(_db.tags).insert(
          TagsCompanion.insert(
            id: tagId,
            name: label,
            source: const drift.Value('ML_LABEL'),
          )
        );
        tag = await (_db.select(_db.tags)..where((t) => t.id.equals(tagId))).getSingle();
      }

      // Link file to tag
      await _db.into(_db.fileTags).insert(
        FileTagsCompanion.insert(
          fileId: fileId,
          tagId: tag.id,
        )
      );
    }
  }

  Future<void> _processAndStoreFaces(File imageFile, List<Rect> faceRects, String fileId) async {
    img.Image? decodedImage;

    for (final rect in faceRects) {
      // Create a mock cluster for each face
      final clusterId = _uuid.v4();
      await _db.into(_db.faceClusters).insert(
        FaceClustersCompanion.insert(
          id: clusterId,
        )
      );

      // Link to file
      await _db.into(_db.photoFaces).insert(
        PhotoFacesCompanion.insert(
          fileId: fileId,
          faceClusterId: clusterId,
        )
      );

      // Crop and save face to cache for UI
      try {
        decodedImage ??= await img.decodeImageFile(imageFile.path);
        if (decodedImage != null) {
          // Clamp rect to image bounds
          int x = rect.left.toInt().clamp(0, decodedImage.width);
          int y = rect.top.toInt().clamp(0, decodedImage.height);
          int w = rect.width.toInt().clamp(1, decodedImage.width - x);
          int h = rect.height.toInt().clamp(1, decodedImage.height - y);

          if (w > 0 && h > 0) {
            final cropped = img.copyCrop(decodedImage, x: x, y: y, width: w, height: h);
            final cacheDir = await getApplicationSupportDirectory();
            final facesDir = Directory('${cacheDir.path}/faces');
            if (!await facesDir.exists()) await facesDir.create(recursive: true);

            final faceFile = File('${facesDir.path}/${clusterId}_${_uuid.v4()}.png');
            await faceFile.writeAsBytes(img.encodePng(cropped));
          }
        }
      } catch (e) {
        AppLogger.error('Failed to crop face for $fileId', e);
      }
    }
  }
}
