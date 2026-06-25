import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdlib/td_api.dart' as td_api;
import 'package:tdlib/tdlib.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';

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

class TelegramService extends StateNotifier<TelegramAuthState> {
  TelegramService({this.accountId = 'primary', this.isHeadless = false}) : super(TelegramAuthState.initial) {
    _initClient();
  }

  final String accountId;
  final bool isHeadless;
  int _clientId = 0;
  
  static bool _globalLoopStarted = false;
  static final Map<int, TelegramService> _instances = {};
  
  late final int _apiId;
  late final String _apiHash;
  late final String _dbPath;

  int? userId;
  String? firstName;
  String? lastName;
  String? phoneNumber;
  String? photoPath;
  String? username;
  int? _photoFileId;
  
  VoidCallback? onProfileUpdated;

  String get displayName {
    final name = '${firstName ?? ''} ${lastName ?? ''}'.trim();
    if (name.isNotEmpty) return name;
    if (phoneNumber != null && phoneNumber!.isNotEmpty) return phoneNumber!;
    return accountId == 'primary' ? 'Main Account' : 'Secondary Account';
  }

  Future<void> _initClient() async {
    final apiIdStr = dotenv.env['TELEGRAM_API_ID'];
    final apiHash = dotenv.env['TELEGRAM_API_HASH'];

    if (apiIdStr == null || apiHash == null) {
      AppLogger.error('Missing TELEGRAM_API_ID or TELEGRAM_API_HASH');
      state = TelegramAuthState.error;
      return;
    }

    _apiId = int.parse(apiIdStr);
    _apiHash = apiHash;

    try {
      final docDir = await getApplicationDocumentsDirectory();
      _dbPath = '${docDir.path}/AeroDrive/tdlib/$accountId';

      if (Platform.isWindows) {
        await TdPlugin.initialize('tdjson.dll');
      } else if (Platform.isAndroid || Platform.isLinux) {
        await TdPlugin.initialize('libtdjson.so');
      } else {
        await TdPlugin.initialize();
      }

      _clientId = tdCreate();
      _instances[_clientId] = this;

      if (isHeadless) {
        // Headless options
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
      }

      // Disable TDLib console logs
      TdPlugin.instance.tdSend(_clientId, jsonEncode({
        "@type": "setLogVerbosityLevel",
        "new_verbosity_level": 1
      }));

      if (!_globalLoopStarted) {
        _startGlobalLoop();
      }

    } catch (e, s) {
      AppLogger.error('Failed to initialize TDLib for $accountId', e, s);
      state = TelegramAuthState.error;
    }
  }

