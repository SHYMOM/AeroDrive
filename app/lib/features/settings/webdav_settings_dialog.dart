import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/domain/webdav/webdav_config.dart';
import 'package:aerodrive/domain/webdav/webdav_server.dart';

class WebDavSettingsDialog extends ConsumerStatefulWidget {
  const WebDavSettingsDialog({super.key});

  @override
  ConsumerState<WebDavSettingsDialog> createState() => _WebDavSettingsDialogState();
}

class _WebDavSettingsDialogState extends ConsumerState<WebDavSettingsDialog> {
  final WebDavConfigService _configService = WebDavConfigService();
  WebDavCredentials? _creds;
  bool _isRunning = false;
  bool _isLoading = true;
  String? _error;

  late TextEditingController _portController;

  @override
  void initState() {
    super.initState();
    _portController = TextEditingController();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final creds = await _configService.getCredentials();
    setState(() {
      _creds = creds;
      _portController.text = creds.port.toString();
      _isLoading = false;
    });
  }

  Future<void> _regenerate() async {
    setState(() => _isLoading = true);
    if (_isRunning) _stopServer();
    
    final newCreds = await _configService.regenerateCredentials();
    setState(() {
      _creds = newCreds;
      _isLoading = false;
    });
  }

  Future<void> _toggleServer(bool start) async {
    setState(() {
      _error = null;
      _isLoading = true;
    });

    try {
      if (start) {
        // Save new port if changed
        final newPort = int.tryParse(_portController.text) ?? 8081;
        if (newPort != _creds!.port) {
          await _configService.setPort(newPort);
          _creds = await _configService.getCredentials();
        }

        await WebDavServer.start(_creds!);
        setState(() => _isRunning = true);
      } else {
        _stopServer();
      }
    } on SocketException catch (_) {
      setState(() {
        _error = "Port ${_portController.text} is in use. Please choose a different port in settings.";
        _isRunning = false;
      });
    } catch (e) {
      setState(() {
        _error = "Failed to start server: $e";
        _isRunning = false;
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _stopServer() {
    WebDavServer.stop();
    setState(() => _isRunning = false);
  }

  @override
  void dispose() {
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('WebDAV Server Settings'),
      content: _isLoading 
        ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
        : SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Mount AeroDrive as a native network drive in Windows Explorer or macOS Finder.'),
                const SizedBox(height: 16),
                
                SwitchListTile(
                  title: const Text('Enable Server'),
                  value: _isRunning,
                  onChanged: (val) => _toggleServer(val),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],

                const SizedBox(height: 16),
                const Text('Mount URL:', style: TextStyle(fontWeight: FontWeight.bold)),
                SelectableText('http://127.0.0.1:${_creds?.port}/', style: const TextStyle(color: Colors.greenAccent)),
                const SizedBox(height: 16),

                _buildCopyRow('Username', _creds?.username ?? ''),
                const SizedBox(height: 8),
                _buildCopyRow('Password', _creds?.password ?? ''),
                
                const SizedBox(height: 16),
                TextField(
                  controller: _portController,
                  decoration: const InputDecoration(
                    labelText: 'Local Port (1024 - 65535)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  enabled: !_isRunning,
                ),
              ],
            ),
          ),
      actions: [
        if (!_isLoading)
          TextButton(
            onPressed: _isRunning ? null : _regenerate,
            child: const Text('Regenerate Credentials'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildCopyRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text('$label: $value', style: const TextStyle(fontFamily: 'monospace')),
        ),
        IconButton(
          icon: const Icon(Icons.copy, size: 16),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied to clipboard')));
          },
        ),
      ],
    );
  }
}
