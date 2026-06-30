import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'telegram_service.dart';

import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:drift/drift.dart' as drift;
import 'package:aerodrive/core/logger.dart';

class TelegramManager extends StateNotifier<List<TelegramService>> {
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get allEvents => _eventController.stream;

  TelegramManager(this.ref) : super([]) {
    _initPrimaryAndRestore();
  }

  final Ref ref;

  List<TelegramService> get readyClients =>
      state.where((c) => c.authState == TelegramAuthState.ready).toList();

  Future<void> _initPrimaryAndRestore() async {
    // Create primary client
    final primary = ref.read(telegramServiceProvider.notifier);
    _setupClientListener(primary);
    state = [primary];

    // Wait for the primary client to at least have its TDLib client handle created.
    // This ensures TdPlugin.initialize() has completed before secondary clients attempt it.
    int attempts = 0;
    while (primary.clientId == 0 && attempts < 100) {
      await Future.delayed(const Duration(milliseconds: 50));
      attempts++;
    }

    // Restore secondary accounts from Drift Accounts table
    await _restoreAccountsFromDb();

    // Listen for primary ready to save account
    primary.onReady = () => _saveAccountToDb(primary);
  }

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
        _saveAccountToDb(client);
      }
    };

    client.addListener((authState) {
      if (mounted) {
        state = [...state];
        if (authState == TelegramAuthState.ready) {
          _saveAccountToDb(client);
        }
      }
    });
  }

  TelegramService getClient(String accountId) {
    return state.firstWhere((c) => c.accountId == accountId, orElse: () => state.first);
  }

  Future<void> _restoreAccountsFromDb() async {
    try {
      final db = ref.read(databaseProvider);
      final accounts = await db.select(db.accounts).get();

      for (final acc in accounts) {
        if (acc.id == 'primary') {
          // Populate primary client
          final primary = getClient('primary');
          primary.phoneNumber = acc.phoneNumber;
          continue;
        }
        if (state.any((c) => c.accountId == acc.id)) continue;

        final client = await _initSecondaryClient(acc.id);
        client.phoneNumber = acc.phoneNumber;

        // Set up onReady to mark session as persistent
        client.onReady = () => _saveAccountToDb(client);
      }

      AppLogger.info('Restored ${accounts.length} accounts from DB');
    } catch (e, s) {
      AppLogger.error('Failed to restore accounts from DB', e, s);
    }
  }

  Future<TelegramService> _initSecondaryClient(String accountId) async {
    final client = TelegramService(accountId: accountId, isHeadless: true);

    // Ensure TDLib database directory exists
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final dbDir = Directory('${docDir.path}/AeroDrive/tdlib/$accountId');
      if (!await dbDir.exists()) {
        await dbDir.create(recursive: true);
      }
    } catch (e) {
      AppLogger.error('Failed to create TDLib db dir for $accountId', e);
    }

    _setupClientListener(client);
    state = [...state, client];
    AppLogger.info('Secondary client initialized for account $accountId');
    return client;
  }

  Future<void> _saveAccountToDb(TelegramService client) async {
    try {
      final db = ref.read(databaseProvider);
      await db.into(db.accounts).insertOnConflictUpdate(
        AccountsCompanion.insert(
          id: client.accountId,
          phoneNumber: drift.Value(client.phoneNumber),
          isDefault: drift.Value(client.accountId == 'primary'),
        ),
      );
      AppLogger.info('Account ${client.accountId} saved to DB');
    } catch (e, s) {
      AppLogger.error('Failed to save account to DB', e, s);
    }
  }

  TelegramService addClient(String accountId, {bool isHeadless = true, bool save = true}) {
    for (final c in state) {
      if (c.accountId == accountId) return c;
    }
    final client = TelegramService(accountId: accountId, isHeadless: isHeadless);
    _setupClientListener(client);

    client.onReady = () {
      _saveAccountToDb(client);
    };

    state = [...state, client];
    if (save) _saveAccountToDb(client);
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

    // Remove from Accounts table
    try {
      final db = ref.read(databaseProvider);
      await (db.delete(db.accounts)..where((a) => a.id.equals(accountId))).go();
    } catch (e) {
      AppLogger.error('Failed to remove account from DB', e);
    }

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
