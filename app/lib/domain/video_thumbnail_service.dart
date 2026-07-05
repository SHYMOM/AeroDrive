import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:image/image.dart' as img;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/logger.dart';

class VideoThumbnailResult {
  final String? path;
  final Duration? duration;
  VideoThumbnailResult({this.path, this.duration});
}

class VideoThumbnailService {
  
  /// Extracts multiple frames, uses ML to score them, and returns the path to the best frame and the duration.
  Future<VideoThumbnailResult> generateSmartThumbnail(String videoPath) async {
    Player? player;
    VideoController? controller;
    final List<File> tempFrames = [];
    Duration? detectedDuration;
    
    try {
      player = Player();
      controller = VideoController(player);
      
      await player.open(Media(videoPath), play: false);
      
      // Wait for duration to be known
      Duration duration = Duration.zero;
      for (var i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 200));
        duration = player.state.duration;
        if (duration.inSeconds > 0) break;
      }
      
      if (duration.inSeconds == 0) {
        AppLogger.warning('VideoThumbnailService: Could not determine video duration.');
        return VideoThumbnailResult(); // Fallback to no thumbnail or standard extraction
      }

      detectedDuration = duration;

      final cacheDir = await getTemporaryDirectory();
      final uuid = const Uuid().v4();

      // Extract frames at 20%, 50%, 80%
      final fractions = [0.2, 0.5, 0.8];
      for (var i = 0; i < fractions.length; i++) {
        final seekPos = Duration(milliseconds: (duration.inMilliseconds * fractions[i]).toInt());
        await player.seek(seekPos);
        await Future.delayed(const Duration(milliseconds: 500)); // Wait for frame to render
        
        final Uint8List? bytes = await player.screenshot();
        if (bytes != null && bytes.isNotEmpty) {
          final file = File('${cacheDir.path}/frame_${uuid}_$i.jpg');
          await file.writeAsBytes(bytes);
          tempFrames.add(file);
        }
      }

      if (tempFrames.isEmpty) {
        AppLogger.warning('VideoThumbnailService: Failed to extract any frames.');
        return VideoThumbnailResult(duration: detectedDuration);
      }

      // Analyze frames with ML Kit
      final labelerOptions = ImageLabelerOptions(confidenceThreshold: 0.6);
      final imageLabeler = ImageLabeler(options: labelerOptions);
      
      File? bestFrame;
      double highestScore = -1;

      for (final frame in tempFrames) {
        final inputImage = InputImage.fromFile(frame);
        final labels = await imageLabeler.processImage(inputImage);
        
        // Score = Sum of confidences (favors frames with more recognized distinct objects)
        double score = 0;
        for (final label in labels) {
          score += label.confidence;
        }

        if (score > highestScore) {
          highestScore = score;
          bestFrame = frame;
        }
      }
      
      imageLabeler.close();
      
      if (bestFrame != null) {
        // Resize and compress the best frame to act as a lightweight thumbnail
        final imageBytes = await bestFrame.readAsBytes();
        final decodedImage = img.decodeImage(imageBytes);
        if (decodedImage != null) {
          final resized = img.copyResize(decodedImage, width: 512); // Maintain aspect ratio
          final compressedBytes = img.encodeJpg(resized, quality: 70);
          
          final finalThumb = File('${cacheDir.path}/thumb_$uuid.jpg');
          await finalThumb.writeAsBytes(compressedBytes);
          
          // Cleanup raw frames
          for (final f in tempFrames) {
            if (await f.exists()) await f.delete();
          }
          
          return VideoThumbnailResult(path: finalThumb.path, duration: detectedDuration);
        }
      }

    } catch (e) {
      AppLogger.error('VideoThumbnailService: Error generating thumbnail', e);
    } finally {
      player?.dispose();
    }
    
    return VideoThumbnailResult(duration: detectedDuration);
  }
}

final videoThumbnailServiceProvider = Provider<VideoThumbnailService>((ref) => VideoThumbnailService());
