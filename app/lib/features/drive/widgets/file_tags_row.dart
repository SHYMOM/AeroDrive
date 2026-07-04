import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tags/tag_providers.dart';

class FileTagsRow extends ConsumerWidget {
  const FileTagsRow({super.key, required this.fileId});
  final String fileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(fileTagsStreamProvider(fileId));
    
    return tagsAsync.when(
      data: (tags) {
        if (tags.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: tags.map((tag) {
                Color color = Colors.grey;
                if (tag.color != null && tag.color!.length >= 7) {
                  try {
                    color = Color(int.parse(tag.color!.replaceFirst('#', '0xFF')));
                  } catch (_) {}
                }
                final contrastColor = color.computeLuminance() > 0.5 ? Colors.black : Colors.white;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      tag.name,
                      style: TextStyle(
                        color: contrastColor,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
