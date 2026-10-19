import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/providers.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/providers/security_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/db/database.dart';
import '../../../domain/channel_load_balancer.dart';
import '../../../domain/recovery/manifest_encoder.dart';
import '../../telegram/telegram_manager.dart';
import '../../telegram/telegram_service.dart';

class FolderPickerDialog extends ConsumerStatefulWidget {
  const FolderPickerDialog({
    super.key,
    required this.title,
    this.initialFolderId,
    this.excludeFolderId,
  });
  final String title;
  final String? initialFolderId;
  final String? excludeFolderId;

  @override
  ConsumerState<FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends ConsumerState<FolderPickerDialog> {
  String? _currentFolderId;
  List<FolderData> _breadcrumbs = [];
  List<FolderData> _subfolders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _currentFolderId = widget.initialFolderId;
    _loadCurrentFolderContents();
  }

  Future<void> _loadCurrentFolderContents() async {
    setState(() => _isLoading = true);
    final db = ref.read(databaseProvider);
    
    // 1. Build breadcrumbs
    final List<FolderData> crumbs = [];
    String? iterId = _currentFolderId;
    while (iterId != null) {
      final folder = await (db.select(db.folders)..where((f) => f.id.equals(iterId!))).getSingleOrNull();
      if (folder == null) break;
      crumbs.insert(0, folder);
      iterId = folder.parentId;
    }
    
    // 2. Fetch subfolders
    final subQuery = db.select(db.folders)..where((f) => f.deletedAt.isNull());
    if (_currentFolderId == null) {
      subQuery.where((f) => f.parentId.isNull());
    } else {
      subQuery.where((f) => f.parentId.equals(_currentFolderId!));
    }
    
    var subs = await subQuery.get();
    
    // Exclude folder if defined
    if (widget.excludeFolderId != null) {
      final Set<String> excludedIds = {widget.excludeFolderId!};
      await _findNestedFolderIds(widget.excludeFolderId!, excludedIds, db);
      subs = subs.where((f) => !excludedIds.contains(f.id)).toList();
    }
    
    subs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (mounted) {
      setState(() {
        _breadcrumbs = crumbs;
        _subfolders = subs;
        _isLoading = false;
      });
    }
  }

  Future<void> _findNestedFolderIds(String parentId, Set<String> excludedIds, AeroDriveDatabase db) async {
    final subfolders = await (db.select(db.folders)..where((f) => f.parentId.equals(parentId) & f.deletedAt.isNull())).get();
    for (final folder in subfolders) {
      excludedIds.add(folder.id);
      await _findNestedFolderIds(folder.id, excludedIds, db);
    }
  }

  Future<void> _handleCreateFolder(BuildContext context) async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Folder name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    final settingsRepo = ref.read(settingsRepositoryProvider);
    final targetChannel = await ChannelLoadBalancer.selectStorageChannel(settings: settingsRepo);
    final masterKey = ref.read(masterKeyProvider);

