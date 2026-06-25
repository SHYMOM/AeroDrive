import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_selector/file_selector.dart';
import 'package:aerodrive/core/theme/app_colors.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:aerodrive/features/drive/providers/drive_providers.dart';
import 'package:aerodrive/domain/folder_scanner.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/features/preview/preview_router.dart';
import 'package:go_router/go_router.dart';
import 'package:aerodrive/features/sharing/share_dialog.dart';
import 'package:aerodrive/features/sharing/share_service.dart';
import 'package:aerodrive/features/tags/tag_dialog.dart';
import 'package:aerodrive/features/tags/tag_providers.dart';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:aerodrive/domain/recovery/manifest_encoder.dart';
import 'package:aerodrive/core/providers/security_providers.dart';
import 'package:aerodrive/features/telegram/telegram_service.dart';

class DriveScreen extends ConsumerWidget {
  const DriveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentsAsync = ref.watch(folderContentsProvider);
    final isGrid = ref.watch(isGridViewProvider);
    final currentFolderId = ref.watch(currentFolderIdProvider);
    final db = ref.watch(databaseProvider);

    return DropTarget(
      onDragDone: (detail) async {
        final activeChannel = await ref.read(settingsRepositoryProvider).getSetting('active_channel_id');
        if (activeChannel == null && context.mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('No Storage Channel Selected'),
              content: const Text('Please go to Settings -> Storage Channels and select a Telegram channel or group to act as your backend storage before uploading files.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                )
              ],
            ),
          );
          return;
        }

        final scanner = ref.read(folderScannerProvider);
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Processing ${detail.files.length} dropped items...')),
          );
        }

        for (final XFile xfile in detail.files) {
          await scanner.scanAndQueueDirectory(xfile.path, currentFolderId);
        }

        // Refresh UI
        ref.invalidate(folderContentsProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Items queued for upload!')),
          );
        }
      },
      onDragEntered: (detail) {
        // Optional: show visual feedback
      },
      child: Scaffold(
        appBar: const _DriveAppBar(),
        body: contentsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Error: $err')),
          data: (contents) {
            final folders = contents['folders'] as List<FolderData>? ?? [];
            final files = contents['files'] as List<FileData>? ?? [];
            
            if (folders.isEmpty && files.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.folder_open, size: 64, color: Colors.white24),
                    SizedBox(height: 16),
                    Text('This folder is empty', style: TextStyle(color: Colors.white54)),
                    SizedBox(height: 8),
                    Text('Drag and drop files here to upload', style: TextStyle(color: Colors.white30, fontSize: 12)),
                  ],
                ),
              );
            }

            if (isGrid) {
              return _buildGridView(folders, files, ref);
            } else {
              return _buildListView(folders, files, ref);
            }
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            final activeChannel = await ref.read(settingsRepositoryProvider).getSetting('active_channel_id');
            if (activeChannel == null && context.mounted) {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('No Storage Channel Selected'),
                  content: const Text('Please go to Settings -> Storage Channels and select a Telegram channel or group to act as your backend storage before uploading files.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    )
                  ],
                ),
              );
              return;
            }

            final List<XFile> result = await openFiles();
            if (result.isNotEmpty) {
              final scanner = ref.read(folderScannerProvider);
              
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Processing ${result.length} selected items...')),
                );
              }

              for (final file in result) {
                await scanner.scanAndQueueDirectory(file.path, currentFolderId);
              }

              // Refresh UI
              ref.invalidate(folderContentsProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Items queued for upload!')),
                );
              }
            }
          },
          icon: const Icon(Icons.add),
          label: const Text('New'),
        ),
      ),
    );
  }

  Widget _buildGridView(List<FolderData> folders, List<FileData> files, WidgetRef ref) {
    final totalItems = folders.length + files.length;
    
    // Virtual Scrolling via builder
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
      ),
      itemCount: totalItems,
      itemBuilder: (context, index) {
        final disableAnimations = MediaQuery.of(context).disableAnimations;
        Widget child;
        if (index < folders.length) {
          child = _FolderGridItem(folder: folders[index]);
        } else {
          child = _FileGridItem(file: files[index - folders.length]);
        }

        if (disableAnimations) return child;

        return child.animate()
            .fadeIn(duration: 250.ms, delay: (index % 20 * 30).ms)
            .slideY(begin: 0.05, end: 0, duration: 250.ms, curve: Curves.easeOutQuad);
      },
    );
  }

  Widget _buildListView(List<FolderData> folders, List<FileData> files, WidgetRef ref) {
    final totalItems = folders.length + files.length;
    
    // Virtual Scrolling via builder
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: totalItems,
      itemBuilder: (context, index) {
        final disableAnimations = MediaQuery.of(context).disableAnimations;
        Widget child;
        if (index < folders.length) {
          child = _FolderListItem(folder: folders[index]);
        } else {
          child = _FileListItem(file: files[index - folders.length]);
        }

        if (disableAnimations) return child;

        return child.animate()
            .fadeIn(duration: 250.ms, delay: (index % 15 * 30).ms)
            .slideY(begin: 0.05, end: 0, duration: 250.ms, curve: Curves.easeOutQuad);
      },
    );
  }
}

