import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tdlib/tdlib.dart';
import 'package:uuid/uuid.dart';

import '../../core/logger.dart';

enum TelegramAuthState {
  initial,
  waitPhoneNumber,
  waitCode,
  waitPassword,
  ready,
  loggingOut,
  closed,
  error,
}

class TelegramInitDebugInfo {
  final String currentStep;
  final String lastEvent;
  final List<String> pendingRequests;
  final String? lastError;

  TelegramInitDebugInfo({
    this.currentStep = 'Not started',
    this.lastEvent = 'None',
    this.pendingRequests = const [],
    this.lastError,
  });

  TelegramInitDebugInfo copyWith({
    String? currentStep,
    String? lastEvent,
    List<String>? pendingRequests,
    String? lastError,
  }) {
    return TelegramInitDebugInfo(
      currentStep: currentStep ?? this.currentStep,
      lastEvent: lastEvent ?? this.lastEvent,
      pendingRequests: pendingRequests ?? this.pendingRequests,
      lastError: lastError ?? this.lastError,
    );
  }
}

class TelegramService extends StateNotifier<TelegramAuthState> {
  TelegramService({this.accountId = 'primary', this.isHeadless = false}) : super(TelegramAuthState.initial) {
    _initClient();
  }

  final debugInfo = ValueNotifier<TelegramInitDebugInfo>(TelegramInitDebugInfo());
  final Map<String, String> _pendingRequestTypes = {};

  void _updateDebugStep(String step) {
    debugInfo.value = debugInfo.value.copyWith(currentStep: step);
  }

  void _updateDebugLastEvent(String event) {
    debugInfo.value = debugInfo.value.copyWith(lastEvent: event);
  }

  void _updateDebugPendingRequests() {
    debugInfo.value = debugInfo.value.copyWith(
      pendingRequests: _pendingRequestTypes.values.toList(),
    );
  }

  void _updateDebugError(String? error) {
    debugInfo.value = debugInfo.value.copyWith(lastError: error);
  }

  final String accountId;
  final bool isHeadless;
  int _clientId = 0;
  int get clientId => _clientId;
  
  static bool _globalLoopStarted = false;
  static bool _tdlibInitialized = false;
  static final Completer<void> _tdlibInitCompleter = Completer<void>();
  static final Map<int, TelegramService> _instances = {};
  
  int _apiId = 0;
  String _apiHash = '';
  String _dbPath = '';

  int? userId;
  String? firstName;
  String? lastName;
  String? phoneNumber;
  String? photoPath;
  String? username;
  String? passwordHint;
  bool hasRecoveryEmail = false;
  int? _photoFileId;
  
  VoidCallback? onProfileUpdated;
  VoidCallback? onReady;

  String get displayName {
    final name = '${firstName ?? ''} ${lastName ?? ''}'.trim();
    if (name.isNotEmpty) return name;
    if (phoneNumber != null && phoneNumber!.isNotEmpty) return phoneNumber!;
    return accountId == 'primary' ? 'Main Account' : 'Secondary Account';
  }

