import 'dart:convert';
import 'dart:io' as io;

import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/db/database.dart';
import '../../domain/ai/face_recognition_service.dart' hide FaceCluster;
import '../../domain/ai/face_recognition_service.dart' show faceClustersProvider;
import '../../domain/backup_service.dart';
import '../drive/providers/drive_providers.dart';
import '../gallery/gallery_screen.dart';
import '../telegram/telegram_manager.dart';
import '../telegram/telegram_service.dart';
import '../trash/trash_screen.dart';

class BackupExportDialog extends ConsumerStatefulWidget {
  const BackupExportDialog({super.key});

  @override
  ConsumerState<BackupExportDialog> createState() => _BackupExportDialogState();
}

class _BackupExportDialogState extends ConsumerState<BackupExportDialog> {
  bool _exportDatabase = true;
  bool _exportSettings = true;
  bool _isLoading = false;
  String? _successPath;

  Future<String?> _getSavePath() async {
    if (io.Platform.isAndroid || io.Platform.isIOS) {
      final dir = await getApplicationDocumentsDirectory();
      return p.join(dir.path, 'aerodrive_backup.aerobackup');
    }

    try {
      const typeGroup = XTypeGroup(
        label: 'AeroDrive Backup (*.aerobackup)',
        extensions: <String>['aerobackup'],
      );
      final FileSaveLocation? result = await getSaveLocation(
        suggestedName: 'aerodrive_backup.aerobackup',
        acceptedTypeGroups: [typeGroup],
      );
      return result?.path;
    } catch (e) {
      final dir = await getApplicationDocumentsDirectory();
      return p.join(dir.path, 'aerodrive_backup.aerobackup');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.download, color: AppColors.secondary),
          SizedBox(width: 12),
          Text('Export Backup', style: TextStyle(color: Colors.white)),
        ],
      ),
      content: _successPath != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: AppColors.success, size: 48),
                const SizedBox(height: 16),
                const Text('Backup exported successfully!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.outline),
                  ),
                  child: Text(_successPath!, style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12), textAlign: TextAlign.center),
                ),
              ],
            )
          : _isLoading
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: AppColors.primary),
                    const SizedBox(height: 16),
                    Text('Exporting backup data...', style: TextStyle(color: AppColors.onSurfaceVariant)),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                  'Select what you want to export to a secure backup file:',
                  style: TextStyle(color: AppColors.onSurface),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text('Database Data', style: TextStyle(color: Colors.white)),
                  subtitle: Text('Files, folders, chunks, channels, accounts, faces', style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12)),
                  value: _exportDatabase,
                  activeColor: AppColors.primary,
                  checkColor: Colors.white,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) {
                    setState(() {
                      _exportDatabase = v ?? false;
                    });
                  },
                ),
                CheckboxListTile(
                  title: const Text('Application Settings', style: TextStyle(color: Colors.white)),
                  subtitle: Text('Preferences, timeouts, toggles', style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12)),
                  value: _exportSettings,
                  activeColor: AppColors.primary,
                  checkColor: Colors.white,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) {
                    setState(() {
                      _exportSettings = v ?? false;
                    });
                  },
                ),
              ],
            ),
      actions: _successPath != null
          ? [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ]
          : _isLoading
              ? null
              : [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
                  ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: (!_exportDatabase && !_exportSettings)
                    ? null
                    : () async {
                        setState(() {
                          _isLoading = true;
                        });
                        try {
                          final path = await _getSavePath();
                          if (path == null) {
                            setState(() {
                              _isLoading = false;
                            });
                            return;
                          }

                          final backupService = ref.read(backupServiceProvider);
                          await backupService.exportBackup(
                            exportDatabase: _exportDatabase,
                            exportSettings: _exportSettings,
                            customPath: path,
                          );

                          if (mounted) {
                            setState(() {
                              _isLoading = false;
                              _successPath = path;
                            });
                          }
                        } catch (e) {
                          if (mounted) {
                            setState(() {
                              _isLoading = false;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error exporting backup: $e'),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        }
                      },
                child: const Text('Export'),
              ),
            ],
    );
}

enum ImportStage { selectFile, configureImport, loading }

class BackupImportDialog extends ConsumerStatefulWidget {
  const BackupImportDialog({super.key});

  @override
  ConsumerState<BackupImportDialog> createState() => _BackupImportDialogState();
}

class _BackupImportDialogState extends ConsumerState<BackupImportDialog> {
  ImportStage _stage = ImportStage.selectFile;
  Map<String, dynamic>? _backupData;
  String? _selectedFilePath;

  bool _importDatabase = false;
  bool _importSettings = false;
  bool _mergeDatabase = true;

  int _folderCount = 0;
  int _fileCount = 0;
  int _settingsCount = 0;

  Future<void> _pickFile() async {
    try {
      XFile? file;
      try {
        const typeGroup = XTypeGroup(
          label: 'AeroDrive Backup (*.aerobackup)',
          extensions: <String>['aerobackup'],
        );
        file = await openFile(acceptedTypeGroups: [typeGroup]);
      } catch (e) {
        final dir = await getApplicationDocumentsDirectory();
        final path = p.join(dir.path, 'aerodrive_backup.aerobackup');
        final fallbackFile = io.File(path);
        if (await fallbackFile.exists()) {
          file = XFile(path);
        } else {
          throw Exception(
            'System file picker is unavailable, and no backup file was found in the App Documents directory at "aerodrive_backup.aerobackup". To restore, place your backup file there.',
          );
        }
      }

      if (file == null) return;

      setState(() {
        _stage = ImportStage.loading;
      });

      final content = await file.readAsString();
      final data = jsonDecode(content);

      if (data is! Map<String, dynamic> || data['version'] == null || (!data.containsKey('database') && !data.containsKey('settings'))) {
        throw const FormatException('Invalid backup file format.');
      }

      var folderCount = 0;
      var fileCount = 0;
      var settingsCount = 0;

      final hasDb = data.containsKey('database');
      final hasSettings = data.containsKey('settings');

      if (hasDb) {
        final dbData = data['database'] as Map<String, dynamic>;
        folderCount = (dbData['folders'] as List?)?.length ?? 0;
        fileCount = (dbData['files'] as List?)?.length ?? 0;
      }

      if (hasSettings) {
        settingsCount = (data['settings'] as List?)?.length ?? 0;
      }

      setState(() {
        _backupData = data;
        _selectedFilePath = file!.path;
        _importDatabase = hasDb;
        _importSettings = hasSettings;
        _folderCount = folderCount;
        _fileCount = fileCount;
        _settingsCount = settingsCount;
        _stage = ImportStage.configureImport;
      });
    } catch (e) {
      setState(() {
        _stage = ImportStage.selectFile;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to read backup file: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Map<String, dynamic> _sanitizeMergeData(
    Map<String, dynamic> data,
    Set<String> localFolderIds,
    Set<String> localFileIds,
    Set<String> localTagIds,
    Set<String> localFaceClusterIds,
  ) {
    final List<FolderData> importedFolders = (data['folders'] as List?)?.map((e) => FolderData.fromJson(e as Map<String, dynamic>)).toList() ?? [];
    final List<FileData> importedFiles = (data['files'] as List?)?.map((e) => FileData.fromJson(e as Map<String, dynamic>)).toList() ?? [];
    final List<ChunkData> importedChunks = (data['chunks'] as List?)?.map((e) => ChunkData.fromJson(e as Map<String, dynamic>)).toList() ?? [];
    final List<Channel> importedChannels = (data['channels'] as List?)?.map((e) => Channel.fromJson(e as Map<String, dynamic>)).toList() ?? [];
    final List<Account> importedAccounts = (data['accounts'] as List?)?.map((e) => Account.fromJson(e as Map<String, dynamic>)).toList() ?? [];
    final List<Tag> importedTags = (data['tags'] as List?)?.map((e) => Tag.fromJson(e as Map<String, dynamic>)).toList() ?? [];
    final List<FileTag> importedFileTags = (data['file_tags'] as List?)?.map((e) => FileTag.fromJson(e as Map<String, dynamic>)).toList() ?? [];
    final List<ShareLinkData> importedShares = (data['shares'] as List?)?.map((e) => ShareLinkData.fromJson(e as Map<String, dynamic>)).toList() ?? [];
    final List<TransferQueueData> importedTransferQueue = (data['transfer_queue'] as List?)?.map((e) => TransferQueueData.fromJson(e as Map<String, dynamic>)).toList() ?? [];
    final List<FaceCluster> importedFaceClusters = (data['face_clusters'] as List?)?.map((e) => FaceCluster.fromJson(e as Map<String, dynamic>)).toList() ?? [];
    final List<PhotoFace> importedPhotoFaces = (data['photo_faces'] as List?)?.map((e) => PhotoFace.fromJson(e as Map<String, dynamic>)).toList() ?? [];
    final List<BackupHistoryData> importedBackupHistory = (data['backup_history'] as List?)?.map((e) => BackupHistoryData.fromJson(e as Map<String, dynamic>)).toList() ?? [];

    final allFolderIds = {...localFolderIds, ...importedFolders.map((e) => e.id)};
    final allFileIds = {...localFileIds, ...importedFiles.map((e) => e.id)};
    final allTagIds = {...localTagIds, ...importedTags.map((e) => e.id)};
    final allFaceClusterIds = {...localFaceClusterIds, ...importedFaceClusters.map((e) => e.id)};

    final sanitizedFolders = importedFolders.map((f) {
      if (f.parentId != null && !allFolderIds.contains(f.parentId)) {
        return f.copyWith(parentId: const Value(null));
      }
      return f;
    }).toList();

    final sanitizedFiles = importedFiles.map((f) {
      if (f.folderId != null && !allFolderIds.contains(f.folderId)) {
        return f.copyWith(folderId: const Value(null));
      }
      return f;
    }).toList();

    final sanitizedChunks = importedChunks.where((c) => c.fileId != null && allFileIds.contains(c.fileId)).toList();

    final sanitizedFileTags = importedFileTags.where((ft) => allFileIds.contains(ft.fileId) && allTagIds.contains(ft.tagId)).toList();

    final sanitizedShares = importedShares.where((s) => s.fileId == null || allFileIds.contains(s.fileId)).toList();

    final sanitizedPhotoFaces = importedPhotoFaces.where((pf) => allFileIds.contains(pf.fileId) && allFaceClusterIds.contains(pf.faceClusterId)).toList();

    return {
      'folders': sanitizedFolders,
      'files': sanitizedFiles,
      'chunks': sanitizedChunks,
      'file_tags': sanitizedFileTags,
      'shares': sanitizedShares,
      'photo_faces': sanitizedPhotoFaces,
      'accounts': importedAccounts,
      'channels': importedChannels,
      'tags': importedTags,
      'face_clusters': importedFaceClusters,
      'transfer_queue': importedTransferQueue,
      'backup_history': importedBackupHistory,
    };
  }

  Future<void> _executeImport() async {
    if (_backupData == null) return;
    setState(() {
      _stage = ImportStage.loading;
    });

    try {
      final db = ref.read(databaseProvider);

      if (_importDatabase && _backupData!.containsKey('database')) {
        final dbData = _backupData!['database'] as Map<String, dynamic>;

        final Set<String> localFolderIds = {};
        final Set<String> localFileIds = {};
        final Set<String> localTagIds = {};
        final Set<String> localFaceClusterIds = {};

        if (_mergeDatabase) {
          final folders = await db.select(db.folders).get();
          final files = await db.select(db.files).get();
          final tags = await db.select(db.tags).get();
          final faceClusters = await db.select(db.faceClusters).get();

          localFolderIds.addAll(folders.map((e) => e.id));
          localFileIds.addAll(files.map((e) => e.id));
          localTagIds.addAll(tags.map((e) => e.id));
          localFaceClusterIds.addAll(faceClusters.map((e) => e.id));
        }

        final sanitized = _sanitizeMergeData(
          dbData,
          localFolderIds,
          localFileIds,
          localTagIds,
          localFaceClusterIds,
        );

        await db.transaction(() async {
          await db.customStatement('PRAGMA foreign_keys = OFF;');

          if (!_mergeDatabase) {
            await db.delete(db.backupHistory).go();
            await db.delete(db.transferQueue).go();
            await db.delete(db.photoFaces).go();
            await db.delete(db.shareLinks).go();
            await db.delete(db.fileTags).go();
            await db.delete(db.chunks).go();
            await db.delete(db.files).go();
            await db.delete(db.folders).go();
            await db.delete(db.faceClusters).go();
            await db.delete(db.tags).go();
            await db.delete(db.channels).go();
            await db.delete(db.accounts).go();
          }

          await db.batch((batch) {
            final accounts = sanitized['accounts'] as List<Account>;
            if (accounts.isNotEmpty) {
              batch.insertAll(db.accounts, accounts, mode: InsertMode.insertOrReplace);
            }

            final channels = sanitized['channels'] as List<Channel>;
            if (channels.isNotEmpty) {
              batch.insertAll(db.channels, channels, mode: InsertMode.insertOrReplace);
            }

            final tags = sanitized['tags'] as List<Tag>;
            if (tags.isNotEmpty) {
              batch.insertAll(db.tags, tags, mode: InsertMode.insertOrReplace);
            }

            final faceClusters = sanitized['face_clusters'] as List<FaceCluster>;
            if (faceClusters.isNotEmpty) {
              batch.insertAll(db.faceClusters, faceClusters, mode: InsertMode.insertOrReplace);
            }

            final folders = sanitized['folders'] as List<FolderData>;
            if (folders.isNotEmpty) {
              batch.insertAll(db.folders, folders, mode: InsertMode.insertOrReplace);
            }

            final files = sanitized['files'] as List<FileData>;
            if (files.isNotEmpty) {
              batch.insertAll(db.files, files, mode: InsertMode.insertOrReplace);
            }

            final chunks = sanitized['chunks'] as List<ChunkData>;
            if (chunks.isNotEmpty) {
              batch.insertAll(db.chunks, chunks, mode: InsertMode.insertOrReplace);
            }

            final fileTags = sanitized['file_tags'] as List<FileTag>;
            if (fileTags.isNotEmpty) {
              batch.insertAll(db.fileTags, fileTags, mode: InsertMode.insertOrReplace);
            }

            final shares = sanitized['shares'] as List<ShareLinkData>;
            if (shares.isNotEmpty) {
              batch.insertAll(db.shareLinks, shares, mode: InsertMode.insertOrReplace);
            }

            final photoFaces = sanitized['photo_faces'] as List<PhotoFace>;
            if (photoFaces.isNotEmpty) {
              batch.insertAll(db.photoFaces, photoFaces, mode: InsertMode.insertOrReplace);
            }

            final transferQueue = sanitized['transfer_queue'] as List<TransferQueueData>;
            if (transferQueue.isNotEmpty) {
              batch.insertAll(db.transferQueue, transferQueue, mode: InsertMode.insertOrReplace);
            }

            final backupHistory = sanitized['backup_history'] as List<BackupHistoryData>;
            if (backupHistory.isNotEmpty) {
              batch.insertAll(db.backupHistory, backupHistory, mode: InsertMode.insertOrReplace);
            }
          });

          await db.customStatement('PRAGMA foreign_keys = ON;');
        });
      }

      if (_importSettings && _backupData!.containsKey('settings')) {
        final List<dynamic> settingsList = _backupData!['settings'];
        final importedSettings = settingsList.map((e) => Setting.fromJson(e as Map<String, dynamic>)).toList();

        await db.transaction(() async {
          await db.delete(db.settings).go();
          await db.batch((batch) {
            batch.insertAll(db.settings, importedSettings);
          });
        });
      }

      ref.read(settingsUpdateProvider.notifier).state++;
      ref.invalidate(folderContentsProvider);
      ref.invalidate(breadcrumbsProvider);
      ref.invalidate(mediaFilesProvider);
      ref.invalidate(trashedItemsProvider);
      ref.invalidate(telegramManagerProvider);
      ref.invalidate(faceClustersProvider);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Backup imported successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _stage = ImportStage.configureImport;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error restoring backup: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    List<Widget>? actions;

    switch (_stage) {
      case ImportStage.selectFile:
        content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Select a .aerobackup file from your local storage to restore your data or settings.',
              style: TextStyle(color: AppColors.onSurface),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.outline),
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _pickFile,
              icon: const Icon(Icons.file_open, color: AppColors.secondary),
              label: const Text('Choose Backup File', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
        actions = [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
          ),
        ];

      case ImportStage.configureImport:
        content = SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.outline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: AppColors.secondary),
                        SizedBox(width: 8),
                        Text(
                          'Backup File Loaded',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Path: ${_selectedFilePath != null ? p.basename(_selectedFilePath!) : ""}',
                      style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Select elements to import:',
                style: TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (_backupData!.containsKey('database'))
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Database Data', style: TextStyle(color: Colors.white)),
                  subtitle: Text('$_fileCount files, $_folderCount folders', style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 11)),
                  value: _importDatabase,
                  activeColor: AppColors.primary,
                  checkColor: Colors.white,
                  onChanged: (v) => setState(() => _importDatabase = v ?? false),
                )
              else
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Database Data', style: TextStyle(color: Colors.white54)),
                  subtitle: Text('Not available in backup file', style: TextStyle(color: Colors.white30, fontSize: 11)),
                  trailing: Icon(Icons.block, size: 16, color: Colors.white30),
                ),
              if (_backupData!.containsKey('settings'))
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Application Settings', style: TextStyle(color: Colors.white)),
                  subtitle: Text('$_settingsCount configuration keys', style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 11)),
                  value: _importSettings,
                  activeColor: AppColors.primary,
                  checkColor: Colors.white,
                  onChanged: (v) => setState(() => _importSettings = v ?? false),
                )
              else
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Application Settings', style: TextStyle(color: Colors.white54)),
                  subtitle: Text('Not available in backup file', style: TextStyle(color: Colors.white30, fontSize: 11)),
                  trailing: Icon(Icons.block, size: 16, color: Colors.white30),
                ),
              if (_importDatabase) ...[
                const SizedBox(height: 16),
                Divider(color: AppColors.outline),
                const SizedBox(height: 8),
                Text(
                  'Database Import Mode:',
                  style: TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                RadioListTile<bool>(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Merge with local database', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text('Safely combines data; updates matching IDs, preserves rest', style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 11)),
                  value: true,
                  groupValue: _mergeDatabase,
                  activeColor: AppColors.secondary,
                  onChanged: (v) => setState(() => _mergeDatabase = v!),
                ),
                RadioListTile<bool>(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Overwrite current database', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text('Wipes existing files, folders, and history before restore', style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 11)),
                  value: false,
                  groupValue: _mergeDatabase,
                  activeColor: AppColors.error,
                  onChanged: (v) => setState(() => _mergeDatabase = v!),
                ),
                if (!_mergeDatabase) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'WARNING: Overwriting will permanently delete all your current local directories, file pointers, shares, and faces. This action is irreversible.',
                            style: TextStyle(color: AppColors.error, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
        actions = [
          TextButton(
            onPressed: () => setState(() {
              _stage = ImportStage.selectFile;
              _backupData = null;
              _selectedFilePath = null;
            }),
            child: Text('Back', style: TextStyle(color: AppColors.onSurfaceVariant)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: (!_importDatabase && !_importSettings)
                  ? Colors.grey
                  : (_importDatabase && !_mergeDatabase ? AppColors.error : AppColors.primary),
              foregroundColor: Colors.white,
            ),
            onPressed: (!_importDatabase && !_importSettings) ? null : _executeImport,
            child: const Text('Import'),
          ),
        ];

      case ImportStage.loading:
        content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              'Importing backup data...',
              style: TextStyle(color: AppColors.onSurfaceVariant),
            ),
          ],
        );
        actions = null;
    }

    return AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(_stage == ImportStage.configureImport && _importDatabase && !_mergeDatabase ? Icons.warning_amber_rounded : Icons.upload, color: _stage == ImportStage.configureImport && _importDatabase && !_mergeDatabase ? AppColors.error : AppColors.secondary),
          const SizedBox(width: 12),
          const Text('Import Backup', style: TextStyle(color: Colors.white)),
        ],
      ),
      content: content,
      actions: actions,
    );
  }
}


