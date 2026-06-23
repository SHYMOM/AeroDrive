import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class WebDavCredentials {
  final String username;
  final String password;
  final int port;

  WebDavCredentials({
    required this.username,
    required this.password,
    required this.port,
  });

  String get basicAuthHeader {
    final credentials = '$username:$password';
    return 'Basic ${base64Encode(utf8.encode(credentials))}';
  }
}

class WebDavConfigService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _keyUsername = 'webdav_username';
  static const String _keyPassword = 'webdav_password';
  static const String _keyPort = 'webdav_port';

  Future<WebDavCredentials> getCredentials() async {
    String? username = await _storage.read(key: _keyUsername);
    String? password = await _storage.read(key: _keyPassword);
    String? portStr = await _storage.read(key: _keyPort);

    if (username == null || password == null) {
      return regenerateCredentials();
    }

    return WebDavCredentials(
      username: username,
      password: password,
      port: portStr != null ? int.tryParse(portStr) ?? 8081 : 8081,
    );
  }

  Future<WebDavCredentials> regenerateCredentials() async {
    final username = 'aerodrive_user';
    final password = const Uuid().v4().replaceAll('-', '').substring(0, 16);

    await _storage.write(key: _keyUsername, value: username);
    await _storage.write(key: _keyPassword, value: password);

    String? portStr = await _storage.read(key: _keyPort);
    final port = portStr != null ? int.tryParse(portStr) ?? 8081 : 8081;

    return WebDavCredentials(
      username: username,
      password: password,
      port: port,
    );
  }

  Future<void> setPort(int port) async {
    if (port < 1024 || port > 65535) {
      throw ArgumentError('Port must be between 1024 and 65535');
    }
    await _storage.write(key: _keyPort, value: port.toString());
  }
}