  Future<void> _initClient() async {
    _updateDebugStep('Loading credentials from .env');
    final apiIdStr = dotenv.env['TELEGRAM_API_ID'];
    final apiHash = dotenv.env['TELEGRAM_API_HASH'];

    if (apiIdStr == null || apiIdStr.isEmpty) {
      AppLogger.error('Missing or empty TELEGRAM_API_ID in .env');
      _updateDebugError('Missing or empty TELEGRAM_API_ID in .env');
      state = TelegramAuthState.error;
      return;
    }
    if (apiHash == null || apiHash.isEmpty) {
      AppLogger.error('Missing or empty TELEGRAM_API_HASH in .env');
      _updateDebugError('Missing or empty TELEGRAM_API_HASH in .env');
      state = TelegramAuthState.error;
      return;
    }

    final parsedId = int.tryParse(apiIdStr);
    if (parsedId == null) {
      AppLogger.error('TELEGRAM_API_ID is not a valid integer: $apiIdStr');
      _updateDebugError('TELEGRAM_API_ID is not a valid integer: $apiIdStr');
      state = TelegramAuthState.error;
      return;
    }
    _apiId = parsedId;
    _apiHash = apiHash;

    try {
      _updateDebugStep('Retrieving application documents directory');
      final docDir = await getApplicationDocumentsDirectory();
      _dbPath = '${docDir.path}/AeroDrive/tdlib/$accountId';

      // Ensure TDLib database directory exists before any TDLib calls
      _updateDebugStep('Creating TDLib database directory: $_dbPath');
      final dbDirectory = Directory(_dbPath);
      if (!await dbDirectory.exists()) {
        await dbDirectory.create(recursive: true);
      }
      AppLogger.info('TDLib db path ($accountId): $_dbPath');

      if (!_tdlibInitialized) {
        if (_tdlibInitCompleter.isCompleted) {
          _tdlibInitialized = true;
        } else {
          try {
            _updateDebugStep('Initializing TdPlugin dynamic library (${Platform.operatingSystem})');
            if (Platform.isWindows) {
              await TdPlugin.initialize('tdjson.dll');
            } else if (Platform.isAndroid) {
              await TdPlugin.initialize('libtdjson.so');
            } else if (Platform.isLinux) {
              await TdPlugin.initialize('libtdjson.so');
            } else if (Platform.isIOS) {
              await TdPlugin.initialize();
            } else if (Platform.isMacOS) {
              await TdPlugin.initialize();
            } else {
              await TdPlugin.initialize();
            }
            _tdlibInitialized = true;
            if (!_tdlibInitCompleter.isCompleted) {
              _tdlibInitCompleter.complete();
            }
            AppLogger.info('TdPlugin initialized successfully');
          } catch (e, s) {
            if (!_tdlibInitCompleter.isCompleted) {
              _tdlibInitCompleter.completeError(e, s);
            }
            AppLogger.error('TdPlugin.initialize failed', e, s);
            _updateDebugError('TdPlugin.initialize failed: $e');
            state = TelegramAuthState.error;
            return;
          }
        }
      } else {
        // Wait for any concurrent initialization to finish
        if (!_tdlibInitCompleter.isCompleted) {
          _updateDebugStep('Waiting for concurrent TdPlugin initialization');
          await _tdlibInitCompleter.future;
        }
      }

      try {
        _updateDebugStep('Creating TDLib client instance (tdCreate)');
        _clientId = TdPlugin.instance.tdCreate();
        _instances[_clientId] = this;
        AppLogger.info('TDLib client created for $accountId (clientId: $_clientId)');
      } catch (e, s) {
        AppLogger.error('tdCreate failed for $accountId', e, s);
        _updateDebugError('tdCreate failed: $e');
        state = TelegramAuthState.error;
        return;
      }

      if (isHeadless) {
        _updateDebugStep('Applying headless options configuration');
        TdPlugin.instance.tdSend(_clientId, jsonEncode({
          "@type": "setOption",
          "name": "online",
          "value": {"@type": "optionValueBoolean", "value": false}
        }));
        TdPlugin.instance.tdSend(_clientId, jsonEncode({
          "@type": "setOption",
          "name": "disable_network_statistics",
          "value": {"@type": "optionValueBoolean", "value": true}
        }));
        TdPlugin.instance.tdSend(_clientId, jsonEncode({
          "@type": "setOption",
          "name": "disable_contact_registered_notifications",
          "value": {"@type": "optionValueBoolean", "value": true}
        }));
        AppLogger.info('Headless options set for $accountId');
      }

      TdPlugin.instance.tdSend(_clientId, jsonEncode({
        "@type": "setLogVerbosityLevel",
        "new_verbosity_level": 1
      }));

      if (!_globalLoopStarted) {
        _updateDebugStep('Starting global TDLib receive loop');
        _startGlobalLoop();
      }

      _updateDebugStep('Initialization completed. Waiting for TDLib events.');
      AppLogger.info('_initClient completed for $accountId');
    } catch (e, s) {
      AppLogger.error('Failed to initialize TDLib for $accountId', e, s);
      _updateDebugError('Failed to initialize: $e');
      state = TelegramAuthState.error;
    }
  }

