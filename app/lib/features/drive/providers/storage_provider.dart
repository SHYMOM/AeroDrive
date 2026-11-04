import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import 'drive_providers.dart';

enum StorageCategoryType {
  images,
  videos,
  audio,
  documents,
  others,
}

class StorageCategoryItem {
  const StorageCategoryItem({
    required this.type,
    required this.label,
    required this.bytes,
    required this.count,
    required this.color,
  });

  final StorageCategoryType type;
  final String label;
  final int bytes;
  final int count;
  final Color color;

  double fractionOf(int total) => total > 0 ? (bytes / total).clamp(0.0, 1.0) : 0.0;
}

class StorageBreakdown {
  const StorageBreakdown({
    required this.totalBytes,
    required this.totalFiles,
    required this.categories,
  });

  final int totalBytes;
  final int totalFiles;
  final Map<StorageCategoryType, StorageCategoryItem> categories;

  List<StorageCategoryItem> get activeCategories =>
      categories.values.where((c) => c.bytes > 0).toList();
}

String formatStorageBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const kb = 1024;
  const mb = 1024 * kb;
  const gb = 1024 * mb;
  const tb = 1024 * gb;

  if (bytes >= tb) {
    return '${(bytes / tb).toStringAsFixed(2)} TB';
  } else if (bytes >= gb) {
    return '${(bytes / gb).toStringAsFixed(2)} GB';
  } else if (bytes >= mb) {
    return '${(bytes / mb).toStringAsFixed(1)} MB';
  } else if (bytes >= kb) {
    return '${(bytes / kb).toStringAsFixed(1)} KB';
  } else {
    return '$bytes B';
  }
}

StorageCategoryType categorizeFile({required String name, String? mimeType}) {
  final mime = (mimeType ?? '').toLowerCase().trim();
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';

  // 1. Images
  if (mime.startsWith('image/') ||
      {'jpg', 'jpeg', 'png', 'gif', 'webp', 'svg', 'bmp', 'heic', 'heif', 'ico', 'tiff', 'raw'}.contains(ext)) {
    return StorageCategoryType.images;
  }

  // 2. Videos
  if (mime.startsWith('video/') ||
      {'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', '3gp', 'ts'}.contains(ext)) {
    return StorageCategoryType.videos;
  }

  // 3. Audio
  if (mime.startsWith('audio/') ||
      {'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'wma', 'opus', 'alac'}.contains(ext)) {
    return StorageCategoryType.audio;
  }

  // 4. Documents
  if (mime.contains('pdf') ||
      mime.startsWith('text/') ||
      mime.contains('document') ||
      mime.contains('msword') ||
      mime.contains('sheet') ||
      mime.contains('excel') ||
      mime.contains('presentation') ||
      mime.contains('powerpoint') ||
      mime.contains('word') ||
      {'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv', 'md', 'rtf', 'epub', 'log'}.contains(ext)) {
    return StorageCategoryType.documents;
  }

  // 5. Others
  return StorageCategoryType.others;
}

final storageBreakdownProvider = StreamProvider.autoDispose<StorageBreakdown>((ref) {
  final db = ref.watch(databaseProvider);
  ref.watch(dbRebuildVersionProvider);

  return (db.select(db.files)..where((f) => f.deletedAt.isNull()))
      .watch()
      .map((files) {
        var imageBytes = 0;
        var videoBytes = 0;
        var audioBytes = 0;
        var docBytes = 0;
        var otherBytes = 0;
        var imageCount = 0;
        var videoCount = 0;
        var audioCount = 0;
        var docCount = 0;
        var otherCount = 0;
        var totalBytes = 0;

        for (final file in files) {
          final size = file.size ?? 0;
          totalBytes += size;
          final cat = categorizeFile(name: file.name, mimeType: file.mimeType);

          switch (cat) {
            case StorageCategoryType.images:
              imageBytes += size;
              imageCount++;
            case StorageCategoryType.videos:
              videoBytes += size;
              videoCount++;
            case StorageCategoryType.audio:
              audioBytes += size;
              audioCount++;
            case StorageCategoryType.documents:
              docBytes += size;
              docCount++;
            case StorageCategoryType.others:
              otherBytes += size;
              otherCount++;
          }
        }

        return StorageBreakdown(
          totalBytes: totalBytes,
          totalFiles: files.length,
          categories: {
            StorageCategoryType.images: StorageCategoryItem(
              type: StorageCategoryType.images,
              label: 'Images',
              bytes: imageBytes,
              count: imageCount,
              color: AppColors.fileImage,
            ),
            StorageCategoryType.videos: StorageCategoryItem(
              type: StorageCategoryType.videos,
              label: 'Videos',
              bytes: videoBytes,
              count: videoCount,
              color: AppColors.fileVideo,
            ),
            StorageCategoryType.audio: StorageCategoryItem(
              type: StorageCategoryType.audio,
              label: 'Audio',
              bytes: audioBytes,
              count: audioCount,
              color: AppColors.fileAudio,
            ),
            StorageCategoryType.documents: StorageCategoryItem(
              type: StorageCategoryType.documents,
              label: 'Documents',
              bytes: docBytes,
              count: docCount,
              color: AppColors.fileDocument,
            ),
            StorageCategoryType.others: StorageCategoryItem(
              type: StorageCategoryType.others,
              label: 'Others',
              bytes: otherBytes,
              count: otherCount,
              color: AppColors.fileUnknown,
            ),
          },
        );
      });
});
