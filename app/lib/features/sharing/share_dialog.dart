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
  String? _shareLink;
  String? _error;

  Future<void> _generateLink() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final link = await ref.read(shareServiceProvider).generateShareLink(widget.file);
      if (mounted) {
        setState(() {
          _shareLink = link;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Share File'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sharing: ${widget.file.name}'),
          const SizedBox(height: 16),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_shareLink == null)
            const Text(
              'This will generate a zero-knowledge App-to-App deep link. The recipient must have AeroDrive installed.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            )
          else
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _shareLink!,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _shareLink!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard')),
                      );
                    },
                  )
                ],
              ),
            ),
        ],
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
      ],
    );
  }
}
