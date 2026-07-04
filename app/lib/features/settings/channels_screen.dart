import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logger.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/providers/security_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/recovery/recovery_scanner.dart';
import '../../domain/sync/config_sync_service.dart';
import '../telegram/telegram_manager.dart';
import '../telegram/telegram_service.dart';

class ChannelsScreen extends ConsumerStatefulWidget {
  const ChannelsScreen({super.key});

  @override
  ConsumerState<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends ConsumerState<ChannelsScreen> {
  String? _activeChannelId;
  List<Map<String, dynamic>> _storageChannels = [];
  bool _isLoading = true;

  /// Stores the local master password salt in the channel description so other
  /// devices can discover it and derive the same encryption key.
  /// Only writes if the channel does not already have an AERODRIVE_SALT,
  /// preserving the first device's salt as canonical.
  Future<void> _storeSaltInChannel(TelegramService telegram, int chatId) async {
    try {
      final settings = ref.read(settingsRepositoryProvider);
      final localSalt = await settings.getSetting('master_password_salt');
      if (localSalt == null || localSalt.isEmpty) return;

      final existing = await telegram.getChannelDescription(chatId);
      if (existing != null && existing.startsWith('AERODRIVE_SALT:')) {
        final existingSalt = existing.substring('AERODRIVE_SALT:'.length).trim();
        if (existingSalt == localSalt) {
          AppLogger.info('Salt already matches in channel $chatId — no update needed');
          return;
        }
        if (existingSalt.isNotEmpty) {
          AppLogger.warning(
            'Channel $chatId already has salt $existingSalt — not overwriting with local $localSalt. '
            'Reinstall on this device to adopt the channel salt.',
          );
          return;
        }
      }

      await telegram.setChatDescription(chatId, 'AERODRIVE_SALT:$localSalt');
      AppLogger.info('Stored salt in channel $chatId description');
    } catch (e) {
      AppLogger.error('Failed to store salt in channel description', e);
    }
  }
  bool _isProcessingSetup = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = ref.read(settingsRepositoryProvider);
    final activeId = await settings.getSetting('active_channel_id');
    final savedChannelsJson = await settings.getSetting('storage_channels_list');
    
    List<Map<String, dynamic>> loaded = [];
    if (savedChannelsJson != null && savedChannelsJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(savedChannelsJson);
        loaded = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (e) {
        // ignore
      }
    }
    
    if (mounted) {
      setState(() {
        _activeChannelId = activeId;
        _storageChannels = loaded;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveChannelsList() async {
    final settings = ref.read(settingsRepositoryProvider);
    await settings.setSetting('storage_channels_list', jsonEncode(_storageChannels));
    
    // Sync the new configuration to the dedicated config channel
    ref.read(configSyncServiceProvider).syncConfigToChannel();
  }

  Future<bool?> _showPoolConfirmationDialog(String channelTitle) async {
    final accounts = ref.read(telegramManagerProvider);
    final readySecondaries = accounts.where((c) => c.authState == TelegramAuthState.ready).length;
    if (readySecondaries <= 1) return false;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Enable Bandwidth Pooling', style: TextStyle(color: Colors.white)),
        content: Text(
          'Would you like to automatically add and promote all your other logged-in Telegram accounts as administrators of "$channelTitle"?\n\n'
          'This allows AeroDrive to pool bandwidth across all accounts for faster, load-balanced uploads and downloads.',
          style: const TextStyle(color: AppColors.onSurface),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No, only this account', style: TextStyle(color: AppColors.onSurfaceVariant)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, pool accounts'),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyAndAddChannel(String identifier, String accountId) async {
    final accounts = ref.read(telegramManagerProvider);
    final telegram = accounts.firstWhere((c) => c.accountId == accountId, orElse: () => accounts.first);
    
    try {
      final chat = await telegram.verifyChannel(identifier);
      if (chat != null) {
        final chatId = chat['id'];
        final title = chat['title'] ?? 'Unknown Chat';
        
        final poolConfirmed = await _showPoolConfirmationDialog(title);
        
        setState(() => _isProcessingSetup = true);
        
        if (poolConfirmed == true) {
          for (final client in accounts) {
            if (client.accountId != accountId && client.authState == TelegramAuthState.ready && client.userId != null) {
              try {
                await telegram.addAdminToChat(chatId, client.userId!);
              } catch (e) {
                AppLogger.error('Failed to add admin $client to channel $title: $e');
              }
            }
          }
        }

        final newChannel = {
          'id': chatId,
          'title': title,
          'accountId': accountId,
        };

        setState(() {
          if (!_storageChannels.any((c) => c['id'] == newChannel['id'])) {
            _storageChannels.add(newChannel);
          }
        });
        await _saveChannelsList();

        // Auto-activate if no active channel is set
        final settings = ref.read(settingsRepositoryProvider);
        final activeId = await settings.getSetting('active_channel_id');
        if (activeId == null || activeId.isEmpty) {
          await settings.setSetting('active_channel_id', chatId.toString());
          await settings.setSetting('active_channel_name', title);
          await settings.setSetting('active_channel_account_id', accountId);
          setState(() {
            _activeChannelId = chatId.toString();
          });
        }

        // Store the master password salt in the channel description for cross-device sync.
        await _storeSaltInChannel(telegram, chatId);

        // Run sync automatically in background
        final masterKey = ref.read(masterKeyProvider);
        if (masterKey != null) {
          final recoveryService = ref.read(recoveryServiceProvider);
          // Run non-blocking
          AesGcm.with256bits().newSecretKeyFromBytes(masterKey).then((secretKey) {
            recoveryService.runDisasterRecovery(masterKey: secretKey, channelId: chatId).catchError((e) {
              AppLogger.error('Auto-sync failed for new channel', e);
            });
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Channel successfully verified, pooled, and bound! Syncing...'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to verify. Ensure you are an admin.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingSetup = false);
      }
    }
  }

  Future<void> _confirmAndAddChannel(String id, String title, String accountId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Add Storage Channel', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to bind "$title" as a storage backend for account "$accountId"?',
          style: const TextStyle(color: AppColors.onSurface),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add & Bind'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _verifyAndAddChannel(id, accountId);
    }
  }

  void _showAddChannelOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Add Storage Channel',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ListTile(
                  leading: const Icon(Icons.link, color: AppColors.primaryLight),
                  title: const Text('Link Existing Channel', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  subtitle: const Text('Choose from Telegram channels you manage', style: TextStyle(fontSize: 12)),
                  onTap: () {
                    Navigator.pop(context);
                    _showLinkExistingChannelDialog();
                  },
                ),
                const Divider(color: AppColors.outline),
                ListTile(
                  leading: const Icon(Icons.add_circle_outline, color: AppColors.secondaryLight),
                  title: const Text('Create Private Channel', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  subtitle: const Text('Create a new private channel on Telegram', style: TextStyle(fontSize: 12)),
                  onTap: () {
                    Navigator.pop(context);
                    _showCreateNewChannelDialog();
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
    );
  }

  void _showLinkExistingChannelDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Consumer(
          builder: (context, ref, child) {
            final accounts = ref.watch(telegramManagerProvider);
            final adminChannelsAsync = ref.watch(adminChannelsProvider);

            return AlertDialog(
              backgroundColor: AppColors.surfaceElevated,
              title: const Text('Link Existing Channel', style: TextStyle(color: Colors.white)),
              content: SizedBox(
                width: double.maxFinite,
                height: 300,
                child: adminChannelsAsync.when(
                  data: (availableChats) {
                    final filteredAvailable = availableChats.where((chat) {
                      final id = chat['id'];
                      return !_storageChannels.any((c) => c['id'] == id);
                    }).toList();

                    if (filteredAvailable.isEmpty) {
                      return const Center(
                        child: Text(
                          'No available admin channels found. Ensure you are an administrator of the channels.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.onSurfaceVariant),
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: filteredAvailable.length,
                      itemBuilder: (context, index) {
                        final chat = filteredAvailable[index];
                        final title = chat['title'] ?? 'Unknown Chat';
                        final id = chat['id'].toString();
                        final chatAccountId = chat['accountId'] ?? 'primary';
                        final client = accounts.firstWhere((c) => c.accountId == chatAccountId, orElse: () => accounts.first);

                        return Card(
                          color: AppColors.surface,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(color: AppColors.outline),
                          ),
                          child: ListTile(
                            leading: const Icon(Icons.campaign, color: AppColors.primaryLight),
                            title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                            subtitle: Text('Account: ${client.displayName}', style: const TextStyle(fontSize: 11)),
                            trailing: const Icon(Icons.link, size: 20),
                            onTap: () {
                              Navigator.pop(ctx);
                              _confirmAndAddChannel(id, title, chatAccountId);
                            },
                          ),
                        );
                      },
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, stack) => Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.error, size: 36),
                        const SizedBox(height: 8),
                        Text('Error: $err', style: const TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => ref.invalidate(adminChannelsProvider),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close', style: TextStyle(color: AppColors.onSurfaceVariant)),
                ),
              ],
            );
          },
        ),
    );
  }

  void _showCreateNewChannelDialog() {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    final accounts = ref.read(telegramManagerProvider);
    String selectedAccountId = accounts.first.accountId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (context, setStateDialog) => AlertDialog(
              backgroundColor: AppColors.surfaceElevated,
              title: const Text('Create Private Channel', style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Channel Title',
                      labelStyle: TextStyle(color: AppColors.onSurfaceVariant),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Description (Optional)',
                      labelStyle: TextStyle(color: AppColors.onSurfaceVariant),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (accounts.length > 1) ...[
                    const Text('Create using Account:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 8),
                    DropdownButton<String>(
                      value: selectedAccountId,
                      dropdownColor: AppColors.surfaceElevated,
                      isExpanded: true,
                      style: const TextStyle(color: Colors.white),
                      items: accounts.map((acc) => DropdownMenuItem(
                        value: acc.accountId,
                        child: Text(acc.displayName),
                      )).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setStateDialog(() => selectedAccountId = val);
                        }
                      },
                    ),
                  ]
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
                ),
                FilledButton(
                  onPressed: () async {
                    final title = titleController.text.trim();
                    if (title.isEmpty) return;
                    Navigator.pop(ctx);
                    
                    try {
                      final telegram = accounts.firstWhere((c) => c.accountId == selectedAccountId);
                      final chat = await telegram.createNewChannel(title, descController.text.trim());
                      final chatId = chat['id'];
                      
                      if (chatId != null) {
                        final poolConfirmed = await _showPoolConfirmationDialog(title);
                        setState(() => _isProcessingSetup = true);
                        
                        if (poolConfirmed == true) {
                          for (final client in accounts) {
                            if (client.accountId != selectedAccountId && client.authState == TelegramAuthState.ready && client.userId != null) {
                              try {
                                await telegram.addAdminToChat(chatId, client.userId!);
                              } catch (e) {
                                AppLogger.error('Failed to add admin $client to new channel: $e');
                              }
                            }
                          }
                        }

                        final newChannel = {
                          'id': chatId,
                          'title': title,
                          'accountId': selectedAccountId,
                        };

                        setState(() {
                          if (!_storageChannels.any((c) => c['id'] == newChannel['id'])) {
                            _storageChannels.add(newChannel);
                          }
                        });
                        await _saveChannelsList();

                        // Auto-activate if no active channel is set
                        final settings = ref.read(settingsRepositoryProvider);
                        final activeId = await settings.getSetting('active_channel_id');
                        if (activeId == null || activeId.isEmpty) {
                          await settings.setSetting('active_channel_id', chatId.toString());
                          await settings.setSetting('active_channel_name', title);
                          await settings.setSetting('active_channel_account_id', selectedAccountId);
                          setState(() {
                            _activeChannelId = chatId.toString();
                          });
                        }

                        // Store the master password salt in the channel description.
                        await _storeSaltInChannel(telegram, chatId);

                        // Run sync automatically in background
                        final masterKey = ref.read(masterKeyProvider);
                        if (masterKey != null) {
                          final recoveryService = ref.read(recoveryServiceProvider);
                          // Run non-blocking
                          AesGcm.with256bits().newSecretKeyFromBytes(masterKey).then((secretKey) {
                            recoveryService.runDisasterRecovery(masterKey: secretKey, channelId: chatId).catchError((e) {
                              AppLogger.error('Auto-sync failed for new channel', e);
                            });
                          });
                        }
                      }
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Channel created, pooled, and bound successfully! Syncing...'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Failed to create channel: $e'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _isProcessingSetup = false);
                    }
                  },
                  child: const Text('Create'),
                ),
              ],
            )
        ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(telegramManagerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage Channels'),
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Channel',
            onPressed: _showAddChannelOptions,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddChannelOptions,
        icon: const Icon(Icons.add),
        label: const Text('Add Channel'),
      ),
      body: _isLoading || _isProcessingSetup
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _loadSettings();
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(24, 24, 24, 8),
                      child: Text(
                        'Active Storage Channels',
                        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                      ),
                    ),
                  ),
                  if (_storageChannels.isEmpty) const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(height: 48),
                                  Icon(Icons.dns_outlined, size: 64, color: Colors.white24),
                                  SizedBox(height: 16),
                                  Text(
                                    'No channels added yet.',
                                    style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Tap the Add Channel button to link or create a channel.',
                                    style: TextStyle(color: Colors.white30, fontSize: 12),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ) else SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final chat = _storageChannels[index];
                              final title = chat['title'] ?? 'Unknown Chat';
                              final id = chat['id'].toString();
                              final boundAccount = chat['accountId'] ?? 'primary';
                              final isActive = _activeChannelId == id;

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                                leading: CircleAvatar(
                                  backgroundColor: isActive ? Colors.green.withValues(alpha: 0.2) : AppColors.primaryLight.withValues(alpha: 0.2),
                                  child: Icon(
                                    isActive ? Icons.check_circle : Icons.cloud,
                                    color: isActive ? Colors.green : AppColors.primaryLight,
                                  ),
                                ),
                                title: Text(
                                  title,
                                  style: TextStyle(fontWeight: FontWeight.bold, color: isActive ? Colors.green : Colors.white),
                                ),
                                subtitle: Text(
                                  'Bound Account: ${accounts.firstWhere((c) => c.accountId == boundAccount, orElse: () => accounts.first).displayName}\nTap to select as primary backend',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: isActive
                                    ? const Text('ACTIVE', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12))
                                    : IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                                        onPressed: () {
                                          setState(() {
                                            _storageChannels.removeWhere((c) => c['id'].toString() == id);
                                            if (_activeChannelId == id) _activeChannelId = null;
                                          });
                                          _saveChannelsList();
                                        },
                                      ),
                                onTap: () async {
                                  final settings = ref.read(settingsRepositoryProvider);
                                  await settings.setSetting('active_channel_id', id);
                                  await settings.setSetting('active_channel_name', title);
                                  await settings.setSetting('active_channel_account_id', boundAccount);
                                  setState(() => _activeChannelId = id);

                                  // Store the master password salt in the channel description.
                                  final chatId = int.tryParse(id);
                                  if (chatId != null) {
                                    final telegram = ref.read(telegramServiceProvider.notifier);
                                    await _storeSaltInChannel(telegram, chatId);
                                  }

                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Selected "$title" as the active storage channel!'),
                                        backgroundColor: AppColors.success,
                                      ),
                                    );
                                  }
                                },
                              );
                            },
                            childCount: _storageChannels.length,
                          ),
                        ),
                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              ),
            ),
    );
  }
}
