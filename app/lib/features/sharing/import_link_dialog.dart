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
                icon: Icon(Icons.folder_open, size: 16, color: AppColors.primary),
                label: Text(
                  _targetFolderName,
                  style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.bold),
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

            // Show a progress indicator while initializing and fetching metadata
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
                          'Measuring internet speed and fetching metadata...',
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
                onConfirm: (totalSize, speedBytesPerSec) async {
                  // Hide the loading dialog first
                  if (context.mounted) {
                    Navigator.of(context, rootNavigator: true).pop(); // dismiss loading
                  }

                  final sizeStr = _formatBytes(totalSize);
                  final double speedMb = speedBytesPerSec / (1024 * 1024);
                  final speedStr = '${speedMb.toStringAsFixed(1)} MB/s';
                  
                  // estimated duration in seconds (double size because we download + upload!)
                  final double totalTransferred = totalSize.toDouble() * 2;
                  final double durationSec = speedBytesPerSec > 0 ? totalTransferred / speedBytesPerSec : 0;
                  final int durationMin = (durationSec / 60).ceil();
                  final durationStr = '$durationMin minute${durationMin == 1 ? "" : "s"}';

                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: AppColors.surfaceElevated,
                      title: const Text('Confirm Import', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Importing this shared item will download and re-encrypt the data to your storage channel.',
                            style: TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                          _buildDetailRow('Total Size:', sizeStr),
                          _buildDetailRow('Internet Data Cost:', '${_formatBytes(totalSize * 2)} (Download + Upload)'),
                          _buildDetailRow('Measured Speed:', speedStr),
                          _buildDetailRow('Estimated Time:', durationStr),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text('Proceed', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );

                  // Show the loading dialog again if confirmed
                  if (confirmed == true && context.mounted) {
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
                                  'Importing share and copying chunks...',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return confirmed ?? false;
                },
              );
              
              if (context.mounted) {
                // If loading dialog is still showing, dismiss it
                Navigator.of(context, rootNavigator: true).pop(); // dismiss loading dialog
                ref.invalidate(folderContentsProvider);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Successfully imported shared items.')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                // If loading dialog is still showing, dismiss it
                try {
                  Navigator.of(context, rootNavigator: true).pop(); // dismiss loading dialog
                } catch (_) {}
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.surfaceElevated,
                    title: const Text('Import Failed', style: TextStyle(color: Colors.white)),
                    content: Text(e.toString(), style: const TextStyle(color: Colors.white70)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('OK', style: TextStyle(color: AppColors.primary)),
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
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))),
        ],
      ),
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
          child: Text('Decrypt', style: TextStyle(color: AppColors.primary)),
        ),
      ],
    );
  }
}
