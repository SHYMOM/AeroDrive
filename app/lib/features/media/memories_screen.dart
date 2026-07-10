import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../data/db/database.dart';
import '../gallery/thumbnail_service.dart';
import '../preview/preview_router.dart';
import 'media_screen.dart';

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
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Memories',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.3),
            radius: 1.8,
            colors: [
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
              Theme.of(context).colorScheme.secondary.withValues(alpha: 0.05),
              AppColors.background,
              AppColors.background,
            ],
          ),
        ),
        child: mediaFilesAsync.when(
          data: (files) {
            if (files.isEmpty) {
              return Center(
                child: Text('No memories found.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                final memoryTitle = yearsAgo > 0 
                    ? '$yearsAgo years ago today'
                    : 'Relive this moment';

                return GestureDetector(
                  onTap: () => PreviewRouter.openPreview(context, file),
                  child: Container(
                    height: 200,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
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
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                dateStr,
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7), fontSize: 13),
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
          error: (err, stack) => Center(child: Text('Error: $err', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
        ),
      ),
    );
  }
}

class _MemoryCover extends ConsumerWidget {
  const _MemoryCover({required this.file});
  final FileData file;

  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder<File?>(
      future: ref.read(thumbnailServiceProvider).getThumbnail(file),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.file(snapshot.data!, fit: BoxFit.cover);
        }
        return Container(color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5));
      },
    );
}
