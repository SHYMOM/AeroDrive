import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CompanionServerDialog extends StatefulWidget {
  const CompanionServerDialog({super.key});

  @override
  State<CompanionServerDialog> createState() => _CompanionServerDialogState();
}

class _CompanionServerDialogState extends State<CompanionServerDialog> {
  final _storage = const FlutterSecureStorage();
  final _urlController = TextEditingController();
  final _keyController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url = await _storage.read(key: 'companion_server_url');
    final apiKey = await _storage.read(key: 'companion_server_api_key');
    
    if (url != null) _urlController.text = url;
    if (apiKey != null) _keyController.text = apiKey;
    
    setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    final url = _urlController.text.trim();
    final apiKey = _keyController.text.trim();
    
    if (url.isEmpty) {
      await _storage.delete(key: 'companion_server_url');
    } else {
      await _storage.write(key: 'companion_server_url', value: url);
    }
    
    if (apiKey.isEmpty) {
      await _storage.delete(key: 'companion_server_api_key');
    } else {
      await _storage.write(key: 'companion_server_api_key', value: apiKey);
    }
    
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Companion Server Configuration'),
      content: _isLoading
          ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Connect your AeroDrive app to an external Go backend server for remote management and syncing.'),
                const SizedBox(height: 16),
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'Backend URL',
                    hintText: 'https://api.my-aero-server.com',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _keyController,
                  decoration: const InputDecoration(
                    labelText: 'Admin API Key',
                    hintText: 'Bearer token for authentication',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
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
