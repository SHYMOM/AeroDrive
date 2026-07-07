import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../drive/providers/drive_providers.dart';
import '../drive/widgets/folder_picker_dialog.dart';
import 'share_service.dart';

class ImportLinkDialog extends ConsumerStatefulWidget {
  const ImportLinkDialog({super.key});

  @override
  ConsumerState<ImportLinkDialog> createState() => _ImportLinkDialogState();
}

class _ImportLinkDialogState extends ConsumerState<ImportLinkDialog> {
  final _controller = TextEditingController();
  String? _targetFolderId;
  String _targetFolderName = 'My Drive';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _resolveFolderName(String folderId) async {
    final db = ref.read(databaseProvider);
    final folder = await (db.select(db.folders)..where((f) => f.id.equals(folderId))).getSingleOrNull();
    if (folder != null && mounted) {
      setState(() {
        _targetFolderName = folder.name;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      title: Text('Import Link', style: TextStyle(color: AppColors.onSurface)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            style: TextStyle(color: AppColors.onSurface),
            decoration: InputDecoration(
              hintText: 'aerodrive://share?...',
              hintStyle: TextStyle(color: AppColors.onSurfaceVariant),
              filled: true,
              fillColor: AppColors.surfaceVariant,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Import to:',
                style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13),
              ),
              TextButton.icon(
                icon: const Icon(Icons.folder_open, size: 16, color: AppColors.primary),
                label: Text(
                  _targetFolderName,
                  style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                onPressed: () async {
                  final pickedId = await showDialog<String>(
                    context: context,
                    builder: (ctx) => const FolderPickerDialog(
                      title: 'Select Destination Folder',
                    ),
                  );
                  if (pickedId != null) {
                    setState(() {
                      if (pickedId == '__root__') {
                        _targetFolderId = null;
                        _targetFolderName = 'My Drive';
                      } else {
                        _targetFolderId = pickedId;
                        _resolveFolderName(pickedId);
                      }
                    });
                  }
                },
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: () async {
            final url = _controller.text.trim();
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
              await ref.read(shareServiceProvider).importShareLink(
                url,
                password: password,
                targetFolderId: _targetFolderId,
              );
              
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
