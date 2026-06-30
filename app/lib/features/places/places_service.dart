import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:exif/exif.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/core/logger.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/features/gallery/thumbnail_service.dart';
import 'package:drift/drift.dart' as drift;

class PlaceLocation {
  final String name;
  final String admin;
  final String country;
  final double lat;
  final double lon;

  PlaceLocation({
    required this.name,
    required this.admin,
    required this.country,
    required this.lat,
    required this.lon,
  });

  factory PlaceLocation.fromJson(Map<String, dynamic> json) {
    return PlaceLocation(
      name: json['name'],
      admin: json['admin'],
      country: json['country'],
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
    );
  }
}

class PlacesService {
  final Ref _ref;
  List<PlaceLocation>? _cities;

  PlacesService(this._ref);

  Future<void> _loadCities() async {
    if (_cities != null) return;
    try {
      final jsonString = await rootBundle.loadString('assets/cities.json');
      final List<dynamic> jsonList = jsonDecode(jsonString);
      _cities = jsonList.map((e) => PlaceLocation.fromJson(e)).toList();
    } catch (e) {
      AppLogger.error('Failed to load cities.json', e);
      _cities = [];
    }
  }

  Future<void> processImageLocation(FileData file) async {
    if (file.mimeType == null || !file.mimeType!.startsWith('image/')) return;

    try {
      // 1. Get decrypted thumbnail
      final thumbnailFile = await _ref.read(thumbnailServiceProvider).getThumbnail(file);
      if (thumbnailFile == null) return;

      // 2. Read EXIF
      final bytes = await thumbnailFile.readAsBytes();
      final tags = await readExifFromBytes(bytes);
      
      if (tags.isEmpty || !tags.containsKey('GPS GPSLatitude')) {
        return;
      }

      // 3. Extract GPS
      final latValue = tags['GPS GPSLatitude']!.values.toList();
      final latRef = tags['GPS GPSLatitudeRef']?.printable;
      final lonValue = tags['GPS GPSLongitude']!.values.toList();
      final lonRef = tags['GPS GPSLongitudeRef']?.printable;

      if (latValue.length < 3 || lonValue.length < 3) return;

      double lat = _convertToDecimal(latValue);
      double lon = _convertToDecimal(lonValue);

      if (latRef == 'S') lat = -lat;
      if (lonRef == 'W') lon = -lon;

      AppLogger.info('Extracted GPS for ${file.name}: $lat, $lon');

      // 4. Offline Reverse Geocoding
      await _loadCities();
      if (_cities == null || _cities!.isEmpty) return;

      PlaceLocation? closestCity;
      double minDistance = double.infinity;

      for (final city in _cities!) {
        // Simple euclidean distance approximation for the mockup
        final dist = math.pow(city.lat - lat, 2) + math.pow(city.lon - lon, 2);
        if (dist < minDistance) {
          minDistance = dist.toDouble();
          closestCity = city;
        }
      }

      if (closestCity != null) {
        AppLogger.info('Closest city: ${closestCity.name}, ${closestCity.country}');
        
        final db = _ref.read(databaseProvider);
        final placeId = '${closestCity.name}_${closestCity.country}'.replaceAll(' ', '_').toLowerCase();

        // Save Place
        await db.into(db.places).insert(
          PlacesCompanion.insert(
            id: placeId,
            country: drift.Value(closestCity.country),
            adminArea: drift.Value(closestCity.admin),
            locality: drift.Value(closestCity.name),
          ),
          mode: drift.InsertMode.insertOrIgnore,
        );

        // Map File to Place
        await db.into(db.filePlaces).insert(
          FilePlacesCompanion.insert(
            fileId: file.id,
            placeId: placeId,
          ),
          mode: drift.InsertMode.insertOrIgnore,
        );
      }

    } catch (e, s) {
      AppLogger.error('Failed to process image location', e, s);
    }
  }

  double _convertToDecimal(List<dynamic> dms) {
    // Exif values are Ratio objects with numerator/denominator
    double getValue(dynamic val) {
      if (val is Ratio) {
        return val.numerator / val.denominator;
      }
      return val is int ? val.toDouble() : double.parse(val.toString());
    }

    double d = getValue(dms[0]);
    double m = getValue(dms[1]);
    double s = getValue(dms[2]);

    return d + (m / 60) + (s / 3600);
  }
}

final placesServiceProvider = Provider<PlacesService>((ref) {
  return PlacesService(ref);
});
