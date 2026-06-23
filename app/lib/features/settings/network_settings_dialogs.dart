import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';

class ConnectionTimeoutDialog extends ConsumerStatefulWidget {
  const ConnectionTimeoutDialog({super.key});

  @override
  ConsumerState<ConnectionTimeoutDialog> createState() => _ConnectionTimeoutDialogState();
}

class _ConnectionTimeoutDialogState extends ConsumerState<ConnectionTimeoutDialog> {
  final _timeoutController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final timeoutStr = await ref.read(settingsRepositoryProvider).getSetting('network_connection_timeout');
    _timeoutController.text = timeoutStr ?? '30';
    setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    final timeoutStr = _timeoutController.text.trim();
    final timeout = int.tryParse(timeoutStr);
    
    if (timeout == null || timeout < 5 || timeout > 300) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid timeout between 5 and 300 seconds.')));
      return;
    }
    
    await ref.read(settingsRepositoryProvider).setSetting('network_connection_timeout', timeout.toString());
    ref.invalidate(settingsRepositoryProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connection Timeout'),
      content: _isLoading
          ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Set the maximum time in seconds to wait for a network response before considering the connection dropped.'),
                const SizedBox(height: 16),
                TextField(
                  controller: _timeoutController,
                  decoration: const InputDecoration(
                    labelText: 'Timeout (Seconds)',
                    hintText: 'e.g. 30',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