class BackupScheduleDialog extends ConsumerStatefulWidget {
  const BackupScheduleDialog({super.key});

  @override
  ConsumerState<BackupScheduleDialog> createState() => _BackupScheduleDialogState();
}

class _BackupScheduleDialogState extends ConsumerState<BackupScheduleDialog> {
  String _selected = 'weekly';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = ref.read(settingsRepositoryProvider);
    final val = await settings.getSetting('auto_backup_schedule') ?? 'weekly';
    if (mounted) {
      setState(() {
        _selected = val;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const AlertDialog(content: SizedBox(height: 100, child: Center(child: CircularProgressIndicator())));

    return AlertDialog(
      title: const Text('Auto-Backup Schedule'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioListTile(
            title: const Text('Daily'),
            value: 'daily',
            groupValue: _selected,
            onChanged: (val) => setState(() => _selected = val.toString()),
          ),
          RadioListTile(
            title: const Text('Weekly'),
            value: 'weekly',
            groupValue: _selected,
            onChanged: (val) => setState(() => _selected = val.toString()),
          ),
          RadioListTile(
            title: const Text('Monthly'),
            value: 'monthly',
            groupValue: _selected,
            onChanged: (val) => setState(() => _selected = val.toString()),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final settings = ref.read(settingsRepositoryProvider);
            await settings.setSetting('auto_backup_schedule', _selected);
            if (!context.mounted) return;
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Schedule updated!')));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class TelegramSelfBackupDialog extends ConsumerWidget {
  const TelegramSelfBackupDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => AlertDialog(
      title: const Text('Telegram Self-Backup'),
      content: const Text('Send an encrypted copy of your SQLite database to your "Saved Messages" in Telegram.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: () async {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uploading to Saved Messages...')));
            
            try {
              final telegram = ref.read(telegramServiceProvider.notifier);
              final me = await telegram.getMe();
              if (me.containsKey('id')) {
                final userId = me['id'];
                
                final dbFolder = await getApplicationDocumentsDirectory();
                final dbPath = p.join(dbFolder.path, 'aerodrive.sqlite');
                
                if (await io.File(dbPath).exists()) {
                   await telegram.uploadDocument(userId, dbPath);
                   if (!context.mounted) return;
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup sent to Saved Messages!')));
                   return;
                }
              }
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed: Database not found or not authenticated.'), backgroundColor: Colors.redAccent));
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
            }
          },
          icon: const Icon(Icons.send),
          label: const Text('Backup Now'),
        ),
      ],
    );
}
