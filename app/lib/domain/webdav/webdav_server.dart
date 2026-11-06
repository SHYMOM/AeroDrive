import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';
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
import '../../core/providers/security_providers.dart';
import '../../core/security/master_key_provider.dart';
import '../../data/crypto/encryption_engine.dart';
import '../../data/db/database.dart';
import '../../features/telegram/telegram_manager.dart';
import '../../features/telegram/telegram_service.dart';
import '../channel_load_balancer.dart';
import '../download_orchestrator.dart';
import '../recovery/manifest_encoder.dart';
import '../streaming/streaming_server.dart';
import 'webdav_config.dart';

typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

class WebDavServer {
  static Isolate? _serverIsolate;
  static int? _activePort;
  static ReceivePort? _mainReceivePort;
  static SendPort? _isolateSendPort;
  static ProviderReader? _read;
  static ProviderContainer? _rootContainer;

  static bool get isRunning => _activePort != null;
  static int? get activePort => _activePort;

  /// Registers a permanent root [ProviderContainer] so that WebDAV is never affected by widget disposal.
  static void setRootContainer(ProviderContainer container) {
    _rootContainer = container;
    _read = <T>(p) => container.read(p);
  }

  /// Starts the WebDAV server.
  static Future<void> start({
    WidgetRef? widgetRef,
    Ref? ref,
    ProviderContainer? container,
    required WebDavCredentials creds,
  }) async {
    if (_activePort != null) return;

    if (container != null) {
      setRootContainer(container);
    } else if (_rootContainer != null) {
      _read = <T>(p) => _rootContainer!.read(p);
    } else if (widgetRef != null) {
      _read = <T>(p) => widgetRef.read(p);
    } else if (ref != null) {
      _read = <T>(p) => ref.read(p);
    } else {
      throw ArgumentError('Either container, widgetRef, or ref must be provided');
    }

    int streamingPort = 0;
    try {
      final streamingServer = _rootContainer?.read(streamingServerProvider) ??
          (ref != null ? ref.read(streamingServerProvider) : null) ??
          (widgetRef != null ? widgetRef.read(streamingServerProvider) : null);
      if (streamingServer != null) {
        if (streamingServer.port == 0) {
          await streamingServer.start();
        }
        streamingPort = streamingServer.port;
      }
    } catch (e) {
      AppLogger.warning('WebDavServer: Could not determine streamingServer port: $e');
    }

    _mainReceivePort = ReceivePort();
    
    final tempDir = await getTemporaryDirectory();
    _serverIsolate = await Isolate.spawn(
      _serverWorker, 
      _WorkerParams(
        sendPort: _mainReceivePort!.sendPort,
        creds: creds,
        tempDirPath: tempDir.path,
        streamingPort: streamingPort,
      ),
    );

    _mainReceivePort!.listen(_handleIsolateMessage);

    _activePort = creds.port;
    AppLogger.info("WebDAV Server started on 127.0.0.1:$_activePort (requireAuth: ${creds.requireAuth}, streamingPort: $streamingPort)");
  }

  static void stop() {
    _serverIsolate?.kill(priority: Isolate.immediate);
    _serverIsolate = null;
    _mainReceivePort?.close();
    _mainReceivePort = null;
    _isolateSendPort = null;
    _activePort = null;
    if (_rootContainer == null) {
      _read = null;
    }
    AppLogger.info("WebDAV Server stopped.");
  }

  // --- PATH NORMALIZATION ---

  /// Strips leading slashes and any leading Windows WebDAV redirector virtual root ("DavWWWRoot").
  static String cleanWebDavPath(String rawPath) {
    String p;
    try {
      p = Uri.decodeComponent(rawPath).trim();
    } catch (_) {
      p = rawPath.trim();
    }
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    if (p.toLowerCase().startsWith('davwwwroot')) {
      p = p.substring('davwwwroot'.length);
      while (p.startsWith('/')) {
        p = p.substring(1);
      }
    }
    return p;
  }

  static String _encodeWebDavHref(String path, {bool isDavWWWRoot = false, bool isDir = false}) {
    final prefix = isDavWWWRoot ? '/DavWWWRoot' : '';
    if (path.isEmpty || path == '/') {
      return prefix.isEmpty ? '/' : '$prefix/';
    }
    final segments = path.split('/').where((s) => s.isNotEmpty).map(Uri.encodeComponent).join('/');
    return '$prefix/$segments${isDir ? '/' : ''}';
  }

  // --- MAIN THREAD MESSAGE HANDLER (BRIDGE) ---

