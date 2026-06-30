import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/core/theme/app_colors.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/features/media/media_screen.dart';
import 'package:aerodrive/features/gallery/thumbnail_service.dart';
import 'package:aerodrive/features/preview/preview_router.dart';
import 'package:intl/intl.dart';
import 'dart:io';

class MemoriesScreen extends ConsumerWidget {
  const MemoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaFilesAsync = ref.watch(allMediaFilesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Memories',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.0, -0.3),
            radius: 1.8,
            colors: [
              const Color(0xFF7C3AED).withValues(alpha: 0.15),
              const Color(0xFF00E5FF).withValues(alpha: 0.05),
              AppColors.background,
              AppColors.background,
            ],
          ),
        ),
        child: mediaFilesAsync.when(
          data: (files) {
            if (files.isEmpty) {
              return const Center(
                child: Text('No memories found.', style: TextStyle(color: Colors.white54)),
              );
            }

            final olderFiles = files.reversed.toList(); // oldest first

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: olderFiles.length.clamp(0, 15),
              itemBuilder: (context, index) {
                final file = olderFiles[index];
                final dateStr = file.createdAt != null
                    ? DateFormat('MMMM d, yyyy').format(file.createdAt!)
                    : 'Some time ago';
                
                final int yearsAgo = DateTime.now().year - (file.createdAt?.year ?? DateTime.now().year);
                final String memoryTitle = yearsAgo > 0 
                    ? '$yearsAgo years ago today'
                    : 'Relive this moment';

                return GestureDetector(
                  onTap: () => PreviewRouter.openPreview(context, file),
                  child: Container(
                    height: 200,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _MemoryCover(file: file),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 20,
                          left: 20,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                memoryTitle,
                                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                dateStr,
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.white))),
        ),
      ),
    );
  }
}

class _MemoryCover extends ConsumerWidget {
  final FileData file;
  const _MemoryCover({required this.file});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<File?>(
      future: ref.read(thumbnailServiceProvider).getThumbnail(file),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.file(snapshot.data!, fit: BoxFit.cover);
        }
        return Container(color: Colors.white.withValues(alpha: 0.05));
      },
    );
  }
}
