import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:aerodrive/core/theme/app_colors.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:aerodrive/features/telegram/telegram_service.dart';
import 'package:drift/drift.dart' as drift;

final activeChannelIdProvider = FutureProvider.autoDispose<String?>((ref) async {
  final settings = ref.watch(settingsRepositoryProvider);
  return settings.getSetting('active_channel_id');
});

final activeChannelNameProvider = FutureProvider.autoDispose<String?>((ref) async {
  final activeChannelStr = ref.watch(activeChannelIdProvider).valueOrNull;
  if (activeChannelStr == null) return null;
  final channelId = int.tryParse(activeChannelStr);
  if (channelId == null) return null;
  final db = ref.watch(databaseProvider);
  final channel = await (db.select(db.channels)..where((c) => c.id.equals(channelId))).getSingleOrNull();
  return channel?.name;
});

class HealthCheckScreen extends ConsumerStatefulWidget {
  const HealthCheckScreen({super.key});

  @override
  ConsumerState<HealthCheckScreen> createState() => _HealthCheckScreenState();
}

class _HealthCheckScreenState extends ConsumerState<HealthCheckScreen> {
  bool _isScanning = false;
  double _progress = 0;
  String _statusText = "Ready to scan";
  
  int _scannedChunks = 0;
  int _totalChunks = 0;
  
  List<String> _compromisedFiles = [];
  bool _hasScanned = false;

  void _startScan(int channelId) async {
    setState(() {
      _isScanning = true;
      _progress = 0;
      _statusText = "Fetching local file chunks...";
      _compromisedFiles.clear();
      _scannedChunks = 0;
      _totalChunks = 0;
      _hasScanned = false;
    });

    try {
      final db = ref.read(databaseProvider);
      final telegram = ref.read(telegramServiceProvider.notifier);

      // Verify Telegram client auth state first
      final authState = ref.read(telegramServiceProvider);
      if (authState != TelegramAuthState.ready) {
        throw Exception("Telegram is not logged in or connected. Please authenticate first.");
      }

      // Query database chunks
      final chunks = await (db.select(db.chunks)..where((c) => c.channelId.equals(channelId))).get();
      if (chunks.isEmpty) {
        setState(() {
          _isScanning = false;
          _progress = 1.0;
          _statusText = "No files have been uploaded yet. Channel integrity is healthy!";
          _hasScanned = true;
        });
        return;
      }

      _totalChunks = chunks.length;
      final Set<String> compromisedFileIds = {};

      for (final chunk in chunks) {
        if (chunk.messageId == null) continue;

        setState(() {
          _statusText = "Checking chunk ${_scannedChunks + 1} of $_totalChunks...";
          _progress = _scannedChunks / _totalChunks;
        });

        bool chunkExists = false;
        int retries = 3;
        while (retries > 0) {
          try {
            await telegram.getMessage(channelId, chunk.messageId!);
            chunkExists = true;
            break;
          } catch (e) {
            final errStr = e.toString().toLowerCase();
            // If message is permanently gone, no need to retry
            if (errStr.contains('message not found') || errStr.contains('chat not found')) {
              break;
            }
            retries--;
            if (retries > 0) {
              await Future.delayed(const Duration(milliseconds: 500));
            }
          }
        }

        if (!chunkExists) {
          if (chunk.fileId != null) {
            compromisedFileIds.add(chunk.fileId!);
          }
        }

        _scannedChunks++;
      }

      // Fetch filenames of compromised files
      final List<String> fileNames = [];
      for (final fileId in compromisedFileIds) {
        final file = await (db.select(db.files)..where((f) => f.id.equals(fileId))).getSingleOrNull();
        if (file != null) {
          fileNames.add(file.name);
        }
      }

      setState(() {
        _isScanning = false;
        _progress = 1.0;
        _compromisedFiles = fileNames;
        _hasScanned = true;
        if (fileNames.isEmpty) {
          _statusText = "Integrity check passed! All $_totalChunks chunks exist on Telegram.";
        } else {
          _statusText = "Integrity check failed: ${fileNames.length} compromised file(s) detected.";
        }
      });

    } catch (e) {
      setState(() {
        _isScanning = false;
        _progress = 0;
        _statusText = "Scan failed: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeChannelAsync = ref.watch(activeChannelIdProvider);
    final channelNameAsync = ref.watch(activeChannelNameProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Channel Health Check'),
      ),
      body: activeChannelAsync.when(
        data: (activeChannelId) {
          final channelId = activeChannelId != null ? int.tryParse(activeChannelId) : null;

          if (channelId == null) {
            // Render Missing Channel UI State
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.error.withOpacity(0.3)),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 64,
                            color: AppColors.error,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No Storage Channel Added',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'To run a channel health check, you must add and select an active storage channel first.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () {
                        context.push('/settings/channels');
                      },
                      icon: const Icon(Icons.settings),
                      label: const Text('Configure Storage Channels'),
                    ),
                  ],
                ),
              ),
            );
          }

          final channelName = channelNameAsync.valueOrNull ?? 'AeroDrive Storage Channel';

          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Verify the integrity of messages in your active storage channel ($channelName). This ensures no file chunks were accidentally deleted from Telegram.',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _compromisedFiles.isNotEmpty
                          ? AppColors.error.withOpacity(0.4)
                          : AppColors.primary.withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _isScanning 
                            ? Icons.sync 
                            : (_compromisedFiles.isNotEmpty 
                                ? Icons.gpp_bad 
                                : (_hasScanned ? Icons.verified_user : Icons.health_and_safety)),
                        size: 64,
                        color: _isScanning 
                            ? AppColors.primaryLight 
                            : (_compromisedFiles.isNotEmpty 
                                ? AppColors.error 
                                : (_hasScanned ? Colors.greenAccent : Colors.white38)),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _statusText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      if (_isScanning) ...[
                        const SizedBox(height: 16),
                        LinearProgressIndicator(value: _progress),
                      ]
                    ],
                  ),
                ),
                if (_compromisedFiles.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Compromised Files List:',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.error, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.outline),
                      ),
                      child: ListView.builder(
                        itemCount: _compromisedFiles.length,
                        itemBuilder: (context, index) {
                          return ListTile(
                            leading: const Icon(Icons.error_outline, color: AppColors.error),
                            title: Text(
                              _compromisedFiles[index],
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                            ),
                            subtitle: const Text('Missing chunk data on Telegram', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          );
                        },
                      ),
                    ),
                  ),
                ],
                if (_compromisedFiles.isEmpty) const Spacer(),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _isScanning ? null : () => _startScan(channelId),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(_isScanning ? 'Scanning...' : 'Start Health Check'),
                )
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error loading channel setting: $err')),
      ),
    );
  }
}
