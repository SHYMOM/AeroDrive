import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../core/logger.dart';

class VideoThumbnailResult {
  final String? path;
  final Duration? duration;
  VideoThumbnailResult({this.path, this.duration});
}

class VideoThumbnailService {

  /// Opens the video just to read its duration — no display surface needed.
  /// This is safe on ALL platforms (Android, Windows, Linux, Mac).
  /// Screenshot extraction is intentionally skipped here because media_kit's
  /// [Player.screenshot] requires a [Video] widget display surface on mobile.
  /// Calling it headless causes a native crash on Android. Video thumbnails
  /// will be implemented in a future phase with a proper display surface.
  Future<VideoThumbnailResult> generateSmartThumbnail(String videoPath) async {
    final duration = await _getDurationOnly(videoPath);
    return VideoThumbnailResult(duration: duration);
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
        player.dispose();
      }
    } catch (e) {
      AppLogger.warning('VideoThumbnailService: Could not read duration: $e');
    }
    return null;
  }
}

final videoThumbnailServiceProvider = Provider<VideoThumbnailService>((ref) => VideoThumbnailService());
