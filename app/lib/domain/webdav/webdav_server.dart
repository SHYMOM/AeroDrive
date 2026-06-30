import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:aerodrive/domain/webdav/webdav_config.dart';
import 'package:aerodrive/domain/webdav/propfind_handler.dart';

class WebDavServer {
  static Isolate? _serverIsolate;
  static int? _activePort;

  /// Starts the WebDAV server. Throws SocketException if port is in use.
  static Future<void> start(WebDavCredentials creds) async {
    if (_activePort != null) return;

    final receivePort = ReceivePort();
    
    _serverIsolate = await Isolate.spawn(
      _serverWorker, 
      _WorkerParams(sendPort: receivePort.sendPort, creds: creds),
    );

    final response = await receivePort.first;
    if (response is Exception) {
      _serverIsolate?.kill(priority: Isolate.immediate);
      _serverIsolate = null;
      throw response; // e.g. SocketException
    }

    _activePort = creds.port;
    debugPrint("WebDAV Server started on 127.0.0.1:$_activePort");
  }

  static void stop() {
    _serverIsolate?.kill(priority: Isolate.immediate);
    _serverIsolate = null;
    _activePort = null;
    debugPrint("WebDAV Server stopped.");
  }

  static void _serverWorker(_WorkerParams params) async {
    final router = Router();
    
    // Mount handlers
    router.add('OPTIONS', '/<path|.*>', _handleOptions);
    router.add('PROPFIND', '/<path|.*>', _handlePropfind);
    router.add('LOCK', '/<path|.*>', _handleLock);
    router.add('UNLOCK', '/<path|.*>', _handleUnlock);
    // GET, PUT, MKCOL, DELETE can be wired here

    // Middleware Pipeline
    final handler = const shelf.Pipeline()
        .addMiddleware(shelf.logRequests())
        .addMiddleware(_authMiddleware(params.creds.basicAuthHeader))
        .addMiddleware(_osHeadersMiddleware())
        .addHandler(router.call);

    try {
      await shelf_io.serve(handler, InternetAddress.loopbackIPv4, params.creds.port);
      params.sendPort.send(true); // Success
    } catch (e) {
      params.sendPort.send(e); // Send exception back (e.g., SocketException)
    }
  }

  /// Ensures Basic Authentication is present and matches.
  static shelf.Middleware _authMiddleware(String expectedAuthHeader) {
    return (shelf.Handler innerHandler) {
      return (shelf.Request request) {
        if (request.method == 'OPTIONS') {
          // OPTIONS often doesn't carry auth in some OS discovery phases
          return innerHandler(request);
        }

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
    };
  }

  /// Appends mandatory WebDAV headers to all responses.
  static shelf.Middleware _osHeadersMiddleware() {
    return (shelf.Handler innerHandler) {
      return (shelf.Request request) async {
        final response = await innerHandler(request);
        return response.change(headers: {
          'DAV': '1, 2',
          'MS-Author-Via': 'DAV',
        });
      };
    };
  }

  static Future<shelf.Response> _handleOptions(shelf.Request request) async {
    return shelf.Response.ok('', headers: {
      'Allow': 'OPTIONS, PROPFIND, GET, PUT, MKCOL, DELETE, LOCK, UNLOCK',
    });
  }

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

  static Future<shelf.Response> _handleUnlock(shelf.Request request) async {
    return shelf.Response(204); // No Content
  }

  static Future<shelf.Response> _handlePropfind(shelf.Request request) async {
    return PropfindHandler.handle(request);
  }
}

class _WorkerParams {
  final SendPort sendPort;
  final WebDavCredentials creds;
  _WorkerParams({required this.sendPort, required this.creds});
}