  static void _handleIsolateMessage(dynamic message) async {
    if (message is SendPort) {
      _isolateSendPort = message;
      _isolateSendPort!.send(_mainReceivePort!.sendPort);
      return;
    }

    if (message is Map<String, dynamic>) {
      final id = message['id'] as String;
      final cmd = message['cmd'] as String;
      
      try {
        if (_read == null) throw Exception("Server reader is not initialized");

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
        } else if (cmd == 'move') {
          final sourcePath = message['sourcePath'] as String;
          final destPath = message['destPath'] as String;
          final overwrite = message['overwrite'] as bool? ?? true;
          final res = await _move(sourcePath, destPath, overwrite);
          _isolateSendPort?.send({'id': id, 'result': res});
        } else if (cmd == 'copy') {
          final sourcePath = message['sourcePath'] as String;
          final destPath = message['destPath'] as String;
          final overwrite = message['overwrite'] as bool? ?? true;
          final res = await _copy(sourcePath, destPath, overwrite);
          _isolateSendPort?.send({'id': id, 'result': res});
        } else if (cmd == 'upload_file') {
          final localPath = message['localPath'] as String;
          final targetPath = message['targetPath'] as String;
          await _uploadFile(localPath, targetPath);
          _isolateSendPort?.send({'id': id, 'result': {'status': 'success'}});
        } else if (cmd == 'download_file') {
          final fileId = message['fileId'] as String;
          final localPath = await _downloadFileDirect(fileId);
          _isolateSendPort?.send({'id': id, 'result': localPath});
        }
      } catch (e, s) {
        AppLogger.error('WebDAV main thread error on cmd $cmd', e, s);
        _isolateSendPort?.send({'id': id, 'error': e.toString()});
      }
    }
  }

  // --- DATABASE & TRANSFER QUEUE WORKERS (MAIN THREAD) ---

  static Future<Map<String, dynamic>?> _resolvePath(String rawPath) async {
    final db = _read!(databaseProvider);
    final cleanPath = cleanWebDavPath(rawPath);
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
            'id': f.id,
            'name': f.name,
            'size': f.size ?? 0,
            'createdAt': f.createdAt?.millisecondsSinceEpoch ?? 0,
            'mimeType': f.mimeType ?? 'application/octet-stream',
          })
        ]
      };
    }

    String? currentFolderId;
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      final folder = await (db.select(db.folders)
        ..where((f) => f.name.equals(part) & (currentFolderId == null ? f.parentId.isNull() : f.parentId.equals(currentFolderId)) & f.deletedAt.isNull())
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
                'id': f.id,
                'name': f.name,
                'size': f.size ?? 0,
                'createdAt': f.createdAt?.millisecondsSinceEpoch ?? 0,
                'mimeType': f.mimeType ?? 'application/octet-stream',
              })
            ]
          };
        }
      } else {
        if (i == parts.length - 1) {
          final file = await (db.select(db.files)
            ..where((f) => f.name.equals(part) & (currentFolderId == null ? f.folderId.isNull() : f.folderId.equals(currentFolderId)) & f.deletedAt.isNull())
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
        ..where((f) => f.name.equals(part) & (currentFolderId == null ? f.parentId.isNull() : f.parentId.equals(currentFolderId)) & f.deletedAt.isNull())
      ).getSingleOrNull();
      if (folder == null) return null;
      currentFolderId = folder.id;
    }
    return currentFolderId;
  }

  /// Recursively resolves or creates missing intermediate folders and dispatches cloud manifest uploads.
  static Future<String?> _resolveOrCreateFolderHierarchy(List<String> parts, AeroDriveDatabase db) async {
    String? currentFolderId;
    for (final part in parts) {
      final folder = await (db.select(db.folders)
        ..where((f) => f.name.equals(part) & 
            (currentFolderId == null ? f.parentId.isNull() : f.parentId.equals(currentFolderId)) & 
            f.deletedAt.isNull())
      ).getSingleOrNull();

      if (folder != null) {
        currentFolderId = folder.id;
      } else {
        final newFolderId = const Uuid().v4();
        await db.into(db.folders).insert(
          FoldersCompanion.insert(
            id: newFolderId,
            name: part,
            parentId: drift.Value(currentFolderId),
            createdAt: drift.Value(DateTime.now()),
            updatedAt: drift.Value(DateTime.now()),
          ),
        );
        // Upload folder manifest to Telegram in the background
        unawaited(_uploadFolderManifestDirect(newFolderId, part, currentFolderId));
        currentFolderId = newFolderId;
      }
    }
    return currentFolderId;
  }

  /// Uploads encrypted folder manifest (1x1 PNG) to the active Telegram storage channel.
  static Future<void> _uploadFolderManifestDirect(String folderId, String folderName, String? parentId) async {
    if (_read == null) return;
    File? tempFile;
    try {
      final settingsRepo = _read!(settingsRepositoryProvider);
      final targetChannel = await ChannelLoadBalancer.selectStorageChannel(settings: settingsRepo);
      if (targetChannel == null) return;
      final chatId = targetChannel['id'] is String ? int.parse(targetChannel['id']) : targetChannel['id'] as int;

      final masterKeyBytes = _read!(masterKeyProvider);
      if (masterKeyBytes == null) return;

      final cipher = AesGcm.with256bits();
      final secretKey = await cipher.newSecretKeyFromBytes(masterKeyBytes);

      final manifestCaption = await ManifestEncoder.encodeFolderManifest(
        folderId: folderId,
        folderName: folderName,
        parentFolderId: parentId,
        masterKey: secretKey,
        createdAt: DateTime.now(),
      );

      final tempDir = await getTemporaryDirectory();
      tempFile = File('${tempDir.path}${Platform.pathSeparator}folder_$folderId.png');
      final pngBytes = Uint8List.fromList([
        137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 108, 137, 0, 0, 0, 11, 73, 68, 65, 84, 120, 156, 99, 96, 0, 0, 0, 2, 0, 1, 226, 33, 188, 51, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130
      ]);
      await tempFile.writeAsBytes(pngBytes);

      final targetAccountId = targetChannel['accountId']?.toString();
      final accounts = _read!(telegramManagerProvider);
      final telegram = (targetAccountId != null && targetAccountId.isNotEmpty)
          ? accounts.firstWhere(
              (c) => c.accountId == targetAccountId,
              orElse: () => _read!(telegramServiceProvider.notifier),
            )
          : _read!(telegramServiceProvider.notifier);

      await telegram.uploadDocument(chatId, tempFile.path, caption: manifestCaption);
      AppLogger.info('WebDavServer: Uploaded cloud manifest for folder "$folderName" ($folderId)');
    } catch (e) {
      AppLogger.warning('WebDavServer: Failed to upload folder manifest: $e');
    } finally {
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    }
  }

  static Future<void> _mkcol(String rawPath) async {
    final db = _read!(databaseProvider);
    final cleanPath = cleanWebDavPath(rawPath);
    final parts = cleanPath.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return;

    await _resolveOrCreateFolderHierarchy(parts, db);
  }

  static Future<void> _delete(String rawPath) async {
    final db = _read!(databaseProvider);
    final folderRepo = _read!(folderRepositoryProvider);
    final fileRepo = _read!(fileRepositoryProvider);

    final cleanPath = cleanWebDavPath(rawPath);
    AppLogger.info('WebDavServer: _delete requested for cleanPath="$cleanPath" (raw="$rawPath")');
    final parts = cleanPath.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) {
      AppLogger.warning('WebDavServer: _delete ignored empty parts');
      return;
    }

    final resolved = await _resolvePath(cleanPath);
    if (resolved == null) {
      AppLogger.warning('WebDavServer: _delete could not resolve path "$cleanPath"');
      return;
    }

    if (resolved['type'] == 'directory') {
      final folderId = await _resolveFolderId(parts, db);
      if (folderId != null) {
        AppLogger.info('WebDavServer: soft-deleting folder $folderId');
        await folderRepo.trashFolder(folderId);
      }
    } else {
      final fileId = resolved['id'] as String?;
      if (fileId != null) {
        AppLogger.info('WebDavServer: soft-deleting file $fileId (${resolved['name']})');
        await fileRepo.softDelete(fileId);
        try {
          final tempDir = await getTemporaryDirectory();
          final cacheDir = Directory('${tempDir.path}${Platform.pathSeparator}aerodrive_webdav_cache');
          final safeName = (resolved['name'] as String).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
          final cacheFile = File('${cacheDir.path}${Platform.pathSeparator}${fileId}_$safeName');
          if (await cacheFile.exists()) {
            await cacheFile.delete();
          }
        } catch (_) {}
      }
    }
  }

  static Future<Map<String, dynamic>> _move(String sourcePath, String destPath, bool overwrite) async {
    final db = _read!(databaseProvider);
    final cleanSource = cleanWebDavPath(sourcePath);
    final cleanDest = cleanWebDavPath(destPath);

    final srcResolved = await _resolvePath(cleanSource);
    if (srcResolved == null) {
      return {'status': 'error', 'code': 404, 'error': 'Source not found'};
    }

    final destParts = cleanDest.split('/').where((p) => p.isNotEmpty).toList();
    if (destParts.isEmpty) {
      return {'status': 'error', 'code': 400, 'error': 'Invalid destination'};
    }

    final destName = destParts.last;
    String? destFolderId;
    if (destParts.length > 1) {
      destFolderId = await _resolveFolderId(destParts.sublist(0, destParts.length - 1), db);
    }

    if (srcResolved['type'] == 'directory') {
      final srcParts = cleanSource.split('/').where((p) => p.isNotEmpty).toList();
      final folderId = await _resolveFolderId(srcParts, db);
      if (folderId == null) return {'status': 'error', 'code': 404, 'error': 'Folder not found'};

      await (db.update(db.folders)..where((f) => f.id.equals(folderId))).write(
        FoldersCompanion(
          name: drift.Value(destName),
          parentId: drift.Value(destFolderId),
        ),
      );
      return {'status': 'success'};
    } else {
      final fileId = srcResolved['id'] as String;
      // Check if destination exists
      final destFile = await (db.select(db.files)
        ..where((f) => f.name.equals(destName) & 
            (destFolderId == null ? f.folderId.isNull() : f.folderId.equals(destFolderId)) & 
            f.deletedAt.isNull())
      ).getSingleOrNull();

      if (destFile != null) {
        if (!overwrite) {
          return {'status': 'error', 'code': 412, 'error': 'Destination file already exists'};
        }
        final fileRepo = _read!(fileRepositoryProvider);
        await fileRepo.softDelete(destFile.id);
      }

      await (db.update(db.files)..where((f) => f.id.equals(fileId))).write(
        FilesCompanion(
          name: drift.Value(destName),
          folderId: drift.Value(destFolderId),
        ),
      );
      return {'status': 'success'};
    }
  }

  static Future<Map<String, dynamic>> _copy(String sourcePath, String destPath, bool overwrite) async {
    final db = _read!(databaseProvider);
    final cleanSource = cleanWebDavPath(sourcePath);
    final cleanDest = cleanWebDavPath(destPath);

    final srcResolved = await _resolvePath(cleanSource);
    if (srcResolved == null) {
      return {'status': 'error', 'code': 404, 'error': 'Source not found'};
    }

    final destParts = cleanDest.split('/').where((p) => p.isNotEmpty).toList();
    if (destParts.isEmpty) {
      return {'status': 'error', 'code': 400, 'error': 'Invalid destination'};
    }

    final destName = destParts.last;
    String? destFolderId;
    if (destParts.length > 1) {
      destFolderId = await _resolveFolderId(destParts.sublist(0, destParts.length - 1), db);
    }

    if (srcResolved['type'] == 'file') {
      final srcFile = await (db.select(db.files)..where((f) => f.id.equals(srcResolved['id']))).getSingle();
      final newFileId = const Uuid().v4();

      await db.into(db.files).insert(
        FilesCompanion.insert(
          id: newFileId,
          name: destName,
          size: drift.Value(srcFile.size),
          mimeType: drift.Value(srcFile.mimeType),
          folderId: drift.Value(destFolderId),
          sha256Hash: drift.Value(srcFile.sha256Hash),
          totalChunks: drift.Value(srcFile.totalChunks),
          createdAt: drift.Value(DateTime.now()),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );

      final chunks = await (db.select(db.chunks)..where((c) => c.fileId.equals(srcFile.id))).get();
      for (final chunk in chunks) {
        await db.into(db.chunks).insert(
          ChunksCompanion.insert(
            id: const Uuid().v4(),
            fileId: drift.Value(newFileId),
            chunkIndex: drift.Value(chunk.chunkIndex),
            messageId: drift.Value(chunk.messageId),
            channelId: drift.Value(chunk.channelId),
            size: drift.Value(chunk.size),
            hash: drift.Value(chunk.hash),
          ),
        );
      }
      return {'status': 'success'};
    }

    return {'status': 'error', 'code': 501, 'error': 'Folder copy not supported'};
  }

  static Future<void> _uploadFile(String localPath, String rawTargetPath) async {
    final db = _read!(databaseProvider);
    final cleanPath = cleanWebDavPath(rawTargetPath);
    final parts = cleanPath.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return;

    final fileName = parts.last;
    String? folderId;
    if (parts.length > 1) {
      folderId = await _resolveOrCreateFolderHierarchy(parts.sublist(0, parts.length - 1), db);
    }

    final file = File(localPath);
    if (!await file.exists()) throw Exception("Temporary local file is missing");
    final fileSize = await file.length();

    // Check if file already exists under this parent folder
    final existingFile = await (db.select(db.files)
      ..where((f) => f.name.equals(fileName) & 
          (folderId == null ? f.folderId.isNull() : f.folderId.equals(folderId)) & 
          f.deletedAt.isNull())
    ).getSingleOrNull();

    final fileIdToUse = existingFile?.id ?? const Uuid().v4();
    final mimeType = _getMimeType(fileName);

    // If 0-byte file (standard initial Windows Explorer probe before sending real file bytes):
    // Record in local DB and return immediately WITHOUT enqueuing to Telegram.
    // This prevents TDLib rejecting empty documents ("InputFile is not specified") and eliminates phantom failure cards!
    if (fileSize == 0) {
      if (existingFile != null) {
        await (db.update(db.files)..where((f) => f.id.equals(fileIdToUse))).write(
          FilesCompanion(
            size: const drift.Value(0),
            mimeType: drift.Value(mimeType),
            updatedAt: drift.Value(DateTime.now()),
          ),
        );
      } else {
        await db.into(db.files).insert(
          FilesCompanion.insert(
            id: fileIdToUse,
            name: fileName,
            folderId: drift.Value(folderId),
            size: const drift.Value(0),
            mimeType: drift.Value(mimeType),
            isEncrypted: const drift.Value(true),
            createdAt: drift.Value(DateTime.now()),
            updatedAt: drift.Value(DateTime.now()),
          ),
          mode: drift.InsertMode.insertOrReplace,
        );
      }
      try {
        await file.delete();
      } catch (_) {}
      AppLogger.info('WebDavServer: 0-byte probe for "$fileName" acknowledged locally without queuing to Telegram');
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final cacheDir = Directory('${tempDir.path}${Platform.pathSeparator}aerodrive_webdav_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final fileCacheDir = Directory('${cacheDir.path}${Platform.pathSeparator}$fileIdToUse');
    if (!await fileCacheDir.exists()) {
      await fileCacheDir.create(recursive: true);
    }
    final cachedFilePath = '${fileCacheDir.path}${Platform.pathSeparator}$safeName';
    await file.copy(cachedFilePath);
    try {
      await file.delete();
    } catch (_) {}

    // Pre-insert or update in db.files so Windows Explorer PROPFIND / GET immediately finds it
    if (existingFile != null) {
      await (db.update(db.files)..where((f) => f.id.equals(fileIdToUse))).write(
        FilesCompanion(
          size: drift.Value(fileSize),
          mimeType: drift.Value(mimeType),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );
    } else {
      await db.into(db.files).insert(
        FilesCompanion.insert(
          id: fileIdToUse,
          name: fileName,
          folderId: drift.Value(folderId),
          size: drift.Value(fileSize),
          mimeType: drift.Value(mimeType),
          isEncrypted: const drift.Value(true),
          createdAt: drift.Value(DateTime.now()),
          updatedAt: drift.Value(DateTime.now()),
        ),
        mode: drift.InsertMode.insertOrReplace,
      );
    }

    // Enqueue background upload to Telegram with preassigned fileId and clean filename
    await db.into(db.transferQueue).insert(
      TransferQueueCompanion.insert(
        id: const Uuid().v4(),
        type: const drift.Value('UPLOAD_FILE'),
        status: const drift.Value('PENDING'),
        priority: const drift.Value(1),
        totalBytes: drift.Value(fileSize),
        fileId: drift.Value('$cachedFilePath|${folderId ?? ''}|$fileIdToUse|$fileName'),
        createdAt: drift.Value(DateTime.now()),
      ),
    );

    try {
      _read!(uploadQueueServiceProvider);
    } catch (_) {}
  }

  static final Map<String, Completer<String>> _inFlightDownloads = {};

  static Future<String> _downloadFileDirect(String fileId) async {
    if (_inFlightDownloads.containsKey(fileId)) {
      return await _inFlightDownloads[fileId]!.future;
    }

    final completer = Completer<String>();
    _inFlightDownloads[fileId] = completer;

    try {
      final db = _read!(databaseProvider);
      final file = await (db.select(db.files)..where((f) => f.id.equals(fileId))).getSingle();
      
      final tempDir = await getTemporaryDirectory();
      final cacheDir = Directory('${tempDir.path}${Platform.pathSeparator}aerodrive_webdav_cache');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final safeName = file.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final cacheFilePath = '${cacheDir.path}${Platform.pathSeparator}${file.id}_$safeName';
      final cacheFile = File(cacheFilePath);

      // Return immediately if valid cached file exists
      if (await cacheFile.exists() && (await cacheFile.length()) == (file.size ?? 0)) {
        completer.complete(cacheFilePath);
        return cacheFilePath;
      }

      // Fetch chunks from local database
      final chunks = await (db.select(db.chunks)
        ..where((c) => c.fileId.equals(fileId))
        ..orderBy([(c) => drift.OrderingTerm.asc(c.chunkIndex)])
      ).get();

      if (chunks.isEmpty) {
        throw Exception("Chunk metadata missing for file $fileId");
      }

      final validChunks = chunks.where((c) => c.messageId != null && c.messageId! > 0 && c.channelId != null).toList();
      final totalChunks = file.totalChunks;
      if (validChunks.length < totalChunks) {
        throw Exception("Incomplete chunks for file $fileId ($validChunks/$totalChunks)");
      }

      final telegramManager = _read!(telegramManagerProvider.notifier);
      final settingsRepo = _read!(settingsRepositoryProvider);
      final settingsStr = await settingsRepo.getSetting('storage_channels_list');

      final List<String> localEncryptedPaths = [];
      for (final chunk in validChunks) {
        var targetAccountId = 'primary';
        if (settingsStr != null) {
          try {
            final List<dynamic> channels = jsonDecode(settingsStr);
            final ch = channels.cast<Map<String, dynamic>>().firstWhere(
              (c) => c['id']?.toString() == chunk.channelId?.toString(),
              orElse: () => {},
            );
            targetAccountId = ch['accountId'] ?? 'primary';
          } catch (_) {}
        }
        final telegram = telegramManager.getClient(targetAccountId);
        Map<String, dynamic> msg;
        try {
          msg = await telegram.getMessage(chunk.channelId!, chunk.messageId!);
        } catch (_) {
          await telegram.openChat(chunk.channelId!);
          final msgs = await telegram.getMessages(chunk.channelId!, [chunk.messageId!]);
          final list = msgs['messages'] as List<dynamic>?;
          if (list != null && list.isNotEmpty && list.first != null) {
            msg = list.first as Map<String, dynamic>;
          } else {
            throw Exception("Chunk message ${chunk.messageId} not found");
          }
        }

        final content = msg['content'] as Map<String, dynamic>?;
        final doc = content?['document'] as Map<String, dynamic>?;
        final remoteId = doc?['document']?['id'] as int?;
        if (remoteId == null) throw Exception("Document id missing for chunk ${chunk.chunkIndex}");

        final downloadRes = await telegram.sendRequest({
          '@type': 'downloadFile',
          'file_id': remoteId,
          'priority': 32,
          'synchronous': false,
        });

        final local = downloadRes['local'] as Map<String, dynamic>?;
        String? chunkPath = local?['path'] as String?;
        if (local?['is_downloading_completed'] != true || chunkPath == null || chunkPath.isEmpty) {
          for (var i = 0; i < 240; i++) {
            await Future.delayed(const Duration(milliseconds: 250));
            final poll = await telegram.sendRequest({'@type': 'getFile', 'file_id': remoteId});
            final pollLocal = poll['local'] as Map<String, dynamic>?;
            if (pollLocal?['is_downloading_completed'] == true) {
              chunkPath = pollLocal?['path'] as String?;
              if (chunkPath != null && chunkPath.isNotEmpty) break;
            }
          }
        }
        if (chunkPath == null || chunkPath.isEmpty) {
          throw Exception("Download chunk ${chunk.chunkIndex} timed out");
        }
        localEncryptedPaths.add(chunkPath);
      }

      // Decrypt chunks to cacheFilePath
      final masterKeyBytes = _read!(masterKeyProvider) ?? MasterKeyProvider.instance.key;
      if (masterKeyBytes == null) throw Exception("Master key not available (vault locked)");

      final engine = EncryptionEngine();
      final unwrapped = await engine.unwrapDek(file.sha256Hash!, masterKeyBytes);
      final dekBytes = unwrapped[0]!;
      final ctrIv = unwrapped[1];

      final orchestrator = DownloadOrchestrator();
      await orchestrator.processFileForDownload(
        localEncryptedPaths,
        safeName,
        dekBytes,
        outputPath: cacheFilePath,
        ctrIv: ctrIv,
      );

      completer.complete(cacheFilePath);
      return cacheFilePath;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _inFlightDownloads.remove(fileId);
    }
  }

  static String _getMimeType(String fileName) {
    final dotIdx = fileName.lastIndexOf('.');
    final ext = dotIdx >= 0 ? fileName.substring(dotIdx + 1).toLowerCase() : '';
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'svg':
        return 'image/svg+xml';
      case 'ico':
        return 'image/x-icon';
      case 'mp4':
        return 'video/mp4';
      case 'mkv':
        return 'video/x-matroska';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'webm':
        return 'video/webm';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'flac':
        return 'audio/flac';
      case 'aac':
        return 'audio/aac';
      case 'ogg':
        return 'audio/ogg';
      case 'm4a':
        return 'audio/mp4';
      case 'pdf':
        return 'application/pdf';
      case 'zip':
        return 'application/zip';
      case 'rar':
        return 'application/x-rar-compressed';
      case '7z':
        return 'application/x-7z-compressed';
      case 'tar':
      case 'gz':
        return 'application/gzip';
      case 'txt':
        return 'text/plain';
      case 'json':
        return 'application/json';
      case 'html':
      case 'htm':
        return 'text/html';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'exe':
        return 'application/x-msdownload';
      default:
        return 'application/octet-stream';
    }
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

  static late String _tempDirPath;
  static int _streamingPort = 0;

  static Future<void> _serverWorker(_WorkerParams params) async {
    _tempDirPath = params.tempDirPath;
    _streamingPort = params.streamingPort;
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
    
    // Register WebDAV handlers
    router.add('OPTIONS', '/<path|.*>', _handleOptions);
    router.add('PROPFIND', '/<path|.*>', _handlePropfind);
    router.add('PROPPATCH', '/<path|.*>', _handleProppatch);
    router.add('LOCK', '/<path|.*>', _handleLock);
    router.add('UNLOCK', '/<path|.*>', _handleUnlock);
    router.add('HEAD', '/<path|.*>', _handleHead);
    router.add('GET', '/<path|.*>', _handleGet);
    router.add('PUT', '/<path|.*>', _handlePut);
    router.add('MKCOL', '/<path|.*>', _handleMkcol);
    router.add('DELETE', '/<path|.*>', _handleDelete);
    router.add('MOVE', '/<path|.*>', _handleMove);
    router.add('COPY', '/<path|.*>', _handleCopy);

    final handler = const shelf.Pipeline()
        .addMiddleware(shelf.logRequests())
        .addMiddleware(_authMiddleware(params.creds.basicAuthHeader, params.creds.requireAuth))
        .addMiddleware(_osHeadersMiddleware())
        .addHandler(router.call);

    try {
      await shelf_io.serve(handler, InternetAddress.loopbackIPv4, params.creds.port);
    } catch (e) {
      // ignore
    }
  }

  // --- SHELF HANDLERS (RUNNING IN ISOLATE) ---

  static shelf.Middleware _authMiddleware(String expectedAuthHeader, bool requireAuth) => (innerHandler) => (request) {
        if (request.method == 'OPTIONS') return innerHandler(request);
        if (!requireAuth) return innerHandler(request);

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
        if (request.method == 'OPTIONS') {
          return shelf.Response.ok('', headers: {
            'DAV': '1, 2',
            'MS-Author-Via': 'DAV',
            'Allow': 'OPTIONS, PROPFIND, PROPPATCH, HEAD, GET, PUT, MKCOL, DELETE, MOVE, COPY, LOCK, UNLOCK',
            'Content-Length': '0',
          });
        }
        final response = await innerHandler(request);
        return response.change(headers: {
          'DAV': '1, 2',
          'MS-Author-Via': 'DAV',
        });
      };

  static Future<shelf.Response> _handleOptions(shelf.Request request) async => shelf.Response.ok('', headers: {
        'Allow': 'OPTIONS, PROPFIND, PROPPATCH, HEAD, GET, PUT, MKCOL, DELETE, MOVE, COPY, LOCK, UNLOCK',
        'DAV': '1, 2',
        'MS-Author-Via': 'DAV',
        'Content-Length': '0',
      });

  static Future<shelf.Response> _handleProppatch(shelf.Request request) async {
    final rawPath = request.url.path;
    final href = rawPath.isEmpty ? '/' : '/$rawPath';
    final xmlBody = '''<?xml version="1.0" encoding="utf-8" ?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>$href</D:href>
    <D:propstat>
      <D:prop/>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
</D:multistatus>''';
    return shelf.Response(207, body: xmlBody, headers: {'Content-Type': 'application/xml; charset=utf-8'});
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

  static Future<shelf.Response> _handleUnlock(shelf.Request request) async => shelf.Response(204);

  static Future<shelf.Response> _handlePropfind(shelf.Request request) async {
    final depth = request.headers['depth'] ?? '1';
    final rawPath = request.url.path;
    final isDavWWWRoot = rawPath.toLowerCase().startsWith('davwwwroot');
    final prefix = isDavWWWRoot ? '/DavWWWRoot' : '';
    final cleanPath = cleanWebDavPath(rawPath);

    final resolved = await _sendToMain('resolve_path', {'path': cleanPath});
    if (resolved == null) {
      return shelf.Response.notFound('Not Found');
    }

    final isDir = resolved['type'] == 'directory';
    final rootHref = _encodeWebDavHref(cleanPath, isDavWWWRoot: isDavWWWRoot, isDir: isDir);

    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="utf-8"');
    builder.element('D:multistatus', namespaces: {
      'DAV:': 'D',
      'urn:uuid:c2f41010-65b3-11d1-a29f-00aa00c14882/': 'b',
    }, nest: () {
      builder.element('D:response', nest: () {
        builder.element('D:href', nest: rootHref);
        builder.element('D:propstat', nest: () {
          builder.element('D:prop', nest: () {
            builder.element('D:displayname', nest: cleanPath.isEmpty ? 'AeroDrive' : resolved['name']);
            builder.element('b:isreadonly', nest: '0');
            builder.element('b:ishidden', nest: '0');
            builder.element('b:Win32FileAttributes', nest: isDir ? '00000010' : '00000020');
            if (isDir) {
              builder.element('D:resourcetype', nest: () {
                builder.element('D:collection');
              });
              builder.element('b:iscollection', nest: '1');
              builder.element('D:getcontenttype', nest: 'httpd/unix-directory');
            } else {
              builder.element('D:resourcetype');
              builder.element('b:iscollection', nest: '0');
              builder.element('D:getcontentlength', nest: (resolved['size'] ?? 0).toString());
              final mime = (resolved['mimeType'] as String?)?.isNotEmpty == true && resolved['mimeType'] != 'application/octet-stream'
                  ? resolved['mimeType'] as String
                  : _getMimeType((resolved['name'] as String?) ?? '');
              builder.element('D:getcontenttype', nest: mime);
              builder.element('D:getetag', nest: '"${resolved['id']}-${resolved['size']}-${resolved['createdAt']}"');
            }
            builder.element('D:creationdate', nest: DateTime.fromMillisecondsSinceEpoch(resolved['createdAt'] ?? 0).toUtc().toIso8601String());
            builder.element('D:getlastmodified', nest: HttpDate.format(DateTime.fromMillisecondsSinceEpoch(resolved['createdAt'] ?? 0).toUtc()));
            builder.element('D:supportedlock', nest: () {
              builder.element('D:lockentry', nest: () {
                builder.element('D:lockscope', nest: () { builder.element('D:exclusive'); });
                builder.element('D:locktype', nest: () { builder.element('D:write'); });
              });
            });
          });
          builder.element('D:status', nest: 'HTTP/1.1 200 OK');
        });
      });

      if (depth == '1' && resolved['children'] != null) {
        final children = resolved['children'] as List;
        for (final child in children) {
          final isChildDir = child['type'] == 'directory';
          final childPath = cleanPath.isEmpty ? child['name'] : '$cleanPath/${child['name']}';
          final childHref = _encodeWebDavHref(childPath, isDavWWWRoot: isDavWWWRoot, isDir: isChildDir);

          builder.element('D:response', nest: () {
            builder.element('D:href', nest: childHref);
            builder.element('D:propstat', nest: () {
              builder.element('D:prop', nest: () {
                builder.element('D:displayname', nest: child['name']);
                builder.element('b:isreadonly', nest: '0');
                builder.element('b:ishidden', nest: '0');
                builder.element('b:Win32FileAttributes', nest: isChildDir ? '00000010' : '00000020');
                if (isChildDir) {
                  builder.element('D:resourcetype', nest: () {
                    builder.element('D:collection');
                  });
                  builder.element('b:iscollection', nest: '1');
                  builder.element('D:getcontenttype', nest: 'httpd/unix-directory');
                } else {
                  builder.element('D:resourcetype');
                  builder.element('b:iscollection', nest: '0');
                  builder.element('D:getcontentlength', nest: (child['size'] ?? 0).toString());
                  final childMime = (child['mimeType'] as String?)?.isNotEmpty == true && child['mimeType'] != 'application/octet-stream'
                      ? child['mimeType'] as String
                      : _getMimeType((child['name'] as String?) ?? '');
                  builder.element('D:getcontenttype', nest: childMime);
                  builder.element('D:getetag', nest: '"${child['id']}-${child['size']}-${child['createdAt']}"');
                }
                builder.element('D:creationdate', nest: DateTime.fromMillisecondsSinceEpoch(child['createdAt'] ?? 0).toUtc().toIso8601String());
                builder.element('D:getlastmodified', nest: HttpDate.format(DateTime.fromMillisecondsSinceEpoch(child['createdAt'] ?? 0).toUtc()));
                builder.element('D:supportedlock', nest: () {
                  builder.element('D:lockentry', nest: () {
                    builder.element('D:lockscope', nest: () { builder.element('D:exclusive'); });
                    builder.element('D:locktype', nest: () { builder.element('D:write'); });
                  });
                });
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

  static Future<shelf.Response> _handleHead(shelf.Request request) async {
    final cleanPath = cleanWebDavPath(request.url.path);
    final resolved = await _sendToMain('resolve_path', {'path': cleanPath});
    if (resolved == null) {
      return shelf.Response.notFound('Not Found');
    }
    final isDir = resolved['type'] == 'directory';
    final mimeType = isDir 
        ? 'httpd/unix-directory' 
        : ((resolved['mimeType'] as String?)?.isNotEmpty == true && resolved['mimeType'] != 'application/octet-stream'
            ? resolved['mimeType'] as String
            : _getMimeType((resolved['name'] as String?) ?? ''));

    return shelf.Response.ok('', headers: {
      'Content-Type': mimeType,
      'Content-Length': isDir ? '0' : (resolved['size']?.toString() ?? '0'),
      'Accept-Ranges': 'bytes',
      'ETag': '"${resolved['id']}-${resolved['size']}-${resolved['createdAt']}"',
    });
  }

  static Future<shelf.Response> _handleGet(shelf.Request request) async {
    final cleanPath = cleanWebDavPath(request.url.path);
    final resolved = await _sendToMain('resolve_path', {'path': cleanPath});
    if (resolved == null || resolved['type'] == 'directory') {
      return shelf.Response.notFound('File Not Found');
    }

    final fileId = resolved['id'] as String;
    final fileName = (resolved['name'] as String?) ?? 'file';
    final fileSize = resolved['size'] as int? ?? 0;
    final mimeType = (resolved['mimeType'] as String?)?.isNotEmpty == true && resolved['mimeType'] != 'application/octet-stream'
        ? resolved['mimeType'] as String
        : _getMimeType(fileName);

    final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final cacheDir = Directory('$_tempDirPath${Platform.pathSeparator}aerodrive_webdav_cache');
    final cacheFile = File('${cacheDir.path}${Platform.pathSeparator}${fileId}_$safeName');
    final rangeHeader = request.headers['range'];

    // 1. If cached file exists and matches size, serve directly from disk
    if (await cacheFile.exists() && (await cacheFile.length()) == fileSize) {
      return _serveLocalFile(cacheFile, fileSize, mimeType, rangeHeader);
    }

    // 2. If StreamingServer is running, stream on-the-fly via loopback
    if (_streamingPort > 0) {
      try {
        final client = HttpClient();
        final uri = Uri.parse('http://127.0.0.1:$_streamingPort/stream?id=$fileId');
        final clientReq = await client.getUrl(uri);
        if (rangeHeader != null) {
          clientReq.headers.add('range', rangeHeader);
        }
        final clientRes = await clientReq.close();
        if (clientRes.statusCode == 200 || clientRes.statusCode == 206) {
          final responseHeaders = <String, String>{
            'Content-Type': mimeType,
            'Accept-Ranges': 'bytes',
          };
          clientRes.headers.forEach((name, values) {
            final lower = name.toLowerCase();
            if (lower == 'content-range' || lower == 'content-length' || lower == 'etag') {
              responseHeaders[name] = values.join(', ');
            }
          });

          return shelf.Response(
            clientRes.statusCode,
            body: clientRes,
            headers: responseHeaders,
          );
        }
      } catch (e) {
        AppLogger.warning('WebDavServer streaming request error: $e, falling back to direct download');
      }
    }

    // 3. Fallback: ask main thread to download and decrypt directly into cache
    try {
      final localPath = await _sendToMain('download_file', {'fileId': fileId}) as String;
      final file = File(localPath);
      if (await file.exists()) {
        final len = await file.length();
        return _serveLocalFile(file, len, mimeType, rangeHeader);
      }
    } catch (e) {
      AppLogger.error('WebDavServer download fallback error: $e');
    }

    return shelf.Response.internalServerError(body: "File could not be downloaded");
  }

  static Future<shelf.Response> _serveLocalFile(File file, int fileLength, String mimeType, String? rangeHeader) async {
    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final rangeValue = rangeHeader.substring(6).trim();
      final parts = rangeValue.split('-');
      final startStr = parts[0].trim();
      final endStr = parts.length > 1 ? parts[1].trim() : '';

      int start = 0;
      int end = fileLength - 1;

      if (startStr.isNotEmpty) {
        start = int.tryParse(startStr) ?? 0;
      }
      if (endStr.isNotEmpty) {
        end = int.tryParse(endStr) ?? (fileLength - 1);
      } else if (startStr.isEmpty && endStr.isNotEmpty) {
        final suffixLength = int.tryParse(endStr) ?? 0;
        start = fileLength - suffixLength;
        end = fileLength - 1;
      }

      if (start < 0) start = 0;
      if (end >= fileLength) end = fileLength - 1;

      if (start > end || start >= fileLength) {
        return shelf.Response(
          416, // Range Not Satisfiable
          headers: {
            'Content-Range': 'bytes */$fileLength',
            'Accept-Ranges': 'bytes',
          },
        );
      }

      final contentLength = end - start + 1;
      final stream = file.openRead(start, end + 1);

      return shelf.Response(
        206, // Partial Content
        body: stream,
        headers: {
          'Content-Type': mimeType,
          'Content-Length': contentLength.toString(),
          'Content-Range': 'bytes $start-$end/$fileLength',
          'Accept-Ranges': 'bytes',
        },
      );
    }

    // Full file response with Accept-Ranges
    return shelf.Response.ok(
      file.openRead(),
      headers: {
        'Content-Type': mimeType,
        'Content-Length': fileLength.toString(),
        'Accept-Ranges': 'bytes',
      },
    );
  }

  static String? _extractDestinationPath(shelf.Request request) {
    final destHeader = request.headers['destination'];
    if (destHeader == null) return null;
    final uri = Uri.tryParse(destHeader);
    if (uri != null) {
      return cleanWebDavPath(uri.path);
    }
    return cleanWebDavPath(destHeader);
  }

  static Future<shelf.Response> _handleMove(shelf.Request request) async {
    final sourcePath = cleanWebDavPath(request.url.path);
    final destPath = _extractDestinationPath(request);
    if (destPath == null) {
      return shelf.Response(400, body: 'Missing Destination header');
    }

    final overwrite = request.headers['overwrite']?.toUpperCase() != 'F';
    final result = await _sendToMain('move', {
      'sourcePath': sourcePath,
      'destPath': destPath,
      'overwrite': overwrite,
    });

    if (result['status'] == 'success') {
      return shelf.Response(201, body: 'Created');
    } else {
      return shelf.Response(result['code'] ?? 500, body: result['error'] ?? 'Move failed');
    }
  }

  static Future<shelf.Response> _handleCopy(shelf.Request request) async {
    final sourcePath = cleanWebDavPath(request.url.path);
    final destPath = _extractDestinationPath(request);
    if (destPath == null) {
      return shelf.Response(400, body: 'Missing Destination header');
    }

    final overwrite = request.headers['overwrite']?.toUpperCase() != 'F';
    final result = await _sendToMain('copy', {
      'sourcePath': sourcePath,
      'destPath': destPath,
      'overwrite': overwrite,
    });

    if (result['status'] == 'success') {
      return shelf.Response(201, body: 'Created');
    } else {
      return shelf.Response(result['code'] ?? 500, body: result['error'] ?? 'Copy failed');
    }
  }

  static Future<shelf.Response> _handlePut(shelf.Request request) async {
    final cleanPath = cleanWebDavPath(request.url.path);
    final fileName = cleanPath.contains('/') ? cleanPath.split('/').last : cleanPath;

    // Stage upload in a unique subfolder while keeping the real file name
    final stagingDir = Directory('$_tempDirPath${Platform.pathSeparator}webdav_stage_${const Uuid().v4()}');
    await stagingDir.create(recursive: true);
    final stagingFile = File('${stagingDir.path}${Platform.pathSeparator}$fileName');
    final sink = stagingFile.openWrite();

    await request.read().forEach((chunk) {
      sink.add(chunk);
    });
    await sink.close();

    await _sendToMain('upload_file', {
      'localPath': stagingFile.path,
      'targetPath': cleanPath,
    });

    try {
      if (await stagingDir.exists()) {
        await stagingDir.delete(recursive: true);
      }
    } catch (_) {}

    return shelf.Response(201, body: 'Created');
  }

  static Future<shelf.Response> _handleMkcol(shelf.Request request) async {
    final cleanPath = cleanWebDavPath(request.url.path);
    await _sendToMain('mkcol', {'path': cleanPath});
    return shelf.Response(201, body: 'Created');
  }

  static Future<shelf.Response> _handleDelete(shelf.Request request) async {
    final cleanPath = cleanWebDavPath(request.url.path);
    AppLogger.info('WebDavServer: _handleDelete received for "${request.url.path}" (clean="$cleanPath")');
    await _sendToMain('delete', {'path': cleanPath});
    return shelf.Response(204, body: 'No Content');
  }
}

class _WorkerParams {
  _WorkerParams({
    required this.sendPort,
    required this.creds,
    required this.tempDirPath,
    required this.streamingPort,
  });
  final SendPort sendPort;
  final WebDavCredentials creds;
  final String tempDirPath;
  final int streamingPort;
}
