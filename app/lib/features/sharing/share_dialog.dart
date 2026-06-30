import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/features/sharing/share_service.dart';

class ShareDialog extends ConsumerStatefulWidget {
  final FileData file;
  const ShareDialog({super.key, required this.file});

  @override
  ConsumerState<ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends ConsumerState<ShareDialog> {
  bool _isLoading = false;
  ShareLinkData? _shareLink;
  String? _error;

  // Options
  final _passwordController = TextEditingController();
  bool _hasPassword = false;
  bool _burnAfterReading = false;
  int? _maxDownloads;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _generateLink() async {
    setState(() { _isLoading = true; _error = null; });

    try {
      final link = await ref.read(shareServiceProvider).generateShareLink(
        widget.file,
        password: _hasPassword ? _passwordController.text : null,
        burnAfterReading: _burnAfterReading,
        maxDownloads: _maxDownloads,
      );
      if (mounted) setState(() { _shareLink = link; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  String _buildShareUrl() {
    if (_shareLink == null) return '';
    final token = _shareLink!.token ?? '';
    return 'aerodrive://share?token=$token';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = _buildShareUrl();

    return AlertDialog(
      title: const Text('Share File'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sharing: ${widget.file.name}', style: theme.textTheme.bodyMedium),
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
                title: const Text('Password protect', style: TextStyle(fontSize: 14)),
                subtitle: _hasPassword ? null : const Text('Require a password to access', style: TextStyle(fontSize: 12)),
                value: _hasPassword,
                onChanged: (v) => setState(() => _hasPassword = v),
              ),
              if (_hasPassword)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      hintText: 'Enter a share password',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Burn after reading', style: TextStyle(fontSize: 14)),
                subtitle: const Text('Self-destruct after first view', style: TextStyle(fontSize: 12)),
                value: _burnAfterReading,
                onChanged: (v) => setState(() => _burnAfterReading = v),
              ),
              Row(
                children: [
                  const Text('Max downloads: ', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: 'Unlimited',
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                      onChanged: (v) => _maxDownloads = int.tryParse(v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'This generates a zero-knowledge deep link. Recipients need AeroDrive installed.',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
            ] else ...[
              // Share link display
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        link,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy),
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
              if (_shareLink!.expiresAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Expires: ${_shareLink!.expiresAt!.toLocal().toString().substring(0, 19)}',
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              if (_shareLink!.burnAfterReading)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(Icons.whatshot, size: 14, color: Colors.orange.shade400),
                      const SizedBox(width: 4),
                      Text('Burn after reading', style: TextStyle(fontSize: 12, color: Colors.orange.shade400)),
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
          child: const Text('Close'),
        ),
        if (_shareLink == null && !_isLoading)
          FilledButton(
            onPressed: _generateLink,
            child: const Text('Generate Link'),
          ),
        if (_shareLink != null)
          FilledButton(
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
