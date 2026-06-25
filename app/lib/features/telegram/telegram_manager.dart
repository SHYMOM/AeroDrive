import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'telegram_service.dart';

import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:aerodrive/core/logger.dart';

class TelegramManager extends StateNotifier<List<TelegramService>> {
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get allEvents => _eventController.stream;

  TelegramManager(this.ref) : super([]) {
    // Add the primary client by default
    final primary = ref.read(telegramServiceProvider.notifier);
    _setupClientListener(primary);
    state = [primary];
    _loadSavedAccounts();
  }

  final Ref ref;

  void _setupClientListener(TelegramService client) {
    client.tdlibEvents.listen((event) {
      _eventController.add({
        '__accountId': client.accountId,
        ...event
      });
    });

    client.onProfileUpdated = () {
      if (mounted) {
        state = [...state];
        _saveAccounts();
      }
    };

    client.addListener((authState) {
      if (mounted) {
        state = [...state];
        _saveAccounts();
      }
    });
  }

  TelegramService getClient(String accountId) {
    return state.firstWhere((c) => c.accountId == accountId, orElse: () => state.first);
  }

  Future<void> _loadSavedAccounts() async {
    final settings = ref.read(settingsRepositoryProvider);
    final accountsStr = await settings.getSetting('telegram_accounts');
    if (accountsStr != null) {
      try {
        final List<dynamic> loaded = jsonDecode(accountsStr);
        for (final acc in loaded) {
          if (acc is String) {
            if (acc != 'primary') {
              addClient(acc, isHeadless: true, save: false);
            }
          } else if (acc is Map) {
            final id = acc['id'] as String;
            if (id != 'primary') {
              final client = addClient(id, isHeadless: true, save: false);
              client.userId = acc['userId'] as int?;
              client.firstName = acc['firstName'] as String?;
              client.lastName = acc['lastName'] as String?;
              client.phoneNumber = acc['phoneNumber'] as String?;
              client.photoPath = acc['photoPath'] as String?;
            } else {
              // Populate primary client cache
              final primary = getClient('primary');
              primary.userId = acc['userId'] as int?;
              primary.firstName = acc['firstName'] as String?;
              primary.lastName = acc['lastName'] as String?;
              primary.phoneNumber = acc['phoneNumber'] as String?;
              primary.photoPath = acc['photoPath'] as String?;
            }
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _saveAccounts() async {
    final settings = ref.read(settingsRepositoryProvider);
    final List<Map<String, dynamic>> data = [];
    for (final client in state) {
      data.add({
        'id': client.accountId,
        'userId': client.userId,
        'firstName': client.firstName,
        'lastName': client.lastName,
        'phoneNumber': client.phoneNumber,
        'photoPath': client.photoPath,
      });
    }
    await settings.setSetting('telegram_accounts', jsonEncode(data));
  }

  TelegramService addClient(String accountId, {bool isHeadless = true, bool save = true}) {
    for (final c in state) {
      if (c.accountId == accountId) return c;
    }
    final client = TelegramService(accountId: accountId, isHeadless: isHeadless);
    _setupClientListener(client);
    state = [...state, client];
    if (save) _saveAccounts();
    return client;
  }

  Future<void> removeClient(String accountId) async {
    if (accountId == 'primary') return;
    final clientIndex = state.indexWhere((c) => c.accountId == accountId);
    if (clientIndex == -1) return;
    
    final client = state[clientIndex];
    
    try {
      if (client.authState == TelegramAuthState.ready) {
        await client.logOut();
        int attempts = 0;
        while (client.authState != TelegramAuthState.closed && attempts < 30) {
          await Future.delayed(const Duration(milliseconds: 100));
          attempts++;
        }
      } else {
        await client.closeClient();
      }
    } catch (e) {
      AppLogger.error('Error closing/logging out client $accountId', e);
    }
    
    client.dispose();
    state = state.where((c) => c.accountId != accountId).toList();
    await _saveAccounts();
    
    // Brief delay to ensure OS file system releases all file handles
    await Future.delayed(const Duration(milliseconds: 500));
    
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final dbPath = Directory('${docDir.path}/AeroDrive/tdlib/$accountId');
      if (await dbPath.exists()) {
        await dbPath.delete(recursive: true);
        AppLogger.info('Deleted database directory for $accountId');
      }
    } catch (e) {
      AppLogger.error('Failed to delete database directory for $accountId', e);
    }
  }
}

final telegramManagerProvider = StateNotifierProvider<TelegramManager, List<TelegramService>>((ref) {
  return TelegramManager(ref);
});

final adminChannelsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final accounts = ref.watch(telegramManagerProvider);
  List<Map<String, dynamic>> allAdminChannels = [];
  
  for (final acc in accounts) {
    if (acc.authState == TelegramAuthState.ready) {
      try {
        final channels = await acc.getAdminChannels();
        for (final ch in channels) {
          allAdminChannels.add({
            ...ch,
            'accountId': acc.accountId,
          });
        }
      } catch (e, s) {
        AppLogger.error('Failed to load admin channels for account ${acc.accountId}', e, s);
      }
    }
  }
  return allAdminChannels;
});

final activeSessionsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final accounts = ref.watch(telegramManagerProvider);
  List<Map<String, dynamic>> allSessions = [];
  
  for (final client in accounts) {
    if (client.authState == TelegramAuthState.ready) {
      try {
        final response = await client.getActiveSessions();
        if (response.containsKey('sessions')) {
          final List<dynamic> list = response['sessions'];
          for (final sess in list) {
            allSessions.add({
              ...sess as Map<String, dynamic>,
              'accountId': client.accountId,
              'accountName': client.displayName,
            });
          }
        }
      } catch (e, s) {
        AppLogger.error('Failed to get active sessions for ${client.accountId}', e, s);
      }
    }
  }
  return allSessions;
});
