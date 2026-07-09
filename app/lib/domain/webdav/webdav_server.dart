import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';

import '../../core/logger.dart';
import '../../core/providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../data/db/database.dart';
import '../download_orchestrator.dart';
import '../download_queue_service.dart';
import 'webdav_config.dart';

class WebDavServer {
  static Isolate? _serverIsolate;
  static int? _activePort;
  static ReceivePort? _mainReceivePort;
  static SendPort? _isolateSendPort;
  static WidgetRef? _ref;

  /// Starts the WebDAV server. Throws SocketException if port is in use.
  static Future<void> start(WidgetRef ref, WebDavCredentials creds) async {
    if (_activePort != null) return;
    _ref = ref;

    _mainReceivePort = ReceivePort();
    
    _serverIsolate = await Isolate.spawn(
      _serverWorker, 
      _WorkerParams(sendPort: _mainReceivePort!.sendPort, creds: creds),
    );

    // Set up bi-directional port communication
    _mainReceivePort!.listen(_handleIsolateMessage);

    _activePort = creds.port;
    AppLogger.info("WebDAV Server started on 127.0.0.1:$_activePort");
  }

  static void stop() {
    _serverIsolate?.kill(priority: Isolate.immediate);
    _serverIsolate = null;
    _mainReceivePort?.close();
    _mainReceivePort = null;
    _isolateSendPort = null;
    _activePort = null;
    _ref = null;
    AppLogger.info("WebDAV Server stopped.");
  }

  // --- MAIN THREAD MESSAGE HANDLER (BRIDGE) ---

  static void _handleIsolateMessage(dynamic message) async {
    if (message is SendPort) {
      _isolateSendPort = message;
      // Send the main thread's sendPort back to isolate for complete setup
      _isolateSendPort!.send(_mainReceivePort!.sendPort);
      return;
    }

    if (message is Map<String, dynamic>) {
      final id = message['id'] as String;
      final cmd = message['cmd'] as String;
      
      try {
        if (_ref == null) throw Exception("Server is stopping or stopped");

        if (cmd == 'resolve_path') {
          final path = message['path'] as String;
          final resolved = await _resolvePath(path);
          _isolateSendPort?.send({'id': id, 'result': resolved});
        } else if (cmd == 'mkcol') {
          final path = message['path'] as String;
          await _mkcol(path);
          _isolateSendPort?.send({'id': id, 'result': {'status': 'success'}});
        } else if (cmd == 'delete') {
          final path = message['path'] as String;
          await _delete(path);
          _isolateSendPort?.send({'id': id, 'result': {'status': 'success'}});
        } else if (cmd == 'upload_file') {
          final localPath = message['localPath'] as String;
          final targetPath = message['targetPath'] as String;
          await _uploadFile(localPath, targetPath);
          _isolateSendPort?.send({'id': id, 'result': {'status': 'success'}});
        } else if (cmd == 'download_file') {
          final fileId = message['fileId'] as String;
          final localPath = await _downloadFile(fileId);
          _isolateSendPort?.send({'id': id, 'result': {'localPath': localPath}});
        }
      } catch (e, s) {
        AppLogger.error('WebDAV main thread error on cmd $cmd', e, s);
        _isolateSendPort?.send({'id': id, 'error': e.toString()});
      }
    }
  }

  // --- DATABASE & TRANSFER QUEUE WORKERS (MAIN THREAD) ---

