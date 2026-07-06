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
      title: Text('Import Link', style: TextStyle(color: AppColors.onSurface)),
      content: TextField(
        controller: controller,
        style: TextStyle(color: AppColors.onSurface),
        decoration: InputDecoration(
          hintText: 'aerodrive://share?...',
          hintStyle: TextStyle(color: AppColors.onSurfaceVariant),
          filled: true,
          fillColor: AppColors.surfaceVariant,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: () async {
            final url = controller.text.trim();
            if (url.isEmpty) {
              Navigator.pop(context);
              return;
            }

            Navigator.pop(context);

            final uri = Uri.parse(url);
            final hasPassword = uri.queryParameters['hasPassword'] == '1';

            String? password;
            if (hasPassword) {
              password = await showDialog<String>(
                context: context,
                builder: (ctx) => const _SharePasswordPromptDialog(),
              );
              if (password == null) return; // User cancelled
            }

            // Show a progress indicator while importing
            if (!context.mounted) return;
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => PopScope(
                canPop: false,
                child: AlertDialog(
                  backgroundColor: AppColors.surfaceElevated,
                  content: const Row(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 20),
                      Expanded(
                        child: Text(
                          'Importing share and mapping keys...',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );

            try {
              await ref.read(shareServiceProvider).importShareLink(url, password: password);
              
              if (context.mounted) {
                Navigator.of(context, rootNavigator: true).pop(); // dismiss loading dialog
                ref.invalidate(folderContentsProvider);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Successfully imported shared items.')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                Navigator.of(context, rootNavigator: true).pop(); // dismiss loading dialog
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.surfaceElevated,
                    title: const Text('Import Failed', style: TextStyle(color: Colors.white)),
                    content: Text(e.toString(), style: const TextStyle(color: Colors.white70)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('OK', style: TextStyle(color: AppColors.primary)),
                      )
                    ],
                  ),
                );
              }
            }
          },
          child: const Text('Import', style: TextStyle(color: Colors.black)),
        ),
      ],
    );
  }
}

class _SharePasswordPromptDialog extends StatefulWidget {
  const _SharePasswordPromptDialog();

  @override
  State<_SharePasswordPromptDialog> createState() => _SharePasswordPromptDialogState();
}

class _SharePasswordPromptDialogState extends State<_SharePasswordPromptDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      title: const Text('Enter Password', style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: _controller,
        obscureText: true,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: 'Share Password',
          hintStyle: TextStyle(color: Colors.white30),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Decrypt', style: TextStyle(color: AppColors.primary)),
        ),
      ],
    );
  }
}
