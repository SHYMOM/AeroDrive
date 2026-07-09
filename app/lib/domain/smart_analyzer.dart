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

  Future<Map<String, String>?> _geocodeLocation(String fileId, double lat, double lng) async {
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
        return {'locality': cityName, 'country': countryName};
      }
    } catch (e) {
      AppLogger.error('SmartAnalyzer: Failed to geocode location', e);
    }
    return null;
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

  Future<AnalysisResult> analyzeImageForUpload(File imageFile, String fileId) async {
    DateTime? photoTakenAt;
    double? latitude;
    double? longitude;
    List<String> tags = [];
    List<Map<String, dynamic>> faces = [];
    String? locality;
    String? country;

    try {
      // 1. EXIF Date and GPS extraction
      try {
        final fileBytes = await imageFile.readAsBytes();
        final exifTags = await readExifFromBytes(fileBytes);
        
        final dateTag = exifTags['Image DateTime'] ?? exifTags['EXIF DateTimeOriginal'];
        if (dateTag != null) {
          try {
            final str = dateTag.toString();
            final parts = str.split(' ');
            final datePart = parts[0].replaceAll(':', '-');
            photoTakenAt = DateTime.parse('$datePart ${parts[1]}');
          } catch (_) {}
        }

        final latTag = exifTags['GPS GPSLatitude'];
        final latRef = exifTags['GPS GPSLatitudeRef'];
        final longTag = exifTags['GPS GPSLongitude'];
        final longRef = exifTags['GPS GPSLongitudeRef'];

        if (latTag != null && latRef != null && longTag != null && longRef != null) {
          try {
            latitude = _convertExifGps(latTag, latRef.toString());
            longitude = _convertExifGps(longTag, longRef.toString());
          } catch (_) {}
        }
      } catch (e) {
        AppLogger.error('SmartAnalyzer: Failed to parse EXIF', e);
      }

      if (photoTakenAt != null) {
        await (_db.update(_db.files)..where((f) => f.id.equals(fileId))).write(
          FilesCompanion(photoTakenAt: drift.Value(photoTakenAt))
        );
      }

      if (latitude != null && longitude != null) {
        final geocodeResult = await _geocodeLocation(fileId, latitude, longitude);
        if (geocodeResult != null) {
          locality = geocodeResult['locality'];
          country = geocodeResult['country'];
        }
      }

      // 2. Machine Learning labels and face detection
      final isDesktop = kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS;
      List<Rect> faceRects = [];

      if (isDesktop) {
        tags = ['Nature', 'Sky', 'Outdoor', 'Pet'];
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
        tags = mlLabels.map((l) => l.label).toList();
        labeler.close();

        final faceDetector = FaceDetector(options: FaceDetectorOptions());
        final facesList = await faceDetector.processImage(inputImage);
        faceRects = facesList.map((f) => f.boundingBox).toList();
        faceDetector.close();
      }

      await _storeLabels(tags, fileId);
      
      if (faceRects.isNotEmpty) {
        faces = await _processAndStoreFacesForUpload(imageFile, faceRects, fileId);
      }
    } catch (e) {
      AppLogger.error('SmartAnalyzer analyzeImageForUpload failed', e);
    }

    return AnalysisResult(
      photoTakenAt: photoTakenAt,
      latitude: latitude,
      longitude: longitude,
      locality: locality,
      country: country,
      tags: tags,
      faces: faces,
    );
  }

  Future<List<Map<String, dynamic>>> _processAndStoreFacesForUpload(File imageFile, List<Rect> faceRects, String fileId) async {
    final List<Map<String, dynamic>> facesResult = [];
    img.Image? decodedImage;

    try {
      decodedImage = await img.decodeImageFile(imageFile.path);
    } catch (_) {}

    final double wOrig = decodedImage?.width.toDouble() ?? 1.0;
    final double hOrig = decodedImage?.height.toDouble() ?? 1.0;

    for (final rect in faceRects) {
      final clusterId = _uuid.v4();
      await _db.into(_db.faceClusters).insert(
        FaceClustersCompanion.insert(
          id: clusterId,
        )
      );

      final double normLeft = rect.left / wOrig;
      final double normTop = rect.top / hOrig;
      final double normWidth = rect.width / wOrig;
      final double normHeight = rect.height / hOrig;

      final mappingId = _uuid.v4();
      await _db.into(_db.photoFaces).insert(
        PhotoFacesCompanion.insert(
          id: mappingId,
          fileId: fileId,
          faceClusterId: clusterId,
          boxLeft: drift.Value(normLeft),
          boxTop: drift.Value(normTop),
          boxWidth: drift.Value(normWidth),
          boxHeight: drift.Value(normHeight),
        )
      );

      facesResult.add({
        'c': clusterId,
        'l': normLeft,
        't': normTop,
        'w': normWidth,
        'h': normHeight,
      });

      // Crop and save face to cache for UI
      try {
        if (decodedImage != null) {
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
        AppLogger.error('Failed to crop face', e);
      }
    }
    return facesResult;
  }

  Future<void> _processAndStoreFaces(File imageFile, List<Rect> faceRects, String fileId) async {
    img.Image? decodedImage;

    try {
      decodedImage = await img.decodeImageFile(imageFile.path);
    } catch (_) {}

    final double wOrig = decodedImage?.width.toDouble() ?? 1.0;
    final double hOrig = decodedImage?.height.toDouble() ?? 1.0;

    for (final rect in faceRects) {
      // Create a mock cluster for each face
      final clusterId = _uuid.v4();
      await _db.into(_db.faceClusters).insert(
        FaceClustersCompanion.insert(
          id: clusterId,
        )
      );

      final double normLeft = rect.left / wOrig;
      final double normTop = rect.top / hOrig;
      final double normWidth = rect.width / wOrig;
      final double normHeight = rect.height / hOrig;

      // Link to file
      final mappingId = _uuid.v4();
      await _db.into(_db.photoFaces).insert(
        PhotoFacesCompanion.insert(
          id: mappingId,
          fileId: fileId,
          faceClusterId: clusterId,
          boxLeft: drift.Value(normLeft),
          boxTop: drift.Value(normTop),
          boxWidth: drift.Value(normWidth),
          boxHeight: drift.Value(normHeight),
        )
      );

      // Crop and save face to cache for UI
      try {
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

  Future<void> syncMetadataFromManifest(Map<String, dynamic> manifest, String fileId) async {
    // 1. Lat/Lng and Location geocoding
    final double? lat = manifest['lat'] as double?;
    final double? lng = manifest['lng'] as double?;
    final String? locality = manifest['loc'] as String?;
    final String? country = manifest['cnt'] as String?;

    if (locality != null && country != null) {
      try {
        var place = await (_db.select(_db.places)
          ..where((p) => p.locality.equals(locality) & p.country.equals(country))
        ).getSingleOrNull();

        if (place == null) {
          final placeId = _uuid.v4();
          await _db.into(_db.places).insert(
            PlacesCompanion.insert(
              id: placeId,
              locality: drift.Value(locality),
              country: drift.Value(country),
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
        AppLogger.info('SmartAnalyzer: Linked synced file $fileId to place $locality, $country');
      } catch (e) {
        AppLogger.error('Failed to link synced place for $fileId', e);
      }
    }

    // 2. ML tags sync
    final tagsRaw = manifest['tags'];
    if (tagsRaw is List) {
      try {
        final tagsList = tagsRaw.map((e) => e.toString()).toList();
        await _storeLabels(tagsList, fileId);
      } catch (e) {
        AppLogger.error('Failed to link synced tags for $fileId', e);
      }
    }

    // 3. Face clusters sync
    final facesRaw = manifest['faces'];
    if (facesRaw is List) {
      try {
        for (final faceObj in facesRaw) {
          if (faceObj is Map) {
            final clusterId = faceObj['c'] as String?;
            final double? left = double.tryParse(faceObj['l'].toString());
            final double? top = double.tryParse(faceObj['t'].toString());
            final double? width = double.tryParse(faceObj['w'].toString());
            final double? height = double.tryParse(faceObj['h'].toString());

            if (clusterId != null) {
              // Ensure cluster exists in local db
              var cluster = await (_db.select(_db.faceClusters)..where((fc) => fc.id.equals(clusterId))).getSingleOrNull();
              if (cluster == null) {
                await _db.into(_db.faceClusters).insert(
                  FaceClustersCompanion.insert(
                    id: clusterId,
                  )
                );
              }

              // Store mapping with bounding box coords
              final mappingId = _uuid.v4();
              await _db.into(_db.photoFaces).insert(
                PhotoFacesCompanion.insert(
                  id: mappingId,
                  fileId: fileId,
                  faceClusterId: clusterId,
                  boxLeft: drift.Value(left),
                  boxTop: drift.Value(top),
                  boxWidth: drift.Value(width),
                  boxHeight: drift.Value(height),
                ),
                mode: drift.InsertMode.insertOrIgnore,
              );
            }
          }
        }
      } catch (e) {
        AppLogger.error('Failed to link synced faces for $fileId', e);
      }
    }
  }
}

class AnalysisResult {
  final DateTime? photoTakenAt;
  final double? latitude;
  final double? longitude;
  final String? locality;
  final String? country;
  final List<String> tags;
  final List<Map<String, dynamic>> faces;

  AnalysisResult({
    this.photoTakenAt,
    this.latitude,
    this.longitude,
    this.locality,
    this.country,
    required this.tags,
    required this.faces,
  });
}
