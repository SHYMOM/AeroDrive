import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class WebDavCredentials {
  WebDavCredentials({
    required this.username,
    required this.password,
    required this.port,
    this.requireAuth = false,
  });

  final String username;
  final String password;
  final int port;
  final bool requireAuth;

  String get basicAuthHeader {
    final credentials = '$username:$password';
    return 'Basic ${base64Encode(utf8.encode(credentials))}';
  }
}

class WebDavConfigService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const int defaultPort = 49188;
  static const String _keyUsername = 'webdav_username';
  static const String _keyPassword = 'webdav_password';
  static const String _keyPort = 'webdav_port';
  static const String _keyServerEnabled = 'webdav_server_enabled';
  static const String _keyRequireAuth = 'webdav_require_auth';

  Future<WebDavCredentials> getCredentials() async {
    final String? username = await _storage.read(key: _keyUsername);
    final String? password = await _storage.read(key: _keyPassword);
    final String? portStr = await _storage.read(key: _keyPort);
    final String? requireAuthStr = await _storage.read(key: _keyRequireAuth);

    if (username == null || password == null) {
      return regenerateCredentials();
    }

    return WebDavCredentials(
      username: username,
      password: password,
      port: portStr != null ? int.tryParse(portStr) ?? defaultPort : defaultPort,
      requireAuth: requireAuthStr == 'true',
    );
  }

  Future<WebDavCredentials> regenerateCredentials() async {
    const username = 'aerodrive_user';
    final password = const Uuid().v4().replaceAll('-', '').substring(0, 16);

    await _storage.write(key: _keyUsername, value: username);
    await _storage.write(key: _keyPassword, value: password);

    final String? portStr = await _storage.read(key: _keyPort);
    final port = portStr != null ? int.tryParse(portStr) ?? defaultPort : defaultPort;
    final String? requireAuthStr = await _storage.read(key: _keyRequireAuth);

    return WebDavCredentials(
      username: username,
      password: password,
      port: port,
      requireAuth: requireAuthStr == 'true',
    );
  }

  Future<void> setPort(int port) async {
    if (port < 1024 || port > 65535) {
      throw ArgumentError('Port must be between 1024 and 65535');
    }
    await _storage.write(key: _keyPort, value: port.toString());
  }

  Future<void> setRequireAuth(bool require) async {
    await _storage.write(key: _keyRequireAuth, value: require.toString());
  }

  Future<bool> isServerAutoStartEnabled() async {
    final val = await _storage.read(key: _keyServerEnabled);
    return val == 'true';
  }

  Future<void> setServerAutoStartEnabled(bool enabled) async {
    await _storage.write(key: _keyServerEnabled, value: enabled.toString());
  }
}
