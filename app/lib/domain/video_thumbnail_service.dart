import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/logger.dart';

class VideoThumbnailResult {
  VideoThumbnailResult({this.path, this.duration});
  final String? path;
  final Duration? duration;
}

class VideoThumbnailService {
  final _thumbnailPlugin = FcNativeVideoThumbnail();

  /// Generates a representative video thumbnail by extracting a frame from a
  /// dynamic offset (avoiding pitch black 0.0s intro frames) and reads duration.
  Future<VideoThumbnailResult> generateSmartThumbnail(String videoPath) async {
    final duration = await _getDurationOnly(videoPath);
    String? thumbnailPath;

    try {
      final file = File(videoPath);
      if (await file.exists()) {
        thumbnailPath = await _extractRepresentativeFrame(videoPath, duration);
      } else {
        AppLogger.warning('VideoThumbnailService: File does not exist at $videoPath');
      }
    } catch (e, s) {
      AppLogger.warning('VideoThumbnailService: Failed to extract video thumbnail: $e\n$s');
    }

    return VideoThumbnailResult(
      path: thumbnailPath,
      duration: duration,
    );
  }

  /// Extracts a frame at a representative/random time offset (10% to 50% into the video)
  /// so users see meaningful content rather than a blank or fade-in intro frame.
  Future<String?> _extractRepresentativeFrame(String videoPath, Duration? duration) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final targetFile = File('${tempDir.path}${Platform.pathSeparator}vthumb_${const Uuid().v4()}.jpg');

      final totalSec = duration?.inSeconds ?? 0;
      FcVideoThumbnailTime? atTime;

      if (totalSec > 2) {
        // Pick a frame between 10% and 50% of the video duration (up to 30s)
        final minSec = (totalSec * 0.1).clamp(1, 5).toInt();
        final maxSec = (totalSec * 0.5).clamp(minSec + 1, 30).toInt();
        final range = maxSec - minSec;
        final selectedSec = minSec + (range > 0 ? Random().nextInt(range) : 0);
        atTime = FcVideoThumbnailTime(selectedSec, FcVideoThumbnailTimeUnit.seconds);
        AppLogger.info('VideoThumbnailService: Seeking frame at ${selectedSec}s for video (duration: ${totalSec}s)');
      }

      bool generated = false;
      if (atTime != null) {
        try {
          generated = await _thumbnailPlugin.saveThumbnailToFile(
            srcFile: videoPath,
            destFile: targetFile.path,
            width: 320,
            height: 320,
            quality: 85,
            at: atTime,
          );
        } catch (seekErr) {
          AppLogger.warning('VideoThumbnailService: Seeking thumbnail failed ($seekErr), trying fallback');
        }
      }

      // If seeking failed or wasn't supported (e.g. Windows native reader), capture default keyframe
      if (!generated || !await targetFile.exists() || (await targetFile.length()) == 0) {
        generated = await _thumbnailPlugin.saveThumbnailToFile(
          srcFile: videoPath,
          destFile: targetFile.path,
          width: 320,
          height: 320,
          quality: 85,
        );
      }

      if (generated && await targetFile.exists() && (await targetFile.length()) > 0) {
        AppLogger.info('VideoThumbnailService: Successfully generated thumbnail (${await targetFile.length()} bytes) at ${targetFile.path}');
        return targetFile.path;
      }
    } catch (e) {
      AppLogger.warning('VideoThumbnailService: Frame extraction failed: $e');
    }
    return null;
  }

  Future<Duration?> _getDurationOnly(String videoPath) async {
    try {
      final player = Player();
      try {
        await player.open(Media(videoPath), play: false);
        for (var i = 0; i < 20; i++) {
          await Future.delayed(const Duration(milliseconds: 200));
          final d = player.state.duration;
          if (d.inSeconds > 0) return d;
        }
      } finally {
        unawaited(player.dispose());
      }
    } catch (e) {
      AppLogger.warning('VideoThumbnailService: Could not read duration: $e');
    }
    return null;
  }
}

final videoThumbnailServiceProvider = Provider<VideoThumbnailService>((ref) => VideoThumbnailService());
