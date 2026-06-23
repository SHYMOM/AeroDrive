import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;
import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/core/logger.dart';
import 'package:aerodrive/features/gallery/thumbnail_service.dart';
import 'package:aerodrive/features/tags/tag_service.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

class MLService {
  final Ref _ref;

  MLService(this._ref);

  Future<void> processImage(FileData file) async {
    // Only process images
    if (file.mimeType == null || !file.mimeType!.startsWith('image/')) return;

    // Gracefully skip on unsupported platforms
    if (!Platform.isAndroid && !Platform.isIOS) {
      AppLogger.info('ML Kit skipped: Not on Android/iOS');
      return;
    }

    try {
      // 1. Get the local decrypted thumbnail (acts as our base image for ML)
      final thumbnailFile = await _ref.read(thumbnailServiceProvider).getThumbnail(file);
      if (thumbnailFile == null) return;

      // 2. Initialize ML Kit
      final inputImage = InputImage.fromFile(thumbnailFile);
      final ImageLabelerOptions options = ImageLabelerOptions(confidenceThreshold: 0.7);
      final imageLabeler = ImageLabeler(options: options);

      // 3. Process
      final List<ImageLabel> labels = await imageLabeler.processImage(inputImage);

      // 4. Clean up
      imageLabeler.close();

      // 5. Save to Database using TagService
      final tagService = _ref.read(tagServiceProvider);
      
      for (final label in labels) {
        final tagName = label.label.toLowerCase();
        
        final tag = await tagService.getOrCreateTag(tagName);
        await tagService.attachTagToFile(file.id, tag.id);
      }
      
      AppLogger.info('Successfully labeled ${file.name} with ${labels.length} tags.');

    } catch (e) {
      AppLogger.error('Failed to run ML Labeler', e);
    }
  }
}

final mlServiceProvider = Provider<MLService>((ref) {
  return MLService(ref);
});