    if (targetChannel == null || masterKey == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vault is locked or storage channels are not set up. Cannot create folder.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    final folderRepo = ref.read(folderRepositoryProvider);
    final newFolderId = await folderRepo.createFolder(
      name: name,
      parentId: _currentFolderId,
      color: '0xFF60A5FA', // Default Blue
    );

    // Refresh directory view immediately
    await _loadCurrentFolderContents();

    // Trigger manifest upload in background (non-blocking)
    unawaited(() async {
      File? tempFile;
      try {
        final chatId = targetChannel['id'] is String ? int.parse(targetChannel['id']) : targetChannel['id'] as int;
        final cipher = AesGcm.with256bits();
        final secretKey = await cipher.newSecretKeyFromBytes(masterKey);
        final manifestCaption = await ManifestEncoder.encodeFolderManifest(
          folderId: newFolderId,
          folderName: name,
          parentFolderId: _currentFolderId,
          masterKey: secretKey,
          color: '0xFF60A5FA',
        );

        final tempDir = await getTemporaryDirectory();
        tempFile = File('${tempDir.path}/folder_$newFolderId.png');
        final pngBytes = Uint8List.fromList([
          137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 108, 137, 0, 0, 0, 11, 73, 68, 65, 84, 120, 156, 99, 96, 0, 0, 0, 2, 0, 1, 226, 33, 188, 51, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130
        ]);
        await tempFile.writeAsBytes(pngBytes);

        final targetAccountId = targetChannel['accountId']?.toString();
        final accounts = ref.read(telegramManagerProvider);
        final telegram = (targetAccountId != null && targetAccountId.isNotEmpty)
            ? accounts.firstWhere(
                (c) => c.accountId == targetAccountId,
                orElse: () => ref.read(telegramServiceProvider.notifier),
              )
            : ref.read(telegramServiceProvider.notifier);

        await telegram.uploadDocument(chatId, tempFile.path, caption: manifestCaption);
      } catch (_) {
      } finally {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    }());
  }

  @override
  Widget build(BuildContext context) => Dialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(16),
        height: 450,
        child: Column(
          children: [
            // Title Header with Create Folder option
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(color: AppColors.onSurface, fontSize: 15, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.create_new_folder_outlined, color: AppColors.primary),
                  onPressed: () => _handleCreateFolder(context),
                  tooltip: 'Create New Folder',
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Breadcrumbs path
            _buildBreadcrumbs(),
            const Divider(color: Colors.white10),
            
            // Folder List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _subfolders.isEmpty
                      ? Center(
                          child: Text('No subfolders found.', style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13)),
                        )
                      : ListView.builder(
                          itemCount: _subfolders.length,
                          itemBuilder: (context, index) {
                            final folder = _subfolders[index];
                            Color color = Colors.blueAccent;
                            if (folder.color != null && folder.color!.isNotEmpty) {
                              try {
                                var colorStr = folder.color!;
                                if (colorStr.startsWith('#')) {
                                  colorStr = colorStr.replaceFirst('#', '0xFF');
                                } else if (!colorStr.startsWith('0x') && !colorStr.startsWith('0X')) {
                                  colorStr = '0x$colorStr';
                                }
                                color = Color(int.parse(colorStr));
                              } catch (_) {}
                            }
                            
                            return ListTile(
                              leading: Icon(Icons.folder, color: color),
                              title: Text(folder.name, style: TextStyle(color: AppColors.onSurface, fontSize: 14)),
                              trailing: Icon(Icons.chevron_right, color: AppColors.onSurfaceVariant.withOpacity(0.5)),
                              onTap: () {
                                setState(() {
                                  _currentFolderId = folder.id;
                                });
                                _loadCurrentFolderContents();
                              },
                            );
                          },
                        ),
            ),
            
            const Divider(color: Colors.white10),
            
            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    // Return the picked directory ID. We use '__root__' if root is picked.
                    Navigator.pop(context, _currentFolderId ?? '__root__');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Select folder', style: TextStyle(color: AppColors.onPrimary)),
                ),
              ],
            ),
          ],
        ),
      ),
    );

  Widget _buildBreadcrumbs() => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Root Button
          InkWell(
            onTap: () {
              setState(() {
                _currentFolderId = null;
              });
              _loadCurrentFolderContents();
            },
            child: Text('My Drive', style: TextStyle(color: AppColors.primary, fontSize: 13)),
          ),
          for (final crumb in _breadcrumbs) ...[
            Icon(Icons.chevron_right, color: AppColors.onSurfaceVariant.withOpacity(0.5), size: 16),
            InkWell(
              onTap: () {
                setState(() {
                  _currentFolderId = crumb.id;
                });
                _loadCurrentFolderContents();
              },
              child: Text(crumb.name, style: TextStyle(color: AppColors.primary, fontSize: 13)),
            ),
          ]
        ],
      ),
    );
}
