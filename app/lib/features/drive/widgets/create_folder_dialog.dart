import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/core/theme/app_colors.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';
import 'package:aerodrive/data/repositories/folder_repository.dart';
import 'package:aerodrive/features/drive/providers/drive_providers.dart';
import 'package:aerodrive/domain/recovery/manifest_encoder.dart';
import 'package:aerodrive/core/providers/security_providers.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/features/telegram/telegram_service.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:typed_data';

class CreateFolderDialog extends ConsumerStatefulWidget {
  const CreateFolderDialog({super.key});

  @override
  ConsumerState<CreateFolderDialog> createState() => _CreateFolderDialogState();
}

class _CreateFolderDialogState extends ConsumerState<CreateFolderDialog> {
  final _nameController = TextEditingController();
  String _selectedColorHex = '0xFF60A5FA'; // Default Blue

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      title: const Text('New Folder', style: TextStyle(color: AppColors.onSurface)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            style: const TextStyle(color: AppColors.onSurface),
            decoration: InputDecoration(
              hintText: 'Folder name',
              hintStyle: TextStyle(color: AppColors.onSurfaceVariant),
              filled: true,
              fillColor: AppColors.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Folder Color',
              style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            width: double.maxFinite,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: AppColors.folderColors.entries.map((entry) {
                final hex = '0x${entry.value.value.toRadixString(16).toUpperCase()}';
                final isSelected = _selectedColorHex == hex;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedColorHex = hex;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 12),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: entry.value,
                      border: isSelected ? Border.all(color: Colors.white, width: 3) : null,
                    ),
                  ),
                );
              }).toList(),
            ),
          )
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
        ),
        ElevatedButton(
          onPressed: () async {
            final name = _nameController.text.trim();
            if (name.isNotEmpty) {
              final folderRepo = ref.read(folderRepositoryProvider);
              final currentId = ref.read(currentFolderIdProvider);
              
              final newFolderId = await folderRepo.createFolder(
                name: name,
                parentId: currentId,
                color: _selectedColorHex,
              );
              ref.invalidate(folderContentsProvider);
              
              if (mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Folder created!')),
                );
              }
              
              // Background manifest sync
              try {
                final activeChannelStr = await ref.read(settingsRepositoryProvider).getSetting('active_channel_id');
                final masterKey = ref.read(masterKeyProvider);
                if (activeChannelStr != null && masterKey != null) {
                  final chatId = int.parse(activeChannelStr);
                  final cipher = AesGcm.with256bits();
                  final secretKey = await cipher.newSecretKeyFromBytes(masterKey);
                  final manifestCaption = await ManifestEncoder.encodeFolderManifest(
                    folderId: newFolderId,
                    folderName: name,
                    parentFolderId: currentId,
                    masterKey: secretKey,
                  );

                  final tempDir = await getTemporaryDirectory();
                  final tempFile = File('\${tempDir.path}/folder_$newFolderId.png');
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
                // Ignore sync errors here
              }
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
          ),
          child: const Text('Create'),
        ),
      ],
    );
  }
}
