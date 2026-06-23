import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class InlineBotSetupDialog extends StatefulWidget {
  const InlineBotSetupDialog({super.key});

  @override
  State<InlineBotSetupDialog> createState() => _InlineBotSetupDialogState();
}

class _InlineBotSetupDialogState extends State<InlineBotSetupDialog> {
  final _storage = const FlutterSecureStorage();
  final _tokenController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = await _storage.read(key: 'integration_inline_bot_token');
    if (token != null) _tokenController.text = token;
    setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      await _storage.delete(key: 'integration_inline_bot_token');
    } else {
      await _storage.write(key: 'integration_inline_bot_token', value: token);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Inline Bot Setup'),
      content: _isLoading
          ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Provide a Telegram Bot Token to enable searching your AeroDrive files from any chat using @your_bot_name.'),
                const SizedBox(height: 16),
                TextField(
                  controller: _tokenController,
                  decoration: const InputDecoration(
                    labelText: 'Bot Token',
                    hintText: 'e.g. 123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11',
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

class SaveToDriveBotDialog extends StatefulWidget {
  const SaveToDriveBotDialog({super.key});

  @override
  State<SaveToDriveBotDialog> createState() => _SaveToDriveBotDialogState();
}

class _SaveToDriveBotDialogState extends State<SaveToDriveBotDialog> {
  final _storage = const FlutterSecureStorage();
  final _tokenController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = await _storage.read(key: 'integration_savetodrive_bot_token');
    if (token != null) _tokenController.text = token;
    setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      await _storage.delete(key: 'integration_savetodrive_bot_token');
    } else {
      await _storage.write(key: 'integration_savetodrive_bot_token', value: token);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save-to-Drive Bot'),
      content: _isLoading
          ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Provide a Bot Token that will listen for forwarded files and automatically queue them for AeroDrive upload.'),
                const SizedBox(height: 16),
                TextField(
                  controller: _tokenController,
                  decoration: const InputDecoration(
                    labelText: 'Bot Token',
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

class WebhookUrlDialog extends StatefulWidget {
  const WebhookUrlDialog({super.key});

  @override
  State<WebhookUrlDialog> createState() => _WebhookUrlDialogState();
}

class _WebhookUrlDialogState extends State<WebhookUrlDialog> {
  final _storage = const FlutterSecureStorage();
  final _urlController = TextEditingController();
  final _secretController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url = await _storage.read(key: 'integration_webhook_url');
    final secret = await _storage.read(key: 'integration_webhook_secret');
    if (url != null) _urlController.text = url;
    if (secret != null) _secretController.text = secret;
    setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    final url = _urlController.text.trim();
    final secret = _secretController.text.trim();
    if (url.isEmpty) {
      await _storage.delete(key: 'integration_webhook_url');
      await _storage.delete(key: 'integration_webhook_secret');
    } else {
      await _storage.write(key: 'integration_webhook_url', value: url);
      await _storage.write(key: 'integration_webhook_secret', value: secret);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Webhook Setup'),
      content: _isLoading
          ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('AeroDrive will fire a POST request to this URL when important events occur (e.g. Upload Complete).'),
                const SizedBox(height: 16),
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'Endpoint URL',
                    hintText: 'https://myapp.com/webhook',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _secretController,
                  decoration: const InputDecoration(
                    labelText: 'Secret Token (Optional)',
                    hintText: 'Used for X-Hub-Signature validation',
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

class ApiKeyManagementDialog extends StatefulWidget {
  const ApiKeyManagementDialog({super.key});

  @override
  State<ApiKeyManagementDialog> createState() => _ApiKeyManagementDialogState();
}

class _ApiKeyManagementDialogState extends State<ApiKeyManagementDialog> {
  final _storage = const FlutterSecureStorage();
  String? _currentKey;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _currentKey = await _storage.read(key: 'integration_api_key');
    setState(() => _isLoading = false);
  }

  Future<void> _generateKey() async {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    final key = 'aero_sk_${Uri.encodeComponent(String.fromCharCodes(values)).replaceAll('%', '').substring(0, 32)}';
    
    await _storage.write(key: 'integration_api_key', value: key);
    setState(() => _currentKey = key);
  }

  Future<void> _revokeKey() async {
    await _storage.delete(key: 'integration_api_key');
    setState(() => _currentKey = null);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('API Key Management'),
      content: _isLoading
          ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Generate an API Key to authenticate external companion apps with your local AeroDrive engine.'),
                const SizedBox(height: 16),
                if (_currentKey != null) ...[
                  const Text('Active API Key:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SelectableText(
                    _currentKey!,
                    style: const TextStyle(fontFamily: 'monospace', color: Colors.greenAccent),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _revokeKey,
                    icon: const Icon(Icons.delete),
                    label: const Text('Revoke Key'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                  ),
                ] else ...[
                  const Text('No active API key.', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _generateKey,
                    icon: const Icon(Icons.vpn_key),
                    label: const Text('Generate New Key'),
                  ),
                ]
              ],
            ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}