class _DriveAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const _DriveAppBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final breadcrumbsAsync = ref.watch(breadcrumbsProvider);
    final isGrid = ref.watch(isGridViewProvider);

    return AppBar(
      title: breadcrumbsAsync.when(
        loading: () => const Text('Loading...'),
        error: (_, __) => const Text('AeroDrive'),
        data: (breadcrumbs) {
          if (breadcrumbs.isEmpty) return const Text('My Vault');
          
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                InkWell(
                  onTap: () => ref.read(currentFolderIdProvider.notifier).state = null,
                  child: const Text('My Vault', style: TextStyle(color: Colors.white70)),
                ),
                for (final folder in breadcrumbs) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Icon(Icons.chevron_right, size: 20, color: Colors.white54),
                  ),
                  InkWell(
                    onTap: () => ref.read(currentFolderIdProvider.notifier).state = folder.id,
                    child: Text(
                      folder.name, 
                      style: TextStyle(
                        fontWeight: folder == breadcrumbs.last ? FontWeight.bold : FontWeight.normal,
                        color: folder == breadcrumbs.last ? Colors.white : Colors.white70,
                      )
                    ),
                  ),
                ]
              ],
            ),
          );
        },
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Search',
          onPressed: () {
            context.push('/search');
          },
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Trash',
          onPressed: () {
            context.push('/trash');
          },
        ),
        IconButton(
          icon: const Icon(Icons.link),
          tooltip: 'Import Shared Link',
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) {
                final controller = TextEditingController();
                return AlertDialog(
                  title: const Text('Import Link'),
                  content: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'aerodrive://share?...',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, controller.text),
                      child: const Text('Import'),
                    ),
                  ],
                );
              },
            ).then((url) async {
              if (url != null && url.toString().trim().isNotEmpty) {
                try {
                  await ref.read(shareServiceProvider).importShareLink(url.toString().trim());
                  ref.invalidate(folderContentsProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File imported successfully!')));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              }
            });
          },
        ),
        IconButton(
          icon: const Icon(Icons.create_new_folder_outlined),
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) {
                final controller = TextEditingController();
                return AlertDialog(
                  title: const Text('New Folder'),
                  content: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Folder name',
                    ),
                    onSubmitted: (val) {
                      Navigator.pop(context, val);
                    },
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, controller.text),
                      child: const Text('Create'),
                    ),
                  ],
                );
              },
            ).then((name) async {
              if (name != null && name.toString().trim().isNotEmpty) {
                final folderRepo = ref.read(folderRepositoryProvider);
                final currentId = ref.read(currentFolderIdProvider);
                try {
                  final newFolderId = await folderRepo.createFolder(name: name.toString().trim(), parentId: currentId);
                  ref.invalidate(folderContentsProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Folder created!')));
                  }

                  // Sync folder creation manifest to Telegram in background
                  final activeChannelStr = await ref.read(settingsRepositoryProvider).getSetting('active_channel_id');
                  final masterKey = ref.read(masterKeyProvider);
                  if (activeChannelStr != null && masterKey != null) {
                    final chatId = int.parse(activeChannelStr);
                    final cipher = AesGcm.with256bits();
                    final secretKey = await cipher.newSecretKeyFromBytes(masterKey);
                    final manifestCaption = await ManifestEncoder.encodeFolderManifest(
                      folderId: newFolderId,
                      folderName: name.toString().trim(),
                      parentFolderId: currentId,
                      masterKey: secretKey,
                    );

                    final tempDir = await getTemporaryDirectory();
                    final tempFile = File('${tempDir.path}/folder_$newFolderId.png');
                    final pngBytes = Uint8List.fromList([
                      137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 108, 137, 0, 0, 0, 11, 73, 68, 65, 84, 120, 156, 99, 96, 0, 0, 0, 2, 0, 1, 226, 33, 188, 51, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130
                    ]);
                    await tempFile.writeAsBytes(pngBytes);

                    final telegram = ref.read(telegramServiceProvider.notifier);
                    await telegram.uploadDocument(chatId, tempFile.path, caption: manifestCaption);

                    if (await tempFile.exists()) {
                      await tempFile.delete();
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              }
            });
          },
        ),
        IconButton(
          icon: Icon(isGrid ? Icons.view_list : Icons.grid_view),
          onPressed: () {
            ref.read(isGridViewProvider.notifier).state = !isGrid;
          },
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

// --- Item Widgets ---

class _FolderGridItem extends ConsumerWidget {
  final FolderData folder;
  const _FolderGridItem({required this.folder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => ref.read(currentFolderIdProvider.notifier).state = folder.id,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder, size: 48, color: folder.color != null ? Color(int.parse(folder.color!)) : Colors.blueAccent),
            const SizedBox(height: 8),
            Text(folder.name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _FileGridItem extends ConsumerWidget {
  final FileData file;
  const _FileGridItem({required this.file});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () {
        PreviewRouter.openPreview(context, file);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                padding: EdgeInsets.zero,
                onSelected: (value) async {
                  if (value == 'download') {
                    final db = ref.read(databaseProvider);
                    await db.into(db.transferQueue).insert(
                      TransferQueueCompanion.insert(
                        id: const Uuid().v4(),
                        fileId: drift.Value(file.id),
                        type: const drift.Value('DOWNLOAD_FILE'),
                        status: const drift.Value('PENDING'),
                        priority: const drift.Value(1),
                        createdAt: drift.Value(DateTime.now()),
                      )
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Queued ${file.name} for download...')));
                    }
                  } else if (value == 'share') {
                    showDialog(
                      context: context,
                      builder: (context) => ShareDialog(file: file),
                    );
                  } else if (value == 'tags') {
                    TagDialog.show(context, file);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'download', child: Text('Download')),
                  const PopupMenuItem(value: 'share', child: Text('Share Link')),
                  const PopupMenuItem(value: 'tags', child: Text('Tags')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
            const Icon(Icons.insert_drive_file, size: 36, color: Colors.grey),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(file.name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            ),
            const SizedBox(height: 4),
            _FileTagsRow(fileId: file.id),
          ],
        ),
      ),
    );
  }
}

class _FolderListItem extends ConsumerWidget {
  final FolderData folder;
  const _FolderListItem({required this.folder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: Icon(Icons.folder, color: folder.color != null ? Color(int.parse(folder.color!)) : Colors.blueAccent),
      title: Text(folder.name),
      trailing: IconButton(
        icon: const Icon(Icons.more_vert),
        onPressed: () {
          // TODO: Context menu (Trash, Rename, etc.)
          final folderRepo = ref.read(folderRepositoryProvider);
          // Show confirmation then folderRepo.trashFolder(folder.id)
        },
      ),
      onTap: () => ref.read(currentFolderIdProvider.notifier).state = folder.id,
    );
  }
}

class _FileListItem extends ConsumerWidget {
  final FileData file;
  const _FileListItem({required this.file});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.insert_drive_file, color: Colors.grey),
      title: Text(file.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${(file.size ?? 0) ~/ 1024} KB'),
          const SizedBox(height: 4),
          _FileTagsRow(fileId: file.id),
        ],
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'download') {
            final db = ref.read(databaseProvider);
            await db.into(db.transferQueue).insert(
              TransferQueueCompanion.insert(
                id: const Uuid().v4(),
                fileId: drift.Value(file.id),
                type: const drift.Value('DOWNLOAD_FILE'),
                status: const drift.Value('PENDING'),
                priority: const drift.Value(1),
                createdAt: drift.Value(DateTime.now()),
              )
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Queued ${file.name} for download...')));
            }
          } else if (value == 'share') {
            showDialog(
              context: context,
              builder: (context) => ShareDialog(file: file),
            );
          } else if (value == 'tags') {
            TagDialog.show(context, file);
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'download', child: Text('Download')),
          const PopupMenuItem(value: 'share', child: Text('Share Link')),
          const PopupMenuItem(value: 'tags', child: Text('Tags')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
      onTap: () {
        PreviewRouter.openPreview(context, file);
      },
    );
  }
}

class _FileTagsRow extends ConsumerWidget {
  final String fileId;
  const _FileTagsRow({required this.fileId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(fileTagsStreamProvider(fileId));
    
    return tagsAsync.when(
      data: (tags) {
        if (tags.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: tags.map((tag) {
                final color = tag.color != null ? HexColor.fromHex(tag.color!) : Colors.grey;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      tag.name,
                      style: TextStyle(
                        color: color.contrastColor,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
