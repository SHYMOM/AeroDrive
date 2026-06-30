import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../drive/providers/drive_providers.dart';
import 'share_service.dart';

class ImportLinkDialog extends ConsumerWidget {
  const ImportLinkDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    return AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      title: const Text('Import Link', style: TextStyle(color: AppColors.onSurface)),
      content: TextField(
        controller: controller,
        style: const TextStyle(color: AppColors.onSurface),
        decoration: InputDecoration(
          hintText: 'aerodrive://share?...',
          hintStyle: const TextStyle(color: AppColors.onSurfaceVariant),
          filled: true,
          fillColor: AppColors.surfaceVariant,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: () async {
            Navigator.pop(context);
            if (controller.text.trim().isNotEmpty) {
              await ref.read(shareServiceProvider).importShareLink(controller.text.trim());
              ref.invalidate(folderContentsProvider);
            }
          },
          child: const Text('Import', style: TextStyle(color: Colors.black)),
        ),
      ],
    );
  }
}
