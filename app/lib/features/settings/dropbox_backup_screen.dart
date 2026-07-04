import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/backup_service.dart';
import 'dropbox_service.dart';
import 'widgets/backup_folder_mapper.dart';

class DropboxBackupScreen extends ConsumerStatefulWidget {
  const DropboxBackupScreen({super.key});

  @override
  ConsumerState<DropboxBackupScreen> createState() => _DropboxBackupScreenState();
}

class _DropboxBackupScreenState extends ConsumerState<DropboxBackupScreen> {
  bool _isConnecting = false;
  bool _isBackingUp = false;
  double _uploadProgress = 0;
  
  String _frequency = 'weekly';
  String _maxKeep = '5';
  bool _wifiOnly = true;
  bool _isLoadingSettings = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = ref.read(settingsRepositoryProvider);
    final freq = await settings.getSetting('dropbox_frequency') ?? 'weekly';
    final maxKeep = await settings.getSetting('dropbox_max_keep') ?? '5';
    final wifi = await settings.getSetting('dropbox_wifi_only');
    
    if (mounted) {
      setState(() {
        _frequency = freq;
        _maxKeep = maxKeep;
        _wifiOnly = wifi == 'true' || wifi == null; // Default true
        _isLoadingSettings = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    final settings = ref.read(settingsRepositoryProvider);
    await settings.setSetting('dropbox_frequency', _frequency);
    await settings.setSetting('dropbox_max_keep', _maxKeep);
    await settings.setSetting('dropbox_wifi_only', _wifiOnly.toString());
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = ref.watch(dropboxServiceProvider);
    final dropboxEmail = ref.read(dropboxServiceProvider.notifier).email;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Dropbox Backup'),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: _isLoadingSettings
        ? const Center(child: CircularProgressIndicator())
        : ListView(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
        children: [
          const Text(
            'Securely sync your local SQLite database and encryption keys to Dropbox App Folder.',
            style: TextStyle(color: Colors.white70, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // Connection Card
          Container(
            decoration: BoxDecoration(
              color: isConnected ? Colors.blue.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isConnected ? Colors.blue.withValues(alpha: 0.5) : Colors.white12),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(
                  Icons.cloud_done_outlined,
                  size: 64,
                  color: isConnected ? Colors.blueAccent : Colors.white54,
                )
                .animate(target: isConnected ? 1 : 0)
                .scale(duration: 400.ms, curve: Curves.easeOutBack),
                
                const SizedBox(height: 16),
                
                if (isConnected) ...[
                  Text('Connected to Dropbox', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue.shade300)),
                  const SizedBox(height: 4),
                  Text(dropboxEmail ?? '', style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 24),
                  FilledButton.tonal(
                    onPressed: () async {
                      await ref.read(dropboxServiceProvider.notifier).disconnect();
                    },
                    style: FilledButton.styleFrom(backgroundColor: Colors.red.withValues(alpha: 0.2), foregroundColor: Colors.redAccent),
                    child: const Text('Disconnect'),
                  ),
                ] else ...[
                  const Text('Not Connected', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _isConnecting ? null : () async {
                      final service = ref.read(dropboxServiceProvider.notifier);
                      await service.openAuthUrl();
                      
                      if (!context.mounted) return;
                      final codeController = TextEditingController();
                      
                      final code = await showDialog<String>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Enter Authorization Code'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Please paste the authorization code provided by Dropbox after you approved access.'),
                              const SizedBox(height: 16),
                              TextField(
                                controller: codeController,
                                decoration: const InputDecoration(
                                  labelText: 'Authorization Code',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, codeController.text),
                              child: const Text('Connect'),
                            ),
                          ],
                        ),
                      );

                      if (code != null && code.isNotEmpty) {
                        setState(() => _isConnecting = true);
                        final success = await service.connectWithCode(code);
                        if (mounted) {
                          setState(() => _isConnecting = false);
                          if (success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Successfully connected to Dropbox!'), backgroundColor: Colors.green),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Failed to connect.'), backgroundColor: Colors.redAccent),
                            );
                          }
                        }
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    ),
                    child: _isConnecting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Connect Dropbox', style: TextStyle(fontSize: 16)),
                  ),
                ],
              ],
            ),
          ).animate().fadeIn(duration: 500.ms),

          const SizedBox(height: 32),

          // Auto-Backup Settings (Animated Expand)
          if (isConnected)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Auto-Backup Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('Frequency'),
                        trailing: DropdownButton<String>(
                          value: _frequency,
                          dropdownColor: AppColors.surface,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(value: 'daily', child: Text('Daily')),
                            DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                            DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _frequency = val);
                              _saveSettings();
                            }
                          },
                        ),
                      ),
                      const Divider(height: 1, color: Colors.white12),
                      ListTile(
                        title: const Text('Max Backups to Keep'),
                        trailing: DropdownButton<String>(
                          value: _maxKeep,
                          dropdownColor: AppColors.surface,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(value: '3', child: Text('3 Backups')),
                            DropdownMenuItem(value: '5', child: Text('5 Backups')),
                            DropdownMenuItem(value: '10', child: Text('10 Backups')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _maxKeep = val);
                              _saveSettings();
                            }
                          },
                        ),
                      ),
                      const Divider(height: 1, color: Colors.white12),
                      SwitchListTile(
                        title: const Text('Wi-Fi Only'),
                        value: _wifiOnly,
                        activeThumbColor: Colors.blueAccent,
                        onChanged: (val) {
                          setState(() => _wifiOnly = val);
                          _saveSettings();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                // Destination Folder Mapper
                const BackupFolderMapper(),

                const SizedBox(height: 32),
                if (_isBackingUp)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      children: [
                        LinearProgressIndicator(
                          value: _uploadProgress > 0 ? _uploadProgress : null,
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                          minHeight: 4,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _uploadProgress > 0
                              ? 'Uploading... ${(_uploadProgress * 100).toStringAsFixed(0)}%'
                              : 'Preparing backup...',
                          style: const TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isBackingUp ? null : () async {
                      setState(() {
                        _isBackingUp = true;
                        _uploadProgress = 0.0;
                      });
                      
                      try {
                        final backupService = ref.read(backupServiceProvider);
                        final settings = ref.read(settingsRepositoryProvider);
                        final destFolder = await settings.getSetting('dropbox_backup_path') ?? '/AeroDrive';
                        final backupPath = await backupService.exportBackup(
                          exportDatabase: true,
                          exportSettings: true,
                        );
                        
                        setState(() => _uploadProgress = 0.01);
                        
                        final success = await ref.read(dropboxServiceProvider.notifier).uploadBackup(
                          backupPath,
                          destinationFolder: destFolder,
                          onProgress: (p) {
                            if (mounted) setState(() => _uploadProgress = p);
                          },
                        );
                        
                        final tempFile = File(backupPath);
                        if (await tempFile.exists()) {
                          await tempFile.delete();
                        }
                        
                        if (context.mounted) {
                          setState(() => _isBackingUp = false);
                          if (success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Backup uploaded to Dropbox!'), backgroundColor: Colors.green),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Dropbox upload failed.'), backgroundColor: Colors.redAccent),
                            );
                          }
                        }
                      } catch (e) {
                        if (context.mounted) {
                          setState(() => _isBackingUp = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Backup failed: $e'), backgroundColor: Colors.redAccent),
                          );
                        }
                      }
                    },
                    icon: _isBackingUp ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.backup),
                    label: Text(_isBackingUp ? 'Uploading...' : 'Backup Now'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                )
              ],
            ).animate().slideY(begin: 0.1, duration: 400.ms, curve: Curves.easeOut).fadeIn(),
        ],
      ),
    );
  }
}