  static void _startGlobalLoop() async {
    _globalLoopStarted = true;
    while (true) {
      final rawStr = TdPlugin.instance.tdReceive(0.01);
      
      if (rawStr != null) {
        try {
          final json = jsonDecode(rawStr);
          final clientId = json['@client_id'];
          if (clientId != null && _instances.containsKey(clientId)) {
            _instances[clientId]!._processEvent(json);
          }
        } catch (e) {
          AppLogger.error('Failed to parse TDLib JSON', e);
        }
      }
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  void _processEvent(Map<String, dynamic> json) {
    final type = json['@type'];
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
      
      if (authState == 'authorizationStateWaitTdlibParameters') {
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
        TdPlugin.instance.tdSend(_clientId, jsonEncode({
          "@type": "checkDatabaseEncryptionKey",
          "encryption_key": ""
        }));
      } else if (authState == 'authorizationStateWaitPhoneNumber') {
        state = TelegramAuthState.waitPhoneNumber;
      } else if (authState == 'authorizationStateWaitCode') {
        state = TelegramAuthState.waitCode;
      } else if (authState == 'authorizationStateWaitPassword') {
        state = TelegramAuthState.waitPassword;
      } else if (authState == 'authorizationStateReady') {
        state = TelegramAuthState.ready;
        _fetchMe();
      } else if (authState == 'authorizationStateLoggingOut') {
        state = TelegramAuthState.loggingOut;
      } else if (authState == 'authorizationStateClosed') {
        state = TelegramAuthState.closed;
      }
    } else if (type == 'error') {
      AppLogger.error('TDLib Error ($accountId): ${json['message']}');
      if (state == TelegramAuthState.initial) {
        state = TelegramAuthState.error;
      }
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
          state = TelegramAuthState.ready; 
        }
      }
    }
  }

  Future<void> setAuthenticationPhoneNumber(String phoneNumber) async {
    TdPlugin.instance.tdSend(_clientId, jsonEncode({
      "@type": "setAuthenticationPhoneNumber",
      "phone_number": phoneNumber,
      "settings": {
        "@type": "phoneNumberAuthenticationSettings",
        "allow_flash_call": false,
        "allow_missed_call": false,
        "is_current_phone_number": false,
        "allow_sms_retriever_api": false
      }
    }));
  }

  Future<void> checkAuthenticationCode(String code) async {
    TdPlugin.instance.tdSend(_clientId, jsonEncode({
      "@type": "checkAuthenticationCode",
      "code": code
    }));
  }

  Future<void> checkAuthenticationPassword(String password) async {
    TdPlugin.instance.tdSend(_clientId, jsonEncode({
      "@type": "checkAuthenticationPassword",
      "password": password
    }));
  }

  List<Map<String, dynamic>> chats = [];

  Future<Map<String, dynamic>> loadChats() async {
    return sendRequest({
      "@type": "loadChats",
      "chat_list": {"@type": "chatListMain"},
      "limit": 500
    });
  }

  Future<Map<String, dynamic>> createNewChannel(String title, String description) async {
    return sendRequest({
      "@type": "createNewSupergroupChat",
      "title": title,
      "is_channel": true,
      "description": description,
      "for_import": false
    });
  }

  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests = {};
  
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get tdlibEvents => _eventController.stream;

  Future<Map<String, dynamic>> sendRequest(Map<String, dynamic> request) async {
    final requestId = const Uuid().v4();
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[requestId] = completer;

    request['@extra'] = requestId;
    TdPlugin.instance.tdSend(_clientId, jsonEncode(request));

    return completer.future;
  }

  Future<Map<String, dynamic>> getMe() async {
    return sendRequest({"@type": "getMe"});
  }

  Future<Map<String, dynamic>> getChatMember(int chatId, int userId) async {
    return sendRequest({
      "@type": "getChatMember",
      "chat_id": chatId,
      "member_id": {
        "@type": "messageSenderUser",
        "user_id": userId
      }
    });
  }

  Future<Map<String, dynamic>> searchPublicChat(String username) async {
    return sendRequest({
      "@type": "searchPublicChat",
      "username": username
    });
  }

  Future<Map<String, dynamic>> checkAdminStatus(dynamic chatId) async {
    int id = chatId is String ? int.parse(chatId) : chatId;
    try {
      final me = await getMe();
      if (!me.containsKey('id')) return {"is_admin": false};
      final userId = me['id'];
      
      final member = await getChatMember(id, userId);
      final status = member['status']?['@type'];
      bool isAdmin = (status == 'chatMemberStatusCreator' || status == 'chatMemberStatusAdministrator');
      return {"is_admin": isAdmin, "chat_id": id};
    } catch (e) {
      return {"is_admin": false, "error": e.toString()};
    }
  }

  Future<Map<String, dynamic>?> verifyChannel(String input) async {
    String trimmedInput = input.trim();
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
      int? firstTryId = int.tryParse(trimmedInput);
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
          String prefixedStr = trimmedInput.startsWith('-') 
              ? '-100${trimmedInput.substring(1)}' 
              : '-100$trimmedInput';
          
          int? secondTryId = int.tryParse(prefixedStr);
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



  Future<Map<String, dynamic>> getMessage(int chatId, int messageId) async {
    return sendRequest({
      "@type": "getMessage",
      "chat_id": chatId,
      "message_id": messageId,
    });
  }

  Future<void> downloadFile(int fileId) async {
    TdPlugin.instance.tdSend(_clientId, jsonEncode({
      "@type": "downloadFile",
      "file_id": fileId,
      "priority": 1,
      "offset": 0,
      "limit": 0,
      "synchronous": false
    }));
  }

  Future<void> uploadDocument(int chatId, String localFilePath, {String? caption}) async {
    TdPlugin.instance.tdSend(_clientId, jsonEncode({
      "@type": "sendMessage",
      "chat_id": chatId,
      "input_message_content": {
        "@type": "inputMessageDocument",
        "document": {
          "@type": "inputFileLocal",
          "path": localFilePath
        },
        if (caption != null)
          "caption": {
            "@type": "formattedText",
            "text": caption,
            "entities": []
          }
      }
    }));
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
    int attempts = 0;
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

  Future<Map<String, dynamic>> getActiveSessions() async {
    return sendRequest({
      "@type": "getActiveSessions",
    });
  }

  Future<Map<String, dynamic>> terminateSession(dynamic sessionId) async {
    return sendRequest({
      "@type": "terminateSession",
      "session_id": sessionId is String ? int.parse(sessionId) : sessionId,
    });
  }

  Future<Map<String, dynamic>> terminateAllOtherSessions() async {
    return sendRequest({
      "@type": "terminateAllOtherSessions",
    });
  }

  Future<List<Map<String, dynamic>>> getAdminChannels() async {
    try {
      await loadChats();
    } catch (_) {
      // Ignored if already loading/loaded
    }
    await Future.delayed(const Duration(milliseconds: 200));

    try {
      final response = await sendRequest({
        "@type": "getChats",
        "chat_list": {"@type": "chatListMain"},
        "limit": 200,
      });

      List<Map<String, dynamic>> adminChannels = [];
      if (response.containsKey('chat_ids')) {
        final List<dynamic> chatIds = response['chat_ids'];
        for (final id in chatIds) {
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
      }
      return adminChannels;
    } catch (e, s) {
      AppLogger.error('Failed to get chats from TDLib', e, s);
      return [];
    }
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

final telegramServiceProvider = StateNotifierProvider<TelegramService, TelegramAuthState>((ref) {
  return TelegramService(accountId: 'primary', isHeadless: false);
});


