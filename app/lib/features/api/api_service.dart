import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:http/http.dart' as http;

import 'package:aerodrive/core/logger.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/domain/folder_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;
import 'package:path_provider/path_provider.dart';

/// Lightweight REST API for AI/tool integration.
///
/// Runs on localhost:{port} (default 8765) and requires an API key
/// set via the `aerodrive_api_key` setting.
class ApiService {
  final int port;
  final ProviderContainer container;
  HttpServer? _server;

  ApiService({this.port = 8765, required this.container});

  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;

    final app = Router();

    // ── Middleware: JSON content type + CORS + API key auth ──────────
    final middleware = shelf.Pipeline()
        .addMiddleware(_corsMiddleware())
        .addMiddleware(_jsonMiddleware())
        .addMiddleware(_authMiddleware());

    // ── Routes ──────────────────────────────────────────────────────
    app.get('/health', _handleHealth);
    app.get('/files', _handleListFiles);
    app.get('/files/:id', _handleGetFile);
    app.get('/folders', _handleListFolders);
    app.post('/folders', _handleCreateFolder);
    app.post('/upload-url', _handleUploadFromUrl);

    _server = await shelf_io.serve(middleware.addHandler(app.call), '127.0.0.1', port);
    AppLogger.info('API server running on http://127.0.0.1:${_server!.port}');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    AppLogger.info('API server stopped');
  }

  // ── Middleware ────────────────────────────────────────────────────

  shelf.Middleware _corsMiddleware() {
    return (shelf.Handler innerHandler) {
      return (shelf.Request request) async {
        if (request.method == 'OPTIONS') {
          return shelf.Response.ok('', headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization',
          });
        }
        final response = await innerHandler(request);
        return response.change(headers: {'Access-Control-Allow-Origin': '*'});
      };
    };
  }

  shelf.Middleware _jsonMiddleware() {
    return (shelf.Handler innerHandler) {
      return (shelf.Request request) async {
        final response = await innerHandler(request);
        return response.change(headers: {'Content-Type': 'application/json'});
      };
    };
  }

  shelf.Middleware _authMiddleware() {
    return (shelf.Handler innerHandler) {
      return (shelf.Request request) async {
        if (request.url.path == 'health') {
          return await innerHandler(request);
        }

        final settingsRepo = container.read(settingsRepositoryProvider);
        final apiKey = await settingsRepo.getSetting('aerodrive_api_key');
        if (apiKey == null || apiKey.isEmpty) {
          return shelf.Response(403, body: jsonEncode({
            'error': 'API key not configured. Set aerodrive_api_key in Settings > API.',
          }));
        }

        final providedKey = request.headers['authorization']?.replaceFirst('Bearer ', '');
        if (providedKey != apiKey) {
          return shelf.Response(401, body: jsonEncode({
            'error': 'Invalid API key. Provide via Authorization: Bearer <key> header.',
          }));
        }

        return await innerHandler(request);
      };
    };
  }

  // ── Handlers ──────────────────────────────────────────────────────

  Future<shelf.Response> _handleHealth(shelf.Request request) async {
    return shelf.Response.ok(jsonEncode({
      'status': 'ok',
      'version': '1.0.0',
      'api_running': true,
    }));
  }

  Future<shelf.Response> _handleListFiles(shelf.Request request) async {
    try {
      final db = container.read(databaseProvider);
      final folderId = request.url.queryParameters['folder_id'];
      final search = request.url.queryParameters['q'];

      var query = db.select(db.files)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([(t) => drift.OrderingTerm.desc(t.createdAt)]);

      if (folderId != null && folderId.isNotEmpty) {
        query.where((t) => t.folderId.equals(folderId));
      } else {
        query.where((t) => t.folderId.isNull());
      }

      if (search != null && search.isNotEmpty) {
        query.where((t) => t.name.contains(search));
      }

      final files = await query.get();
      return shelf.Response.ok(jsonEncode({
        'files': files.map((f) => _fileToJson(f)).toList(),
      }));
    } catch (e) {
      return shelf.Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  }

  Future<shelf.Response> _handleGetFile(shelf.Request request) async {
    try {
      final fileId = request.params['id']!;
      final db = container.read(databaseProvider);
      final file = await (db.select(db.files)
        ..where((t) => t.id.equals(fileId))
        ..where((t) => t.deletedAt.isNull())
      ).getSingleOrNull();

      if (file == null) {
        return shelf.Response(404, body: jsonEncode({'error': 'File not found'}));
      }

      return shelf.Response.ok(jsonEncode({'file': _fileToJson(file)}));
    } catch (e) {
      return shelf.Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  }

  Future<shelf.Response> _handleListFolders(shelf.Request request) async {
    try {
      final db = container.read(databaseProvider);
      final parentId = request.url.queryParameters['parent_id'];

      var query = db.select(db.folders)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([(t) => drift.OrderingTerm.asc(t.name)]);

      if (parentId != null && parentId.isNotEmpty) {
        query.where((t) => t.parentId.equals(parentId));
      } else {
        query.where((t) => t.parentId.isNull());
      }

      final folders = await query.get();
      return shelf.Response.ok(jsonEncode({
        'folders': folders.map(_folderToJson).toList(),
      }));
    } catch (e) {
      return shelf.Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  }

  Future<shelf.Response> _handleCreateFolder(shelf.Request request) async {
    try {
      final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final name = body['name'] as String?;
      if (name == null || name.trim().isEmpty) {
        return shelf.Response(400, body: jsonEncode({'error': 'name is required'}));
      }

      final parentId = body['parent_id'] as String?;
      final db = container.read(databaseProvider);
      final folderId = const Uuid().v4();

      await db.into(db.folders).insert(
        FoldersCompanion.insert(
          id: folderId,
          name: name.trim(),
          parentId: drift.Value(parentId),
          createdAt: drift.Value(DateTime.now()),
        ),
      );

      return shelf.Response.ok(jsonEncode({
        'folder': {
          'id': folderId,
          'name': name.trim(),
          'parent_id': parentId,
        }
      }));
    } catch (e) {
      return shelf.Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  }

  Future<shelf.Response> _handleUploadFromUrl(shelf.Request request) async {
    try {
      final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final url = body['url'] as String?;
      final folderId = body['folder_id'] as String?;
      final customName = body['name'] as String?;

      if (url == null || url.trim().isEmpty) {
        return shelf.Response(400, body: jsonEncode({'error': 'url is required'}));
      }

      final uri = Uri.parse(url);
      final client = http.Client();
      final response = await client.send(http.Request('GET', uri)..followRedirects = true);

      if (response.statusCode != 200) {
        client.close();
        return shelf.Response(400, body: jsonEncode({
          'error': 'Download failed: HTTP ${response.statusCode}',
        }));
      }

      final bytes = <int>[];
      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
      }
      client.close();

      final tempDir = await getTemporaryDirectory();
      final fileName = (customName?.isNotEmpty == true
          ? customName
          : uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? 'download.bin')!;
      final localPath = '${tempDir.path}/$fileName';
      await File(localPath).writeAsBytes(bytes);

      final scanner = container.read(folderScannerProvider);
      await scanner.scanAndQueueDirectory(localPath, folderId);

      return shelf.Response.ok(jsonEncode({
        'status': 'queued',
        'file_name': fileName,
        'size_bytes': bytes.length,
        'target_folder_id': folderId,
      }));
    } catch (e) {
      return shelf.Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  }

  // ── JSON helpers ──────────────────────────────────────────────────

  Map<String, dynamic> _fileToJson(FileData f) => {
    'id': f.id,
    'name': f.name,
    'size_bytes': f.size,
    'mime_type': f.mimeType,
    'folder_id': f.folderId,
    'is_encrypted': f.isEncrypted,
    'is_chunked': f.isChunked,
    'total_chunks': f.totalChunks,
    'created_at': f.createdAt?.toIso8601String(),
  };

  Map<String, dynamic> _folderToJson(FolderData f) => {
    'id': f.id,
    'name': f.name,
    'parent_id': f.parentId,
    'created_at': f.createdAt?.toIso8601String(),
  };
}
