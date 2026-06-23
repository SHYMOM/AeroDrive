import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:aerodrive/core/logger.dart';

class DropboxService extends StateNotifier<bool> {
  DropboxService() : super(false) {
    _checkStatus();
  }

  final _storage = const FlutterSecureStorage();
  String? _email;
  String? get email => _email;
  
  // This can be loaded from .env
  String get _clientId => dotenv.env['DROPBOX_CLIENT_ID'] ?? 'PLACEHOLDER_CLIENT_ID';

  Future<void> _checkStatus() async {
    final token = await _storage.read(key: 'dropbox_access_token');
    if (token != null) {
      _email = await _storage.read(key: 'dropbox_email') ?? 'user@dropbox.com';
      state = true;
    }
  }

  Future<void> openAuthUrl() async {
    final url = Uri.parse('https://www.dropbox.com/oauth2/authorize?client_id=$_clientId&response_type=code&token_access_type=offline');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      AppLogger.error('Could not launch Dropbox Auth URL');
    }
  }

  Future<bool> connectWithCode(String code) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.dropboxapi.com/oauth2/token'),
        body: {
          'code': code.trim(),
          'grant_type': 'authorization_code',
          'client_id': _clientId,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['access_token'];
        
        await _storage.write(key: 'dropbox_access_token', value: token);
        
        // Optionally fetch account info to get email, but for now just mock email or fetch it
        _email = 'connected_user@dropbox.com'; 
        await _storage.write(key: 'dropbox_email', value: _email);
        
        state = true;
        return true;
      } else {
        AppLogger.error('Dropbox Auth failed: ${response.body}');
        return false;
      }
    } catch (e) {
      AppLogger.error('Dropbox connection error', e);
      return false;
    }
  }

  Future<void> disconnect() async {
    await _storage.delete(key: 'dropbox_access_token');
    await _storage.delete(key: 'dropbox_email');
    _email = null;
    state = false;
  }

  Future<bool> uploadBackup(String dbPath) async {
    // TODO: Implement actual Dropbox REST API upload in Phase X
    // Uses http.post to https://content.dropboxapi.com/2/files/upload
    await Future.delayed(const Duration(seconds: 3));
    return true;
  }
}

final dropboxServiceProvider = StateNotifierProvider<DropboxService, bool>((ref) {
  return DropboxService();
});
