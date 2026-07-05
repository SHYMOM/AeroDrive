import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:drift/drift.dart' as drift;
import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/logger.dart';
import '../data/db/database.dart';

class SmartAnalyzer {

  SmartAnalyzer(this._db);
  final AeroDriveDatabase _db;
  final Uuid _uuid = const Uuid();

  double? _convertExifGps(dynamic gpsTag, String ref) {
    final list = gpsTag.values.toList();
    if (list.length < 3) return null;
    
    double convertRational(dynamic value) {
      if (value is Ratio) {
        return value.numerator / value.denominator;
      }
      return double.tryParse(value.toString()) ?? 0.0;
    }

    final d = convertRational(list[0]);
    final m = convertRational(list[1]);
    final s = convertRational(list[2]);

    double decimal = d + (m / 60.0) + (s / 3600.0);
    if (ref == 'S' || ref == 'W') {
      decimal = -decimal;
    }
    return decimal;
  }

  Future<void> _geocodeLocation(String fileId, double lat, double lng) async {
    try {
      final jsonStr = await rootBundle.loadString('assets/cities.json');
      final List cities = jsonDecode(jsonStr);
      
      Map<String, dynamic>? closestCity;
      double minDistance = double.maxFinite;

      for (final city in cities) {
        final clat = double.tryParse(city['lat'].toString()) ?? 0.0;
        final clng = double.tryParse(city['lng'].toString()) ?? 0.0;
        
        final dx = clat - lat;
        final dy = clng - lng;
        final dist = dx * dx + dy * dy;
        
        if (dist < minDistance) {
          minDistance = dist;
          closestCity = Map<String, dynamic>.from(city);
        }
      }

      if (closestCity != null) {
        final cityName = closestCity['name'] as String;
        final countryName = closestCity['country'] as String;

        var place = await (_db.select(_db.places)
          ..where((p) => p.locality.equals(cityName) & p.country.equals(countryName))
        ).getSingleOrNull();

        if (place == null) {
          final placeId = _uuid.v4();
          await _db.into(_db.places).insert(
            PlacesCompanion.insert(
              id: placeId,
              locality: drift.Value(cityName),
              country: drift.Value(countryName),
            )
          );
          place = await (_db.select(_db.places)..where((p) => p.id.equals(placeId))).getSingle();
        }

        await _db.into(_db.filePlaces).insert(
          FilePlacesCompanion.insert(
            fileId: fileId,
            placeId: place.id,
          ),
          mode: drift.InsertMode.insertOrIgnore,
        );
        AppLogger.info('SmartAnalyzer: Geocoded $fileId to $cityName, $countryName');
      }
    } catch (e) {
      AppLogger.error('SmartAnalyzer: Failed to geocode location', e);
    }
  }

  Future<void> analyzeAndStore(File imageFile, String fileId) async {
    try {
      // 1. EXIF Date and GPS extraction
      DateTime? photoTakenAt;
      double? latitude;
      double? longitude;
      try {
        final fileBytes = await imageFile.readAsBytes();
        final tags = await readExifFromBytes(fileBytes);
        
        final dateTag = tags['Image DateTime'] ?? tags['EXIF DateTimeOriginal'];
        if (dateTag != null) {
          try {
            final str = dateTag.toString();
            final parts = str.split(' ');
            final datePart = parts[0].replaceAll(':', '-');
            photoTakenAt = DateTime.parse('$datePart ${parts[1]}');
          } catch (_) {}
        }

        final latTag = tags['GPS GPSLatitude'];
        final latRef = tags['GPS GPSLatitudeRef'];
        final longTag = tags['GPS GPSLongitude'];
        final longRef = tags['GPS GPSLongitudeRef'];

        if (latTag != null && latRef != null && longTag != null && longRef != null) {
          try {
            latitude = _convertExifGps(latTag, latRef.toString());
            longitude = _convertExifGps(longTag, longRef.toString());
          } catch (_) {}
        }
      } catch (e) {
        AppLogger.error('SmartAnalyzer: Failed to parse EXIF for $fileId', e);
      }

      if (photoTakenAt != null) {
        await (_db.update(_db.files)..where((f) => f.id.equals(fileId))).write(
          FilesCompanion(photoTakenAt: drift.Value(photoTakenAt))
        );
      }

      if (latitude != null && longitude != null) {
        await _geocodeLocation(fileId, latitude, longitude);
      }

      // 2. Machine Learning labels and face detection
      final isDesktop = kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS;
      List<String> labels = [];
      List<Rect> faceRects = [];

      if (isDesktop) {
        // Mock data for desktop testing
        labels = ['Nature', 'Sky', 'Outdoor', 'Pet'];
        final decoded = await img.decodeImageFile(imageFile.path);
        if (decoded != null) {
          final hw = decoded.width / 4;
          final hh = decoded.height / 4;
          faceRects.add(Rect.fromLTWH(decoded.width / 2 - hw/2, decoded.height / 2 - hh/2, hw, hh));
        }
      } else {
        final inputImage = InputImage.fromFile(imageFile);
        
        final labeler = ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.7));
        final mlLabels = await labeler.processImage(inputImage);
        labels = mlLabels.map((l) => l.label).toList();
        labeler.close();

        final faceDetector = FaceDetector(options: FaceDetectorOptions());
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
          final int x = rect.left.toInt().clamp(0, decodedImage.width);
          final int y = rect.top.toInt().clamp(0, decodedImage.height);
          final int w = rect.width.toInt().clamp(1, decodedImage.width - x);
          final int h = rect.height.toInt().clamp(1, decodedImage.height - y);

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
