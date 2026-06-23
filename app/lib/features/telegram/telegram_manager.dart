import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'telegram_service.dart';

import 'dart:convert';
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
  }

  TelegramService getClient(String accountId) {
    return state.firstWhere((c) => c.accountId == accountId, orElse: () => state.first);
  }

  Future<void> _loadSavedAccounts() async {
    final settings = ref.read(settingsRepositoryProvider);
    final accountsStr = await settings.getSetting('telegram_accounts');
    if (accountsStr != null) {
      try {
        final List<dynamic> accountIds = jsonDecode(accountsStr);
        for (final acc in accountIds) {
          if (acc != 'primary') {
            addClient(acc as String, isHeadless: true, save: false);
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _saveAccounts() async {
    final settings = ref.read(settingsRepositoryProvider);
    final accountIds = state.map((c) => c.accountId).where((id) => id != 'primary').toList();
    await settings.setSetting('telegram_accounts', jsonEncode(accountIds));
  }

  void addClient(String accountId, {bool isHeadless = true, bool save = true}) {
    if (state.any((c) => c.accountId == accountId)) return;
    final client = TelegramService(accountId: accountId, isHeadless: isHeadless);
    _setupClientListener(client);
    state = [...state, client];
    if (save) _saveAccounts();
  }

  void removeClient(String accountId) {
    if (accountId == 'primary') return; // Cannot remove primary from here
    final client = state.firstWhere((c) => c.accountId == accountId, orElse: () => state.first);
    if (client.accountId == 'primary') return;
    client.dispose();
    state = state.where((c) => c.accountId != accountId).toList();
    _saveAccounts();
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
