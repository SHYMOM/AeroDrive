import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path/path.dart' as p;
import 'package:aerodrive/core/logger.dart';

class DropboxService extends StateNotifier<bool> {
  DropboxService() : super(false) {
    _checkStatus();
  }

  final _storage = const FlutterSecureStorage();
  String? _email;
  String? get email => _email;
  bool get connected => state;
  
  String get _clientId => dotenv.env['DROPBOX_CLIENT_ID'] ?? 'PLACEHOLDER_CLIENT_ID';
  String get _clientSecret => dotenv.env['DROPBOX_CLIENT_SECRET'] ?? '';

  Future<void> _checkStatus() async {
    final token = await _storage.read(key: 'dropbox_access_token');
    if (token != null) {
      _email = await _storage.read(key: 'dropbox_email') ?? 'user@dropbox.com';
      state = true;
    }
  }

  /// Returns the stored access token, if any.
  Future<String?> getAccessToken() async {
    return _storage.read(key: 'dropbox_access_token');
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
          if (_clientSecret.isNotEmpty) 'client_secret': _clientSecret,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['access_token'];
        
        await _storage.write(key: 'dropbox_access_token', value: token);
        
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

  Future<bool> uploadBackup(String dbPath, {String destinationFolder = '/AeroDrive', void Function(double progress)? onProgress}) async {
    try {
      final token = await getAccessToken();
      if (token == null) {
        AppLogger.error('Dropbox: No access token available');
        return false;
      }

      final file = File(dbPath);
      if (!await file.exists()) {
        AppLogger.error('Dropbox: File not found at $dbPath');
        return false;
      }

      // Calculate SHA-256 fingerprint for deduplication
      final hashBytes = await sha256.bind(file.openRead()).first;
      final fileHash = hashBytes.toString();
      
      final lastUploadedHash = await _storage.read(key: 'dropbox_last_backup_hash');
      if (lastUploadedHash == fileHash) {
        AppLogger.info('Dropbox: Backup identical to last upload (Deduplicated). Skipping upload.');
        onProgress?.call(1.0);
        return true;
      }

      final fileSize = await file.length();
      final fileName = p.basename(dbPath);
      final destPath = '$destinationFolder/$fileName'.replaceAll('//', '/');

      if (fileSize > 150 * 1024 * 1024) {
        AppLogger.info('Dropbox: File >150MB, using chunked upload ($fileSize bytes)');
        return _uploadChunked(file, token, fileName, onProgress, destinationFolder: destinationFolder, fileHash: fileHash);
      }

      final bytes = await file.readAsBytes();
      final response = await http.post(
        Uri.parse('https://content.dropboxapi.com/2/files/upload'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/octet-stream',
          'Dropbox-API-Arg': jsonEncode({
            'path': destPath,
            'mode': 'overwrite',
            'autorename': true,
          }),
        },
        body: bytes,
      );

      onProgress?.call(1.0);
      if (response.statusCode == 200) {
        AppLogger.info('Dropbox: Backup uploaded successfully');
        await _storage.write(key: 'dropbox_last_backup_hash', value: fileHash);
        return true;
      } else {
        AppLogger.error('Dropbox: Upload failed (${response.statusCode}): ${response.body}');
        return false;
      }
    } catch (e) {
      AppLogger.error('Dropbox upload error', e);
      return false;
    }
  }

  Future<bool> _uploadChunked(File file, String token, String fileName, void Function(double progress)? onProgress, {String destinationFolder = '/AeroDrive', String? fileHash}) async {
    const int chunkSize = 4 * 1024 * 1024;
    final destPath = '$destinationFolder/$fileName'.replaceAll('//', '/');
    final fileSize = await file.length();

    try {
      // Step 1: Start session
      final startResponse = await http.post(
        Uri.parse('https://content.dropboxapi.com/2/files/upload_session/start'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/octet-stream',
          'Dropbox-API-Arg': jsonEncode({
            'close': false,
          }),
        },
        body: <int>[],
      );

      if (startResponse.statusCode != 200) {
        AppLogger.error('Dropbox: Failed to start upload session: ${startResponse.body}');
        return false;
      }

      final sessionData = jsonDecode(startResponse.body);
      final sessionId = sessionData['session_id'] as String;

      final raf = await file.open(mode: FileMode.read);
      int bytesRead = 0;

      // Step 2: Upload chunks
      while (bytesRead < fileSize) {
        final bytesToRead = (fileSize - bytesRead < chunkSize) ? fileSize - bytesRead : chunkSize;
        final chunk = await raf.read(bytesToRead);

        final bool isLastChunk = (bytesRead + chunk.length) >= fileSize;

        if (!isLastChunk) {
          final appendResponse = await http.post(
            Uri.parse('https://content.dropboxapi.com/2/files/upload_session/append_v2'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/octet-stream',
              'Dropbox-API-Arg': jsonEncode({
                'cursor': {
                  'session_id': sessionId,
                  'offset': bytesRead,
                },
                'close': false,
              }),
            },
            body: chunk,
          );

          if (appendResponse.statusCode != 200) {
            AppLogger.error('Dropbox: Chunk append failed at offset $bytesRead: ${appendResponse.body}');
            await raf.close();
            return false;
          }
        } else {
          // Step 3: Finish session
          final finishResponse = await http.post(
            Uri.parse('https://content.dropboxapi.com/2/files/upload_session/finish'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/octet-stream',
              'Dropbox-API-Arg': jsonEncode({
                'cursor': {
                  'session_id': sessionId,
                  'offset': bytesRead,
                },
                'commit': {
                  'path': destPath,
                  'mode': 'overwrite',
                  'autorename': true,
                  'mute': false,
                },
              }),
            },
            body: chunk,
          );

          if (finishResponse.statusCode != 200) {
            AppLogger.error('Dropbox: Session finish failed: ${finishResponse.body}');
            await raf.close();
            return false;
          }
        }

        bytesRead += chunk.length;
        final progress = bytesRead / fileSize;
        onProgress?.call(progress.clamp(0.0, 1.0));
      }

      await raf.close();
      AppLogger.info('Dropbox: Chunked upload completed successfully');
      if (fileHash != null) {
        await _storage.write(key: 'dropbox_last_backup_hash', value: fileHash);
      }
      return true;
    } catch (e) {
      AppLogger.error('Dropbox chunked upload error', e);
      return false;
    }
  }


}

final dropboxServiceProvider = StateNotifierProvider<DropboxService, bool>((ref) {
  return DropboxService();
});
