import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../data/db/database.dart';
import 'share_service.dart';

class ShareDialog extends ConsumerStatefulWidget {
  const ShareDialog({super.key, this.file, this.folder});
  final FileData? file;
  final FolderData? folder;

  @override
  ConsumerState<ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends ConsumerState<ShareDialog> {
  bool _isLoading = false;
  String? _shareLink;
  String? _error;

  // Options
  final _passwordController = TextEditingController();
  bool _hasPassword = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _generateLink() async {
    setState(() { _isLoading = true; _error = null; });

    try {
      final link = await ref.read(shareServiceProvider).generateShareLink(
        file: widget.file,
        folder: widget.folder,
        password: _hasPassword ? _passwordController.text : null,
      );
      if (mounted) setState(() { _shareLink = link; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = _shareLink ?? '';
    final name = widget.file?.name ?? widget.folder?.name ?? '';

    return AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      title: Text(widget.folder != null ? 'Share Folder' : 'Share File', style: const TextStyle(color: Colors.white)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sharing: $name', style: const TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 16),

            if (_error != null)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ),

            if (_isLoading)
              const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ))
            else if (_shareLink == null) ...[
              // Options
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Password protect', style: TextStyle(fontSize: 14, color: Colors.white)),
                subtitle: _hasPassword ? null : const Text('Require a password to access', style: TextStyle(fontSize: 12, color: Colors.white54)),
                value: _hasPassword,
                onChanged: (v) => setState(() => _hasPassword = v),
              ),
              if (_hasPassword)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: _passwordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      labelStyle: TextStyle(color: Colors.white70),
                      hintText: 'Enter a share password',
                      hintStyle: TextStyle(color: Colors.white30),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'This generates a zero-knowledge deep link. Recipients need AeroDrive installed.',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
              ),
            ] else ...[
              // Share link display
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        link,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, color: AppColors.primary),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: link));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied to clipboard')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close', style: TextStyle(color: Colors.white54)),
        ),
        if (_shareLink == null && !_isLoading)
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: _generateLink,
            child: const Text('Generate Link', style: TextStyle(color: Colors.black)),
          ),
        if (_shareLink != null)
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
            child: const Text('Copy Link', style: TextStyle(color: Colors.black)),
          ),
      ],
    );
  }
}
