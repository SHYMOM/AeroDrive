import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../transfers/transfers_screen.dart';

class UploadQueueScreen extends ConsumerStatefulWidget {
  const UploadQueueScreen({super.key});

  @override
  ConsumerState<UploadQueueScreen> createState() => _UploadQueueScreenState();
}

class _UploadQueueScreenState extends ConsumerState<UploadQueueScreen> {
  String _formatSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _getTransferName(TransferItem item) {
    if (item.transfer.type == 'UPLOAD_FILE' && item.transfer.fileId != null) {
      final parts = item.transfer.fileId!.split('|');
      if (parts.isNotEmpty) {
        final path = parts[0];
        return path.split(RegExp(r'[\\/]')).last;
      }
    }
    return item.file?.name ?? item.transfer.fileId ?? 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    final transfersAsync = ref.watch(transfersStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Upload Queue')),
      body: transfersAsync.when(
        data: (items) {
          final uploads = items.where((i) => i.transfer.type == 'UPLOAD_FILE').toList();
          if (uploads.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_upload_outlined, size: 64, color: Colors.white24),
                  const SizedBox(height: 24),
                  Text(
                    'No uploads yet',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white54,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Files you upload will appear here',
                    style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: uploads.length,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemBuilder: (context, index) {
              final item = uploads[index];
              final name = _getTransferName(item);
              final status = item.transfer.status;
              final bytesTransferred = item.transfer.bytesTransferred;
              final totalBytes = item.transfer.totalBytes ?? 0;
              final progress = totalBytes > 0 ? (bytesTransferred / totalBytes).clamp(0.0, 1.0) : 0.0;

              Color statusColor;
              String statusText;
              switch (status) {
                case 'PROCESSING':
                  statusColor = Colors.blueAccent;
                  statusText = 'UPLOADING';
                case 'PENDING':
                  statusColor = Colors.orangeAccent;
                  statusText = 'QUEUED';
                case 'COMPLETED':
                  statusColor = Colors.green;
                  statusText = 'DONE';
                case 'FAILED':
                  statusColor = Colors.red;
                  statusText = 'FAILED';
                default:
                  statusColor = Colors.grey;
                  statusText = status ?? 'UNKNOWN';
              }

              return Card(
                color: AppColors.surfaceElevated,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppColors.outline, width: 0.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: AppColors.primaryLight.withValues(alpha: 0.1),
                            child: const Icon(Icons.cloud_upload, color: AppColors.primaryLight, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatSize(totalBytes),
                                  style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: statusColor.withValues(alpha: 0.5), width: 0.5),
                            ),
                            child: Text(
                              statusText,
                              style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      if (status == 'PROCESSING') ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.white10,
                            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                            minHeight: 4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${_formatSize(bytesTransferred)} of ${_formatSize(totalBytes)}',
                              style: const TextStyle(fontSize: 11, color: Colors.white54),
                            ),
                            Text(
                              '${(progress * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                      if (status == 'FAILED' && item.transfer.errorMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${item.transfer.errorMessage}',
                          style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ),
              ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.05, end: 0, curve: Curves.easeOut);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.redAccent))),
      ),
    );
  }
}