  static Future<Map<String, dynamic>?> _resolvePath(String path) async {
    final db = _ref!.read(databaseProvider);
    final cleanPath = Uri.decodeComponent(path);
    final parts = cleanPath.split('/').where((p) => p.isNotEmpty).toList();

    if (parts.isEmpty) {
      final folders = await (db.select(db.folders)..where((f) => f.parentId.isNull() & f.deletedAt.isNull())).get();
      final files = await (db.select(db.files)..where((f) => f.folderId.isNull() & f.deletedAt.isNull())).get();
      
      return {
        'type': 'directory',
        'name': '',
        'size': 0,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'children': [
          ...folders.map((f) => {
            'type': 'directory',
            'name': f.name,
            'size': 0,
            'createdAt': f.createdAt?.millisecondsSinceEpoch ?? 0,
          }),
          ...files.map((f) => {
            'type': 'file',
            'name': f.name,
            'size': f.size ?? 0,
            'createdAt': f.createdAt?.millisecondsSinceEpoch ?? 0,
          })
        ]
      };
    }

    String? currentFolderId;
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      final folder = await (db.select(db.folders)
        ..where((f) => f.name.equals(part) & (currentFolderId == null ? f.parentId.isNull() : f.parentId.equals(currentFolderId!)) & f.deletedAt.isNull())
      ).getSingleOrNull();

      if (folder != null) {
        currentFolderId = folder.id;
        if (i == parts.length - 1) {
          final subFolders = await (db.select(db.folders)..where((f) => f.parentId.equals(folder.id) & f.deletedAt.isNull())).get();
          final files = await (db.select(db.files)..where((f) => f.folderId.equals(folder.id) & f.deletedAt.isNull())).get();

          return {
            'type': 'directory',
            'name': folder.name,
            'size': 0,
            'createdAt': folder.createdAt?.millisecondsSinceEpoch ?? 0,
            'children': [
              ...subFolders.map((f) => {
                'type': 'directory',
                'name': f.name,
                'size': 0,
                'createdAt': f.createdAt?.millisecondsSinceEpoch ?? 0,
              }),
              ...files.map((f) => {
                'type': 'file',
                'name': f.name,
                'size': f.size ?? 0,
                'createdAt': f.createdAt?.millisecondsSinceEpoch ?? 0,
              })
            ]
          };
        }
      } else {
        if (i == parts.length - 1) {
          final file = await (db.select(db.files)
            ..where((f) => f.name.equals(part) & (currentFolderId == null ? f.folderId.isNull() : f.folderId.equals(currentFolderId!)) & f.deletedAt.isNull())
          ).getSingleOrNull();
          if (file != null) {
            return {
              'type': 'file',
              'id': file.id,
              'name': file.name,
              'size': file.size ?? 0,
              'createdAt': file.createdAt?.millisecondsSinceEpoch ?? 0,
              'mimeType': file.mimeType ?? 'application/octet-stream',
            };
          }
        }
        return null;
      }
    }
    return null;
  }

  static Future<String?> _resolveFolderId(List<String> parts, AeroDriveDatabase db) async {
    String? currentFolderId;
    for (final part in parts) {
      final folder = await (db.select(db.folders)
        ..where((f) => f.name.equals(part) & (currentFolderId == null ? f.parentId.isNull() : f.parentId.equals(currentFolderId!)) & f.deletedAt.isNull())
      ).getSingleOrNull();
      if (folder == null) return null;
      currentFolderId = folder.id;
    }
    return currentFolderId;
  }

  static Future<void> _mkcol(String path) async {
    final db = _ref!.read(databaseProvider);
    final cleanPath = Uri.decodeComponent(path);
    final parts = cleanPath.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return;

    final folderName = parts.last;
    String? parentId;
    if (parts.length > 1) {
      parentId = await _resolveFolderId(parts.sublist(0, parts.length - 1), db);
    }

    final newId = const Uuid().v4();
    await db.into(db.folders).insert(
      FoldersCompanion.insert(
        id: newId,
        name: folderName,
        parentId: drift.Value(parentId),
        createdAt: drift.Value(DateTime.now()),
      )
    );
  }

  static Future<void> _delete(String path) async {
    final db = _ref!.read(databaseProvider);
    final folderRepo = _ref!.read(folderRepositoryProvider);
    final fileRepo = _ref!.read(fileRepositoryProvider);

    final cleanPath = Uri.decodeComponent(path);
    final parts = cleanPath.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return;

    final resolved = await _resolvePath(cleanPath);
    if (resolved == null) return;

    if (resolved['type'] == 'directory') {
      final folderId = await _resolveFolderId(parts, db);
      if (folderId != null) {
        await folderRepo.trashFolder(folderId);
      }
    } else {
      final fileId = resolved['id'] as String?;
      if (fileId != null) {
        await fileRepo.softDelete(fileId);
      }
    }
  }

  static Future<void> _uploadFile(String localPath, String targetPath) async {
    final db = _ref!.read(databaseProvider);
    final cleanPath = Uri.decodeComponent(targetPath);
    final parts = cleanPath.split('/').where((p) => p.isNotEmpty).toList();
    final fileName = parts.last;

    String? folderId;
    if (parts.length > 1) {
      folderId = await _resolveFolderId(parts.sublist(0, parts.length - 1), db);
    }

    final file = File(localPath);
    if (!await file.exists()) throw Exception("Temporary local file is missing");
    final fileSize = await file.length();
    final queueId = const Uuid().v4();

    // Insert into transferQueue to trigger standard upload
    await db.into(db.transferQueue).insert(
      TransferQueueCompanion.insert(
        id: queueId,
        type: const drift.Value('UPLOAD_FILE'),
        status: const drift.Value('PENDING'),
        priority: const drift.Value(1),
        totalBytes: drift.Value(fileSize),
        fileId: drift.Value('$localPath|${folderId ?? ''}'),
        createdAt: drift.Value(DateTime.now()),
      )
    );
  }

  static Future<String> _downloadFile(String fileId) async {
    final db = _ref!.read(databaseProvider);
    final file = await (db.select(db.files)..where((f) => f.id.equals(fileId))).getSingle();
    final queueId = const Uuid().v4();

    // Queue download
    await db.into(db.transferQueue).insert(
      TransferQueueCompanion.insert(
        id: queueId,
        type: const drift.Value('DOWNLOAD_FILE'),
        status: const drift.Value('PENDING'),
        priority: const drift.Value(1),
        fileId: drift.Value(fileId),
        createdAt: drift.Value(DateTime.now()),
      )
    );

    // Poll for download completion
    for (var attempt = 0; attempt < 240; attempt++) {
      await Future.delayed(const Duration(milliseconds: 500));
      final item = await (db.select(db.transferQueue)..where((q) => q.id.equals(queueId))).getSingleOrNull();
      if (item == null) throw Exception("Download queue task disappeared");
      if (item.status == 'COMPLETED') {
        final targetDir = await DownloadOrchestrator.ensureDownloadDirectory(file.mimeType);
        final rawPath = '${targetDir.path}${Platform.pathSeparator}${file.name}';
        
        final fileEntity = File(rawPath);
        if (await fileEntity.exists()) return rawPath;

        // Search directory for duplicate-deduped names e.g. file (1).txt
        final list = targetDir.listSync();
        for (final entity in list) {
          if (entity is File && entity.path.split(Platform.pathSeparator).last.startsWith(file.name.split('.').first)) {
            return entity.path;
          }
        }
        return rawPath;
      }
      if (item.status == 'FAILED') {
        throw Exception(item.errorMessage ?? "Download task failed");
      }
    }
    throw Exception("WebDAV download timed out after 2 minutes");
  }

  // --- ISOLATE WORKER RUNTIME ---

  static final Map<String, Completer<dynamic>> _pendingRequests = {};
  static late SendPort _toMainPort;
  static late ReceivePort _fromMainPort;

  static Future<dynamic> _sendToMain(String cmd, Map<String, dynamic> args) {
    final id = const Uuid().v4();
    final completer = Completer<dynamic>();
    _pendingRequests[id] = completer;

    _toMainPort.send({
      'id': id,
      'cmd': cmd,
      ...args,
    });

    return completer.future;
  }

  static Future<void> _serverWorker(_WorkerParams params) async {
    _fromMainPort = ReceivePort();
    params.sendPort.send(_fromMainPort.sendPort);

    _fromMainPort.listen((message) {
      if (message is SendPort) {
        _toMainPort = message;
      } else if (message is Map<String, dynamic>) {
        final id = message['id'] as String;
        if (_pendingRequests.containsKey(id)) {
          if (message.containsKey('error')) {
            _pendingRequests[id]!.completeError(message['error']);
          } else {
            _pendingRequests[id]!.complete(message['result']);
          }
          _pendingRequests.remove(id);
        }
      }
    });

    final router = Router();
    
    // Register handlers
    router.add('OPTIONS', '/<path|.*>', _handleOptions);
    router.add('PROPFIND', '/<path|.*>', _handlePropfind);
    router.add('LOCK', '/<path|.*>', _handleLock);
    router.add('UNLOCK', '/<path|.*>', _handleUnlock);
    router.add('GET', '/<path|.*>', _handleGet);
    router.add('PUT', '/<path|.*>', _handlePut);
    router.add('MKCOL', '/<path|.*>', _handleMkcol);
    router.add('DELETE', '/<path|.*>', _handleDelete);

    final handler = const shelf.Pipeline()
        .addMiddleware(shelf.logRequests())
        .addMiddleware(_authMiddleware(params.creds.basicAuthHeader))
        .addMiddleware(_osHeadersMiddleware())
        .addHandler(router.call);

    try {
      await shelf_io.serve(handler, InternetAddress.loopbackIPv4, params.creds.port);
    } catch (e) {
      // ignore
    }
  }

  // --- SHELF HANDLERS (RUNNING IN ISOLATE) ---

  static shelf.Middleware _authMiddleware(String expectedAuthHeader) => (innerHandler) => (request) {
        if (request.method == 'OPTIONS') return innerHandler(request);
        final authHeader = request.headers['authorization'];
        if (authHeader != expectedAuthHeader) {
          return shelf.Response(
            401,
            body: 'Unauthorized',
            headers: {'WWW-Authenticate': 'Basic realm="AeroDrive"'},
          );
        }
        return innerHandler(request);
      };

  static shelf.Middleware _osHeadersMiddleware() => (innerHandler) => (request) async {
        final response = await innerHandler(request);
        return response.change(headers: {
          'DAV': '1, 2',
          'MS-Author-Via': 'DAV',
        });
      };

  static Future<shelf.Response> _handleOptions(shelf.Request request) async => shelf.Response.ok('', headers: {
        'Allow': 'OPTIONS, PROPFIND, GET, PUT, MKCOL, DELETE, LOCK, UNLOCK',
      });

  static Future<shelf.Response> _handleLock(shelf.Request request) async {
    final uuid = 'urn:uuid:${DateTime.now().microsecondsSinceEpoch}-${_nextLockId++}';
    final xmlBody = '''<?xml version="1.0" encoding="utf-8" ?>
<D:prop xmlns:D="DAV:">
  <D:lockdiscovery>
    <D:activelock>
      <D:locktype><D:write/></D:locktype>
      <D:lockscope><D:exclusive/></D:lockscope>
      <D:depth>Infinity</D:depth>
      <D:timeout>Second-3600</D:timeout>
      <D:locktoken>
        <D:href>$uuid</D:href>
      </D:locktoken>
    </D:activelock>
  </D:lockdiscovery>
</D:prop>''';

    return shelf.Response(200, body: xmlBody, headers: {
      'Content-Type': 'application/xml; charset=utf-8',
      'Lock-Token': '<$uuid>',
    });
  }

  static int _nextLockId = 0;

  static Future<shelf.Response> _handleUnlock(shelf.Request request) async => shelf.Response(204);

  static Future<shelf.Response> _handlePropfind(shelf.Request request) async {
    final depth = request.headers['depth'] ?? '1';
    final path = request.url.path;

    final resolved = await _sendToMain('resolve_path', {'path': path});
    if (resolved == null) {
      return shelf.Response.notFound('Not Found');
    }

    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="utf-8"');
    builder.element('D:multistatus', namespaces: {'DAV:': 'D'}, nest: () {
      builder.element('D:response', nest: () {
        builder.element('D:href', nest: '/$path');
        builder.element('D:propstat', nest: () {
          builder.element('D:prop', nest: () {
            if (resolved['type'] == 'directory') {
              builder.element('D:resourcetype', nest: () {
                builder.element('D:collection');
              });
            } else {
              builder.element('D:resourcetype');
              builder.element('D:getcontentlength', nest: resolved['size'].toString());
              builder.element('D:getcontenttype', nest: resolved['mimeType']);
            }
            builder.element('D:getlastmodified', nest: HttpDate.format(DateTime.fromMillisecondsSinceEpoch(resolved['createdAt']).toUtc()));
          });
          builder.element('D:status', nest: 'HTTP/1.1 200 OK');
        });
      });

      if (depth == '1' && resolved['children'] != null) {
        final children = resolved['children'] as List;
        for (final child in children) {
          final childPath = path.isEmpty ? child['name'] : '$path/${child['name']}';
          builder.element('D:response', nest: () {
            builder.element('D:href', nest: '/$childPath');
            builder.element('D:propstat', nest: () {
              builder.element('D:prop', nest: () {
                if (child['type'] == 'directory') {
                  builder.element('D:resourcetype', nest: () {
                    builder.element('D:collection');
                  });
                } else {
                  builder.element('D:resourcetype');
                  builder.element('D:getcontentlength', nest: child['size'].toString());
                }
                builder.element('D:getlastmodified', nest: HttpDate.format(DateTime.fromMillisecondsSinceEpoch(child['createdAt']).toUtc()));
              });
              builder.element('D:status', nest: 'HTTP/1.1 200 OK');
            });
          });
        }
      }
    });

    return shelf.Response(
      207,
      body: builder.buildDocument().toXmlString(),
      headers: {'Content-Type': 'application/xml; charset=utf-8'},
    );
  }

  static Future<shelf.Response> _handleGet(shelf.Request request) async {
    final path = request.url.path;
    final resolved = await _sendToMain('resolve_path', {'path': path});
    if (resolved == null || resolved['type'] == 'directory') {
      return shelf.Response.notFound('File Not Found');
    }

    final localPath = await _sendToMain('download_file', {'fileId': resolved['id']}) as String;
    final file = File(localPath);
    if (!await file.exists()) {
      return shelf.Response.internalServerError(body: "Decrypted file not found on disk");
    }

    // Stream file contents safely, clean up immediately on completion
    final stream = file.openRead().transform(StreamTransformer.fromHandlers(
      handleDone: (sink) {
        sink.close();
        file.delete().catchError((_) {});
      }
    ));

    return shelf.Response.ok(
      stream,
      headers: {
        'Content-Type': resolved['mimeType'],
        'Content-Length': file.lengthSync().toString(),
      },
    );
  }

  static Future<shelf.Response> _handlePut(shelf.Request request) async {
    final path = request.url.path;
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/webdav_upload_${const Uuid().v4()}.tmp');
    final sink = tempFile.openWrite();

    // Stream network request body in 4MB chunks directly to disk cache
    await request.read().forEach((chunk) {
      sink.add(chunk);
    });
    await sink.close();

    // Trigger encryption and upload on the main thread
    await _sendToMain('upload_file', {
      'localPath': tempFile.path,
      'targetPath': path,
    });

    return shelf.Response(201, body: 'Created');
  }

  static Future<shelf.Response> _handleMkcol(shelf.Request request) async {
    final path = request.url.path;
    await _sendToMain('mkcol', {'path': path});
    return shelf.Response(201, body: 'Created');
  }

  static Future<shelf.Response> _handleDelete(shelf.Request request) async {
    final path = request.url.path;
    await _sendToMain('delete', {'path': path});
    return shelf.Response(204, body: 'No Content');
  }
}

class _WorkerParams {
  _WorkerParams({required this.sendPort, required this.creds});
  final SendPort sendPort;
  final WebDavCredentials creds;
}
