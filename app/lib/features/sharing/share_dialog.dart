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
    final cs = Theme.of(context).colorScheme;
    final link = _shareLink ?? '';
    final name = widget.file?.name ?? widget.folder?.name ?? '';

    return AlertDialog(
      backgroundColor: cs.surfaceContainerHighest,
      title: Text(widget.folder != null ? 'Share Folder' : 'Share File', style: TextStyle(color: cs.onSurface)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sharing: $name', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
            const SizedBox(height: 16),

            if (_error != null)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: cs.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
              ),

            if (_isLoading)
              const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ))
            else if (_shareLink == null) ...[
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('Password protect', style: TextStyle(fontSize: 14, color: cs.onSurface)),
                subtitle: _hasPassword ? null : Text('Require a password to access', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                value: _hasPassword,
                onChanged: (v) => setState(() => _hasPassword = v),
              ),
              if (_hasPassword)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: _passwordController,
                    obscureText: true,
                    style: TextStyle(color: cs.onSurface),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      labelStyle: TextStyle(color: cs.onSurfaceVariant),
                      hintText: 'Enter a share password',
                      hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'This generates a zero-knowledge deep link. Recipients need AeroDrive installed.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
              ),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        link,
                        style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: cs.onSurface),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.copy, color: cs.primary),
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
          child: Text('Close', style: TextStyle(color: cs.onSurfaceVariant)),
        ),
        if (_shareLink == null && !_isLoading)
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cs.primary),
            onPressed: _generateLink,
            child: const Text('Generate Link'),
          ),
        if (_shareLink != null)
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cs.primary),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
            child: const Text('Copy Link'),
          ),
      ],
    );
  }
}
