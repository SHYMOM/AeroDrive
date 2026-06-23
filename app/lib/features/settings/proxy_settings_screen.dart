import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:aerodrive/features/telegram/telegram_service.dart';

class ProxySettingsScreen extends ConsumerStatefulWidget {
  const ProxySettingsScreen({super.key});

  @override
  ConsumerState<ProxySettingsScreen> createState() => _ProxySettingsScreenState();
}

class _ProxySettingsScreenState extends ConsumerState<ProxySettingsScreen> {
  final _serverCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();
  
  String _proxyType = 'SOCKS5';
  bool _isEnabled = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = ref.read(settingsRepositoryProvider);
    final enabled = await settings.getSetting('proxy_enabled');
    final type = await settings.getSetting('proxy_type');
    final server = await settings.getSetting('proxy_server');
    final port = await settings.getSetting('proxy_port');
    final user = await settings.getSetting('proxy_user');
    final pass = await settings.getSetting('proxy_pass');
    final secret = await settings.getSetting('proxy_secret');

    if (mounted) {
      setState(() {
        _isEnabled = enabled == 'true';
        _proxyType = type ?? 'SOCKS5';
        _serverCtrl.text = server ?? '';
        _portCtrl.text = port ?? '';
        _userCtrl.text = user ?? '';
        _passCtrl.text = pass ?? '';
        _secretCtrl.text = secret ?? '';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveAndApply() async {
    final settings = ref.read(settingsRepositoryProvider);
    final telegram = ref.read(telegramServiceProvider.notifier);

    await settings.setSetting('proxy_enabled', _isEnabled.toString());
    await settings.setSetting('proxy_type', _proxyType);
    await settings.setSetting('proxy_server', _serverCtrl.text);
    await settings.setSetting('proxy_port', _portCtrl.text);
    await settings.setSetting('proxy_user', _userCtrl.text);
    await settings.setSetting('proxy_pass', _passCtrl.text);
    await settings.setSetting('proxy_secret', _secretCtrl.text);

    if (_isEnabled) {
      final port = int.tryParse(_portCtrl.text) ?? 1080;
      await telegram.addProxy(
        server: _serverCtrl.text,
        port: port,
        username: _proxyType == 'SOCKS5' ? _userCtrl.text : null,
        password: _proxyType == 'SOCKS5' ? _passCtrl.text : null,
        secret: _proxyType == 'MTProto' ? _secretCtrl.text : null,
        enable: true,
      );
    } else {
      await telegram.disableProxy(0); // TDLib clears proxies if you don't supply specific IDs sometimes, or we can just send disableProxy
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Proxy settings applied.')));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Proxy Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveAndApply,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Enable Proxy'),
            subtitle: const Text('Route Telegram traffic through a custom server'),
            value: _isEnabled,
            onChanged: (val) => setState(() => _isEnabled = val),
          ),
          const Divider(),
          if (_isEnabled) ...[
            DropdownButtonFormField<String>(
              value: _proxyType,
              decoration: const InputDecoration(labelText: 'Proxy Type'),
              items: const [
                DropdownMenuItem(value: 'SOCKS5', child: Text('SOCKS5')),
                DropdownMenuItem(value: 'MTProto', child: Text('MTProto')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _proxyType = val);
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _serverCtrl,
              decoration: const InputDecoration(labelText: 'Server IP / Hostname'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _portCtrl,
              decoration: const InputDecoration(labelText: 'Port'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            if (_proxyType == 'SOCKS5') ...[
              TextField(
                controller: _userCtrl,
                decoration: const InputDecoration(labelText: 'Username (Optional)'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passCtrl,
                decoration: const InputDecoration(labelText: 'Password (Optional)'),
                obscureText: true,
              ),
            ] else ...[
              TextField(
                controller: _secretCtrl,
                decoration: const InputDecoration(labelText: 'Secret (Hex)'),
              ),
            ],
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _saveAndApply,
              icon: const Icon(Icons.check),
              label: const Text('Apply and Connect'),
            ),
          ]
        ],
      ),
    );
  }
}