  static Future<void> _startGlobalLoop() async {
    _globalLoopStarted = true;
    var idleCycles = 0;
    while (true) {
      String? rawStr;
      try {
        rawStr = TdPlugin.instance.tdReceive(0.01);
      } catch (e) {
        AppLogger.error('tdReceive error', e);
        await Future.delayed(const Duration(milliseconds: 100));
        continue;
      }
      
      if (rawStr != null) {
        idleCycles = 0;
        try {
          final json = jsonDecode(rawStr);
          final rawClientId = json['@client_id'];
          final int? clientId = rawClientId is int
              ? rawClientId
              : (rawClientId is num
                  ? rawClientId.toInt()
                  : (rawClientId is String ? int.tryParse(rawClientId) : null));

          if (clientId != null && _instances.containsKey(clientId)) {
            _instances[clientId]!._processEvent(json);
          } else if (clientId == null && _instances.length == 1) {
            _instances.values.first._processEvent(json);
          }
        } catch (e) {
          AppLogger.error('Failed to parse TDLib JSON', e);
        }
        await Future.delayed(const Duration(milliseconds: 5));
      } else {
        idleCycles++;
        // Exponential backoff when idle: 10ms -> 50ms -> 100ms -> 200ms -> 500ms max
        final int delayMs;
        if (idleCycles <= 1) {
          delayMs = 10;
        } else if (idleCycles <= 5) {
          delayMs = 50;
        } else if (idleCycles <= 20) {
          delayMs = 100;
        } else {
          delayMs = 500;
        }
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
  }

  void _processEvent(Map<String, dynamic> json) {
    final type = json['@type'] as String? ?? 'Unknown';
    _updateDebugLastEvent(type);
    _eventController.add(json);

    final extra = json['@extra'];
    if (extra != null && _pendingRequests.containsKey(extra)) {
      if (type == 'error') {
        _pendingRequests[extra]!.completeError(json);
      } else {
        _pendingRequests[extra]!.complete(json);
      }
      _pendingRequests.remove(extra);
    }

    if (type == 'updateAuthorizationState') {
      final authState = json['authorization_state']['@type'];
      AppLogger.info('TDLib Auth State ($accountId): $authState');
      _updateDebugStep('Auth State Update: $authState');
      
      if (authState == 'authorizationStateWaitTdlibParameters') {
        _updateDebugStep('Sending TDLib parameters (setTdlibParameters)');
        TdPlugin.instance.tdSend(_clientId, jsonEncode({
          "@type": "setTdlibParameters",
          "use_test_dc": false,
          "database_directory": _dbPath,
          "files_directory": _dbPath,
          "use_file_database": true,
          "use_chat_info_database": !isHeadless,
          "use_message_database": !isHeadless,
          "use_secret_chats": false,
          "api_id": _apiId,
          "api_hash": _apiHash,
          "system_language_code": "en",
          "device_model": "AeroDrive Desktop",
          "system_version": "1.0",
          "application_version": "1.0",
          "enable_storage_optimizer": true,
          "ignore_file_names": isHeadless,
        }));
      } else if (authState == 'authorizationStateWaitEncryptionKey') {
        _updateDebugStep('Sending database encryption key (checkDatabaseEncryptionKey)');
        TdPlugin.instance.tdSend(_clientId, jsonEncode({
          "@type": "checkDatabaseEncryptionKey",
          "encryption_key": ""
        }));
      } else if (authState == 'authorizationStateWaitPhoneNumber') {
        _updateDebugStep('Waiting for user phone number input');
        state = TelegramAuthState.waitPhoneNumber;
      } else if (authState == 'authorizationStateWaitCode') {
        _updateDebugStep('Waiting for Telegram verification code');
        state = TelegramAuthState.waitCode;
      } else if (authState == 'authorizationStateWaitPassword') {
        _updateDebugStep('Waiting for 2FA password');
        final authStateData = json['authorization_state'] as Map<String, dynamic>?;
        passwordHint = authStateData?['password_hint'] as String?;
        hasRecoveryEmail = authStateData?['has_recovery_email_address'] == true;
        state = TelegramAuthState.waitPassword;
      } else if (authState == 'authorizationStateReady') {
        _updateDebugStep('TDLib Ready. Fetching current user details (getMe)');
        _fetchMe().whenComplete(() {
          _updateDebugStep('User details loaded. AeroDrive Ready.');
          state = TelegramAuthState.ready;
          onReady?.call();
        });
      } else if (authState == 'authorizationStateLoggingOut') {
        _updateDebugStep('Logging out of Telegram...');
        state = TelegramAuthState.loggingOut;
      } else if (authState == 'authorizationStateClosed') {
        _updateDebugStep('TDLib connection closed');
        state = TelegramAuthState.closed;
      }
    } else if (type == 'error') {
      final errorMsg = json['message'] as String? ?? 'Unknown TDLib error';
      AppLogger.error('TDLib Error ($accountId): $errorMsg');
      _updateDebugError(errorMsg);
    } else if (type == 'updateFile') {
      final file = json['file'];
      if (file != null && _photoFileId != null && file['id'] == _photoFileId) {
        final local = file['local'];
        if (local != null && local['is_downloading_completed'] == true && local['path'] != null && (local['path'] as String).isNotEmpty) {
          photoPath = local['path'];
          onProfileUpdated?.call();
        }
      }
    } else if (type == 'updateNewChat' && !isHeadless) {
      final chat = json['chat'];
      final chatType = chat['type']['@type'];
      if (chatType == 'chatTypeBasicGroup' || chatType == 'chatTypeSupergroup') {
        if (!chats.any((c) => c['id'] == chat['id'])) {
          chats = List.from(chats)..add(chat);
          // Removed premature state = TelegramAuthState.ready;
        }
      }
    }
  }

  Future<void> setAuthenticationPhoneNumber(String phoneNumber) async {
    this.phoneNumber = phoneNumber;
    await sendRequest({
      "@type": "setAuthenticationPhoneNumber",
      "phone_number": phoneNumber,
      "settings": {
        "@type": "phoneNumberAuthenticationSettings",
        "allow_flash_call": false,
        "allow_missed_call": false,
        "is_current_phone_number": false,
        "allow_sms_retriever_api": false
      }
    });
  }

  Future<void> checkAuthenticationCode(String code) async {
    await sendRequest({
      "@type": "checkAuthenticationCode",
      "code": code
    });
  }

  Future<void> checkAuthenticationPassword(String password) async {
    await sendRequest({
      "@type": "checkAuthenticationPassword",
      "password": password
    });
  }

  List<Map<String, dynamic>> chats = [];

  Future<Map<String, dynamic>> loadChats() async => sendRequest({
      "@type": "loadChats",
      "chat_list": {"@type": "chatListMain"},
      "limit": 500
    });

  Future<Map<String, dynamic>> createNewChannel(String title, String description) async => sendRequest({
      "@type": "createNewSupergroupChat",
      "title": title,
      "is_channel": true,
      "description": description,
      "for_import": false
    });

  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests = {};
  
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get tdlibEvents => _eventController.stream;

  Future<Map<String, dynamic>> sendRequest(Map<String, dynamic> request, {Duration timeout = const Duration(seconds: 30), int maxRetries = 3}) async {
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      final requestId = const Uuid().v4();
      final completer = Completer<Map<String, dynamic>>();
      _pendingRequests[requestId] = completer;

      request['@extra'] = requestId;
      _pendingRequestTypes[requestId] = request['@type'] as String? ?? 'unknown';
      _updateDebugPendingRequests();
      
      TdPlugin.instance.tdSend(_clientId, jsonEncode(request));

      try {
        final result = await completer.future.timeout(timeout, onTimeout: () {
          throw TimeoutException('TDLib request timed out: ${request['@type']}');
        });
        return result;
      } catch (e) {
        // Check if this is a 429 FloodWait error
        if (e is Map && e['@type'] == 'error') {
          final code = e['code'] as int?;
          if (code == 429) {
            final retryAfter = (e['retry_after'] as num?)?.toInt() ?? 5;
            final backoff = retryAfter * (attempt + 1);
            AppLogger.warning('FloodWait 429 for ${request['@type']}, retrying in ${backoff}s (attempt ${attempt + 1}/$maxRetries)');
            await Future.delayed(Duration(seconds: backoff));
            continue;
          }
        }

        // For TimeoutException, retry with exponential backoff
        if (e is TimeoutException) {
          if (attempt < maxRetries - 1) {
            final backoff = Duration(seconds: 2 * (attempt + 1));
            AppLogger.warning('Timeout for ${request['@type']}, retrying in ${backoff.inSeconds}s (attempt ${attempt + 1}/$maxRetries)');
            await Future.delayed(backoff);
            continue;
          }
        }

        rethrow;
      } finally {
        _pendingRequests.remove(requestId);
        _pendingRequestTypes.remove(requestId);
        _updateDebugPendingRequests();
      }
    }
    throw TimeoutException('TDLib request failed after $maxRetries retries: ${request['@type']}');
  }

  Future<Map<String, dynamic>> getMe() async => sendRequest({"@type": "getMe"});

  Future<Map<String, dynamic>> getChatMember(int chatId, int userId) async => sendRequest({
      "@type": "getChatMember",
      "chat_id": chatId,
      "member_id": {
        "@type": "messageSenderUser",
        "user_id": userId
      }
    });

  Future<Map<String, dynamic>> searchPublicChat(String username) async => sendRequest({
      "@type": "searchPublicChat",
      "username": username
    });

  Future<Map<String, dynamic>> checkAdminStatus(dynamic chatId) async {
    final int id = chatId is String ? int.parse(chatId) : chatId;
    try {
      final me = await getMe();
      if (!me.containsKey('id')) return {"is_admin": false};
      final userId = me['id'];
      
      final member = await getChatMember(id, userId);
      final status = member['status']?['@type'];
      final bool isAdmin = (status == 'chatMemberStatusCreator' || status == 'chatMemberStatusAdministrator');
      return {"is_admin": isAdmin, "chat_id": id};
    } catch (e) {
      return {"is_admin": false, "error": e.toString()};
    }
  }

  /// Sets the description of a chat (used for cross-device salt sharing).
  Future<void> setChatDescription(int chatId, String description) async {
    await sendRequest({
      '@type': 'setChatDescription',
      'chat_id': chatId,
      'description': description,
    });
  }

  /// Sets the title of a chat or channel.
  Future<void> setChatTitle(int chatId, String title) async {
    await sendRequest({
      '@type': 'setChatTitle',
      'chat_id': chatId,
      'title': title,
    });
  }

  /// Reads the description of a supergroup or channel.
  Future<String?> getChannelDescription(int chatId) async {
    try {
      final chat = await sendRequest({'@type': 'getChat', 'chat_id': chatId});
      if (chat['type']?['@type'] != 'chatTypeSupergroup') return null;
      final supergroupId = chat['type']['supergroup_id'] as int;
      final info = await sendRequest({
        '@type': 'getSupergroupFullInfo',
        'supergroup_id': supergroupId,
      });
      return info['description'] as String?;
    } catch (e) {
      AppLogger.error('getChannelDescription failed', e);
      return null;
    }
  }

  /// Groups AeroDrive connected channels into a Telegram Chat Folder named 'AeroDrive'.
  Future<void> updateTelegramFolder(List<int> chatIds) async {
    try {
      // 1. Get all chat folders (TDLib API: getChatFolders, not deprecated getChatFilters)
      final foldersResponse = await sendRequest({"@type": "getChatFolders"});
      final folders = foldersResponse['chat_folders'] as List<dynamic>? ?? [];
      
      int? aeroDriveFolderId;
      Map<String, dynamic>? existingFolder;
      
      for (final f in folders) {
        if (f['title'] == 'AeroDrive') {
          aeroDriveFolderId = f['id'] as int?;
          break;
        }
      }
      
      // If folder exists, retrieve its full details
      if (aeroDriveFolderId != null) {
        final folderDetail = await sendRequest({
          "@type": "getChatFolder",
          "chat_folder_id": aeroDriveFolderId,
        });
        if (folderDetail['@type'] != 'error') {
          existingFolder = folderDetail;
        }
      }
      
      final Set<int> targetChatIds = chatIds.toSet();
      
      if (existingFolder != null) {
        // Update existing folder
        final List<dynamic> included = List.from(existingFolder['included_chat_ids'] ?? []);
        final Set<int> currentIncluded = included.map((e) => e as int).toSet();
        
        // Add new ones
        currentIncluded.addAll(targetChatIds);
        
        final response = await sendRequest({
          "@type": "editChatFolder",
          "chat_folder_id": aeroDriveFolderId,
          "folder": {
            "@type": "chatFolder",
            "title": "AeroDrive",
            "icon_name": existingFolder['icon_name'] ?? "Folder",
            "pinned_chat_ids": existingFolder['pinned_chat_ids'] ?? [],
            "included_chat_ids": currentIncluded.toList(),
            "excluded_chat_ids": existingFolder['excluded_chat_ids'] ?? [],
            "exclude_muted": existingFolder['exclude_muted'] ?? false,
            "exclude_read": existingFolder['exclude_read'] ?? false,
            "exclude_archived": existingFolder['exclude_archived'] ?? false,
            "include_contacts": existingFolder['include_contacts'] ?? false,
            "include_non_contacts": existingFolder['include_non_contacts'] ?? false,
            "include_groups": existingFolder['include_groups'] ?? false,
            "include_channels": existingFolder['include_channels'] ?? false,
            "include_bots": existingFolder['include_bots'] ?? false,
          }
        });
        if (response['@type'] == 'error') {
          AppLogger.error('Failed to edit AeroDrive Chat Folder: ${response['message']}');
        } else {
          AppLogger.info('Updated Telegram folder AeroDrive successfully');
        }
      } else {
        // Create new folder
        final response = await sendRequest({
          "@type": "createChatFolder",
          "folder": {
            "@type": "chatFolder",
            "title": "AeroDrive",
            "icon_name": "Folder",
            "pinned_chat_ids": [],
            "included_chat_ids": targetChatIds.toList(),
            "excluded_chat_ids": [],
            "exclude_muted": false,
            "exclude_read": false,
            "exclude_archived": false,
            "include_contacts": false,
            "include_non_contacts": false,
            "include_groups": false,
            "include_channels": false,
            "include_bots": false,
          }
        });
        if (response['@type'] == 'error') {
          AppLogger.error('Failed to create AeroDrive Chat Folder: ${response['message']}');
        } else {
          AppLogger.info('Created Telegram folder AeroDrive successfully');
        }
      }
    } catch (e, s) {
      AppLogger.error('Failed to update Telegram folder AeroDrive', e, s);
    }
  }

  Future<Map<String, dynamic>?> verifyChannel(String input) async {
    final String trimmedInput = input.trim();
    if (trimmedInput.startsWith('@')) {
      try {
        final chat = await searchPublicChat(trimmedInput.substring(1));
        if (chat.containsKey('id')) {
          final chatId = chat['id'];
          final adminCheck = await checkAdminStatus(chatId);
          if (adminCheck['is_admin'] == true) {
            return await sendRequest({"@type": "getChat", "chat_id": chatId});
          }
        }
      } catch (e) {
        return null; // not found or not admin
      }
      return null;
    } else {
      // Numeric ID logic
      final int? firstTryId = int.tryParse(trimmedInput);
      if (firstTryId == null) return null;

      try {
        final chat = await sendRequest({"@type": "getChat", "chat_id": firstTryId});
        final adminCheck = await checkAdminStatus(firstTryId);
        if (adminCheck['is_admin'] == true) {
          return chat;
        }
      } catch (e) {
        // Fallback: prepend -100 if it doesn't already start with -100
        if (!trimmedInput.startsWith('-100')) {
          final prefixedStr = trimmedInput.startsWith('-') 
              ? '-100${trimmedInput.substring(1)}' 
              : '-100$trimmedInput';
          
          final int? secondTryId = int.tryParse(prefixedStr);
          if (secondTryId != null) {
            try {
              final chat2 = await sendRequest({"@type": "getChat", "chat_id": secondTryId});
              final adminCheck2 = await checkAdminStatus(secondTryId);
              if (adminCheck2['is_admin'] == true) {
                return chat2;
              }
            } catch (e2) {
              return null;
            }
          }
        }
      }
      return null;
    }
  }



  Future<Map<String, dynamic>> getMessage(int chatId, int messageId) async => sendRequest({
      "@type": "getMessage",
      "chat_id": chatId,
      "message_id": messageId,
    });

  Future<Map<String, dynamic>> getMessages(int chatId, List<int> messageIds) async => sendRequest({
      "@type": "getMessages",
      "chat_id": chatId,
      "message_ids": messageIds,
    });

  Future<void> openChat(int chatId) async {
    try {
      await sendRequest({
        "@type": "openChat",
        "chat_id": chatId,
      });
    } catch (e) {
      AppLogger.warning('openChat failed for chatId $chatId: $e');
    }
  }

  Future<void> closeChat(int chatId) async {
    try {
      await sendRequest({
        "@type": "closeChat",
        "chat_id": chatId,
      });
    } catch (_) {}
  }

  Future<void> downloadFile(int fileId) async {
    await sendRequest({
      "@type": "downloadFile",
      "file_id": fileId,
      "priority": 1,
      "offset": 0,
      "limit": 0,
      "synchronous": false
    });
  }

  Future<Map<String, dynamic>> uploadDocument(int chatId, String localFilePath, {String? caption}) async {
    final inputContent = <String, dynamic>{
      "@type": "inputMessageDocument",
      "document": {
        "@type": "inputFileLocal",
        "path": localFilePath,
      },
      "disable_content_type_detection": true,
    };

    if (caption != null) {
      inputContent["caption"] = {
        "@type": "formattedText",
        "text": caption,
        "entities": <dynamic>[],
      };
    }

    final payload = <String, dynamic>{
      "@type": "sendMessage",
      "chat_id": chatId,
      "input_message_content": inputContent,
    };

    final payloadJson = jsonEncode(payload);
    AppLogger.info('=== TDLib sendMessage PAYLOAD ===');
    AppLogger.info('ChatId: $chatId');
    AppLogger.info('LocalFile: $localFilePath');
    AppLogger.info('HasCaption: ${caption != null}');
    if (caption != null) {
      AppLogger.info('Caption length: ${caption.length} chars');
    } else {
      AppLogger.warning('>>> CAPTION IS NULL - Manifest will be MISSING from Telegram message!');
    }
    AppLogger.info('Full Payload JSON: $payloadJson');

    return sendRequest(payload, timeout: const Duration(hours: 6));
  }

  Future<Map<String, dynamic>> uploadPhoto(int chatId, String localFilePath, {String? caption}) async {
    final inputContent = <String, dynamic>{
      "@type": "inputMessagePhoto",
      "photo": {
        "@type": "inputFileLocal",
        "path": localFilePath,
      },
    };

    if (caption != null) {
      inputContent["caption"] = {
        "@type": "formattedText",
        "text": caption,
        "entities": <dynamic>[],
      };
    }

    final payload = <String, dynamic>{
      "@type": "sendMessage",
      "chat_id": chatId,
      "input_message_content": inputContent,
    };

    return sendRequest(payload);
  }

  Future<void> addProxy({
    required String server,
    required int port,
    String? username,
    String? password,
    String? secret, // For MTProto
    bool enable = true,
  }) async {
    final Map<String, dynamic> proxyType;
    if (secret != null && secret.isNotEmpty) {
      proxyType = {
        "@type": "proxyTypeMtproto",
        "secret": secret
      };
    } else {
      proxyType = {
        "@type": "proxyTypeSocks5",
        "username": username ?? "",
        "password": password ?? ""
      };
    }

    TdPlugin.instance.tdSend(_clientId, jsonEncode({
      "@type": "addProxy",
      "server": server,
      "port": port,
      "enable": enable,
      "type": proxyType
    }));
  }

  Future<void> disableProxy(int proxyId) async {
    TdPlugin.instance.tdSend(_clientId, jsonEncode({
      "@type": "disableProxy"
    }));
  }

  Future<void> logOut() async {
    state = TelegramAuthState.loggingOut;
    TdPlugin.instance.tdSend(_clientId, jsonEncode({
      "@type": "logOut"
    }));
  }

  Future<void> _fetchMe() async {
    try {
      final me = await getMe();
      userId = me['id'];
      firstName = me['first_name'];
      lastName = me['last_name'];
      phoneNumber = me['phone_number'];
      username = me['username'];
      
      final profilePhoto = me['profile_photo'];
      if (profilePhoto != null) {
        final smallFile = profilePhoto['small'];
        if (smallFile != null) {
          _photoFileId = smallFile['id'];
          final local = smallFile['local'];
          if (local != null && local['is_downloading_completed'] == true && local['path'] != null && (local['path'] as String).isNotEmpty) {
            photoPath = local['path'];
          } else {
            await downloadFile(_photoFileId!);
          }
        }
      }
      onProfileUpdated?.call();
    } catch (e, s) {
      AppLogger.error('Failed to fetch user info for $accountId', e, s);
    }
  }

  Future<void> closeClient() async {
    if (state == TelegramAuthState.closed) return;
    TdPlugin.instance.tdSend(_clientId, jsonEncode({
      "@type": "close"
    }));
    var attempts = 0;
    while (state != TelegramAuthState.closed && attempts < 30) {
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }
  }

  Future<void> addAdminToChat(int chatId, int targetUserId) async {
    try {
      await sendRequest({
        "@type": "addChatMember",
        "chat_id": chatId,
        "user_id": targetUserId,
        "forward_limit": 0
      });
    } catch (e) {
      AppLogger.info('addChatMember failed or user already in chat: $e');
    }

    await sendRequest({
      "@type": "setChatMemberStatus",
      "chat_id": chatId,
      "member_id": {
        "@type": "messageSenderUser",
        "user_id": targetUserId
      },
      "status": {
        "@type": "chatMemberStatusAdministrator",
        "custom_title": "AeroDrive Agent",
        "can_be_edited": true,
        "rights": {
          "@type": "chatAdministratorRights",
          "can_manage_chat": true,
          "can_post_messages": true,
          "can_edit_messages": true,
          "can_delete_messages": true,
          "can_invite_users": true,
          "can_restrict_members": true,
          "can_pin_messages": true,
          "can_promote_members": false,
          "can_manage_video_chats": true,
          "can_post_stories": true,
          "can_edit_stories": true,
          "can_delete_stories": true
        }
      }
    });
  }

  Future<Map<String, dynamic>> getActiveSessions() async => sendRequest({
      "@type": "getActiveSessions",
    });

  Future<Map<String, dynamic>> terminateSession(dynamic sessionId) async => sendRequest({
      "@type": "terminateSession",
      "session_id": sessionId is String ? int.parse(sessionId) : sessionId,
    });

  Future<Map<String, dynamic>> terminateAllOtherSessions() async => sendRequest({
      "@type": "terminateAllOtherSessions",
    });

  Future<List<Map<String, dynamic>>> getAdminChannels() async {
    try {
      await loadChats();
    } catch (_) {
      // Ignored if already loading/loaded
    }
    await Future.delayed(const Duration(milliseconds: 200));

    try {
      final List<dynamic> allChatIds = [];

      // Query Main Chat List
      try {
        final mainResponse = await sendRequest({
          "@type": "getChats",
          "chat_list": {"@type": "chatListMain"},
          "limit": 200,
        });
        if (mainResponse.containsKey('chat_ids')) {
          allChatIds.addAll(mainResponse['chat_ids']);
        }
      } catch (e) {
        AppLogger.warning('Failed to get Main chats: $e');
      }

      // Query Archive Chat List
      try {
        final archiveResponse = await sendRequest({
          "@type": "getChats",
          "chat_list": {"@type": "chatListArchive"},
          "limit": 200,
        });
        if (archiveResponse.containsKey('chat_ids')) {
          allChatIds.addAll(archiveResponse['chat_ids']);
        }
      } catch (e) {
        // Safe to ignore if archive is empty or fails
      }

      final uniqueChatIds = allChatIds.toSet().toList();

      final List<Map<String, dynamic>> adminChannels = [];
      for (final id in uniqueChatIds) {
        try {
          final chat = await sendRequest({
            "@type": "getChat",
            "chat_id": id,
          });

          final chatType = chat['type'];
          if (chatType != null && chatType['@type'] == 'chatTypeSupergroup') {
            final isChannel = chatType['is_channel'] ?? false;
            if (isChannel) {
              final supergroupId = chatType['supergroup_id'];
              final sg = await sendRequest({
                "@type": "getSupergroup",
                "supergroup_id": supergroupId,
              });
              final statusType = sg['status']?['@type'];
              if (statusType == 'chatMemberStatusCreator' || statusType == 'chatMemberStatusAdministrator') {
                adminChannels.add(chat);
              }
            }
          }
        } catch (e) {
          // Ignore error for a single chat
        }
      }
      return adminChannels;
    } catch (e, s) {
      AppLogger.error('Failed to get chats from TDLib', e, s);
      return [];
    }
  }

  /// Resets the entire Telegram authentication flow for this account.
  /// This is a major operation that removes all associated session data.
  /// Typically called when a user wants to log out completely or when
  /// authentication becomes corrupted.
  Future<void> resetAuthFlow() async {
    // Only proceed if we have an active client to clean up.
    // If already in initial state with no client, skip to avoid
    // re-initializing a fresh instance (which causes late field errors).
    if (_clientId == 0 && state == TelegramAuthState.initial) {
      return;
    }

    AppLogger.info('Resetting auth flow for account: $accountId');
    closeClient();

    // Remove instance from map
    if (_clientId != 0) {
      _instances.remove(_clientId);
      _clientId = 0;
    }

    // Clear local cache variables
    userId = null;
    firstName = null;
    lastName = null;
    phoneNumber = null;
    photoPath = null;
    username = null;
    passwordHint = null;
    hasRecoveryEmail = false;
    _photoFileId = null;
    chats.clear();

    // Reinitialize client
    state = TelegramAuthState.initial;
    await _initClient();
  }

  TelegramAuthState get authState => state;

  @override
  void dispose() {
    _instances.remove(_clientId);
    _eventController.close();
    if (_clientId != 0) {
      TdPlugin.instance.tdSend(_clientId, jsonEncode({
        "@type": "close"
      }));
    }
    super.dispose();
  }
}

final telegramServiceProvider = StateNotifierProvider<TelegramService, TelegramAuthState>((ref) => TelegramService());


