# Graph Report - app  (2026-10-22)

## Corpus Check
- 211 files · ~175,941 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3697 nodes · 6163 edges · 175 communities (169 shown, 6 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS · INFERRED: 18 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `9ef28ff4`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- tables.dart
- telegram_service.dart
- media_screen.dart
- share_service.dart
- upload_queue_service.dart
- app_colors.dart
- webdav_server.dart
- GeneratedPluginRegistrant.swift
- databaseProvider
- app_router.dart
- drive_providers.dart
- folder_picker_dialog.dart
- FileData?
- main.dart
- download_queue_service.dart
- constants.dart
- auto_backup_settings_dialogs.dart
- settingsRepositoryProvider
- universal_file_viewer.dart
- backup_dialogs.dart
- auth_screen.dart
- faces_screen.dart
- package:drift/drift.dart
- settings_screen.dart
- accounts_screen.dart
- ml_service.dart
- ConsumerStatefulWidget
- otp_input.dart
- media_player_screen.dart
- drive_screen.dart
- multi_account_screen.dart
- my_application.cc
- currentFolderIdProvider
- integrity_verification_service.dart
- search_screen.dart
- premium_button.dart
- places_screen.dart
- telegramManagerProvider
- notification_service.dart
- media_gallery_screen.dart
- fullscreen_video_screen.dart
- theme_provider.dart
- dart:typed_data
- press_and_hold_preview.dart
- Color
- ConsumerState
- infrastructure_providers.dart
- smart_analyzer.dart
- auto_backup_watcher.dart
- integration_settings_dialogs.dart
- marquee_text.dart
- responsive_scaffold.dart
- ConsumerWidget
- testing_ended_screen.dart
- infrastructure_provisioning_service.dart
- webdav_settings_dialog.dart
- health_check_screen.dart
- ../data/db/database.dart
- api_service.dart
- streaming_server.dart
- package:flutter_riverpod/flutter_riverpod.dart
- decrypted_text_viewer.dart
- List
- Table
- core/providers/repository_providers.dart
- shared_links_screen.dart
- repository_providers.dart
- dropbox_backup_screen.dart
- file_list_item.dart
- advanced_settings_dialogs.dart
- transfers_screen.dart
- State
- archive_viewer.dart
- encryption_engine.dart
- package:flutter/material.dart
- StatelessWidget
- aerodrive_theme.dart
- package:path_provider/path_provider.dart
- decrypted_image_viewer.dart
- tag_dialog.dart
- win32_window.cpp
- AeroDriveBackupService
- realtime_sync_service.dart
- thumbnail_service.dart
- dart:io
- channels_screen.dart
- upload_orchestrator.dart
- debug_error_screen.dart
- appearance_settings_screen.dart
- folder_repository.dart
- config_sync_service.dart
- file_type_icon.dart
- file_grid_item.dart
- memories_screen.dart
- places_service.dart
- dropbox_service.dart
- FlutterWindow
- auth_provider.dart
- gallery_screen.dart
- logger.dart
- face_recognition_service.dart
- folder_picker_dialog.dart
- proxy_settings_screen.dart
- preview_router.dart
- manifest_encoder.dart
- channel_discovery_service.dart
- purge_job.dart
- backup_service.dart
- webdav_config.dart
- folder_scanner.dart
- Win32Window
- aerodrive_logo.dart
- video_gallery_screen.dart
- import_link_dialog.dart
- app_error.dart
- _AeroDriveAppState
- smart_tags_screen.dart
- about_screen.dart
- companion_server_dialogs.dart
- core/logger.dart
- dart:async
- video_thumbnail_service.dart
- wWinMain
- repository_test.dart
- network_settings_dialogs.dart
- isSelectionModeProvider
- media_settings_dialogs.dart
- splash_screen.dart
- purge_job.dart
- settings_repository.dart
- build
- backup_folder_mapper.dart
- manifest.json
- master_key_provider.dart
- MessageHandler
- file_decryption_util.dart
- dart:convert
- recovery_scanner.dart
- package:cryptography/cryptography.dart
- thumbnail_cache_service.dart
- phone_validator.dart
- _buildExploreTab
- BootReceiver
- DateTime
- propfind_handler.dart
- file_tags_row.dart
- MainActivity
- thumbnail_service.dart
- create_folder_dialog.dart
- MaterialPageRoute
- RegisterPlugins
- gallery_screen.dart
- aerodrive
- @your_bot_name
- int?
- String?
- takeout_importer_service.dart
- StatelessWidget
- State
- queue_repository.dart
- download_orchestrator.dart
- app_lock_screen.dart
- biometric_auth_service.dart
- duplicate_cleaner_service.dart
- ../core/providers.dart
- encryption_engine_test.dart
- package:path_provider/path_provider.dart
- return
- dart:math
- people_screen.dart
- streamingServerProvider
- _DigestSink

## God Nodes (most connected - your core abstractions)
1. `databaseProvider` - 80 edges
2. `settingsRepositoryProvider` - 74 edges
3. `telegramManagerProvider` - 37 edges
4. `dbRebuildVersionProvider` - 35 edges
5. `_DriveScreenState` - 31 edges
6. `thumbnailServiceProvider` - 25 edges
7. `telegramServiceProvider` - 25 edges
8. `masterKeyProvider` - 23 edges
9. `currentFolderIdProvider` - 23 edges
10. `Win32Window` - 22 edges

## Surprising Connections (you probably didn't know these)
- `MockSettingsRepository` --implements--> `SettingsRepository`  [EXTRACTED]
  test/features/telegram/api_credentials_test.dart → lib/data/repositories/settings_repository.dart
- `_handleStream` --references--> `databaseProvider`  [EXTRACTED]
  lib/domain/streaming/streaming_server.dart → lib/core/providers.dart
- `_loadFolderInfo` --references--> `databaseProvider`  [EXTRACTED]
  lib/features/drive/media_player_screen.dart → lib/core/providers.dart
- `_toggleFavorite` --references--> `databaseProvider`  [EXTRACTED]
  lib/features/drive/media_player_screen.dart → lib/core/providers.dart
- `_loadCurrentFolderContents` --references--> `databaseProvider`  [EXTRACTED]
  lib/features/drive/widgets/folder_picker_dialog.dart → lib/core/providers.dart

## Import Cycles
- None detected.

## Communities (175 total, 6 thin omitted)

### Community 0 - "tables.dart"
Cohesion: 0.02
Nodes (94): BlobColumn get, BoolColumn get, DateTimeColumn get, IntColumn get, accountId, adminArea, boxHeight, boxLeft (+86 more)

### Community 1 - "telegram_service.dart"
Cohesion: 0.02
Nodes (87): accountId, _activeAccountClientIds, activeInstances, addAdminToChat, addProxy, _apiHash, _apiId, authState (+79 more)

### Community 2 - "media_screen.dart"
Cohesion: 0.03
Nodes (65): _AlbumItemData, allFiles, allMedia, allTags, build, _buildActiveFiltersHeader, _buildAlbumCard, _buildBody (+57 more)

### Community 3 - "share_service.dart"
Cohesion: 0.04
Nodes (47): _addTempJoinedChannel, _archiveAndMute, _buildFlatImportList, channelId, cleanupInterruptedTempChannels, _copyAndReEncryptFile, _copyAndReEncryptFileResumable, createdAt (+39 more)

### Community 4 - "upload_queue_service.dart"
Cohesion: 0.04
Nodes (54): ../features/ml/ml_service.dart, ../features/places/places_service.dart, _abortedFileIds, _activeUploadDirs, ActiveUploadInfo, _allChunksSentAt, _calculateFileHash, chatId (+46 more)

### Community 5 - "app_colors.dart"
Cohesion: 0.04
Nodes (46): AppColors, background, error, fileArchive, fileAudio, fileCode, fileDocument, fileFolder (+38 more)

### Community 6 - "webdav_server.dart"
Cohesion: 0.04
Nodes (45): ../download_queue_service.dart, _activePort, _authMiddleware, creds, _delete, _downloadFile, _fromMainPort, _handleDelete (+37 more)

### Community 7 - "GeneratedPluginRegistrant.swift"
Cohesion: 0.05
Nodes (36): app_links, audio_session, battery_plus, Bool, Cocoa, cryptography_flutter, desktop_drop, file_picker (+28 more)

### Community 8 - "databaseProvider"
Cohesion: 0.11
Nodes (37): ../../domain/sync/config_sync_service.dart, databaseProvider, fileRepositoryProvider, folderRepositoryProvider, configSyncServiceProvider, _handleDeleteSelected, _showChannelSetupPrompt, _showDeleteConfirm (+29 more)

### Community 9 - "app_router.dart"
Cohesion: 0.05
Nodes (41): ChangeNotifier, ../../features/auth/auth_provider.dart, ../../features/auth/auth_screen.dart, ../../features/auth/infrastructure_setup_screen.dart, features/debug/debug_error_screen.dart, ../../features/drive/drive_screen.dart, ../../features/drive/quick_access_tools_screen.dart, ../../features/faces/faces_screen.dart (+33 more)

### Community 10 - "drive_providers.dart"
Cohesion: 0.05
Nodes (39): anyFile, audioCount, breadcrumbs, calculateFolderSize, categoryPriority, contents, copyWith, criteria (+31 more)

### Community 11 - "folder_picker_dialog.dart"
Cohesion: 0.08
Nodes (23): _allFolders, build, _buildFolderTile, _buildRootTile, _buildTree, _collectDescendantIds, createState, currentFolderId (+15 more)

### Community 12 - "FileData?"
Cohesion: 0.08
Nodes (30): ../drive/providers/drive_providers.dart, ../drive/widgets/press_and_hold_preview.dart, audioFiles, _AudioItem, audiosProvider, AudiosScreen, build, db (+22 more)

### Community 13 - "main.dart"
Cohesion: 0.05
Nodes (38): @pragma, AppLinks, core/routing/app_router.dart, domain/boot_service.dart, domain/notification_service.dart, domain/upload_crash_debugger.dart, features/sharing/share_service.dart, _appLinks (+30 more)

### Community 14 - "download_queue_service.dart"
Cohesion: 0.05
Nodes (38): ../download_orchestrator.dart, ActiveDownloadInfo, _activeDownloads, chunkIndex, _chunkTimeout, _completionController, _db, dispose (+30 more)

### Community 15 - "constants.dart"
Cohesion: 0.06
Nodes (33): animFast, animNormal, animSlow, AppConstants, appName, appVersion, argon2Iterations, argon2Memory (+25 more)

### Community 16 - "auto_backup_settings_dialogs.dart"
Cohesion: 0.07
Nodes (29): domain/auto_backup_watcher.dart, AddBackupProfileDialog, _AddBackupProfileDialogState, _backupMode, build, _checkBatteryOptimizations, createState, _deleteBehavior (+21 more)

### Community 17 - "settingsRepositoryProvider"
Cohesion: 0.08
Nodes (55): ConsumerState, FolderPickerDialog, infrastructureProvisioningServiceProvider, settingsRepositoryProvider, masterKeyProvider, recoveryServiceProvider, AuthScreen, _AuthScreenState (+47 more)

### Community 18 - "universal_file_viewer.dart"
Cohesion: 0.06
Nodes (33): html,
  markdown,
  pdf,
  docx,, build, _buildCodeContent, _buildHighlightedLine, createState, _data, dispose, _error (+25 more)

### Community 19 - "backup_dialogs.dart"
Cohesion: 0.07
Nodes (32): ../../domain/ai/face_recognition_service.dart, ../gallery/gallery_screen.dart, _backupData, BackupExportDialog, _BackupExportDialogState, BackupImportDialog, _BackupImportDialogState, BackupScheduleDialog (+24 more)

### Community 20 - "auth_screen.dart"
Cohesion: 0.05
Nodes (40): ../../core/widgets/aerodrive_logo.dart, _apiHashController, _apiIdController, _buildApiCredentialsEntry, _buildAuthSection, _buildCard, _buildCodeEntry, _buildCurrentView (+32 more)

### Community 21 - "faces_screen.dart"
Cohesion: 0.07
Nodes (32): ../../domain/ai/face_clustering_engine.dart, faceClustersProvider, build, _buildClusterPhotosGrid, _buildClustersList, cacheDir, clusterExistingFaces, clusters (+24 more)

### Community 22 - "package:drift/drift.dart"
Cohesion: 0.09
Nodes (24): _, @DriftDatabase, AeroDriveDatabase, package:aerodrive/core/providers/repository_providers.dart, package:aerodrive/core/utils/phone_validator.dart, package:aerodrive/data/db/database.dart, package:aerodrive/data/repositories/settings_repository.dart, package:aerodrive/domain/channel_load_balancer.dart (+16 more)

### Community 23 - "settings_screen.dart"
Cohesion: 0.06
Nodes (32): advanced_settings_dialogs.dart, appearance_settings_screen.dart, auto_backup_settings_dialogs.dart, backup_dialogs.dart, ../cleaner/cleaner_screen.dart, domain/background_service_manager.dart, ../importer/takeout_importer_dialog.dart, _buildDynamicItem (+24 more)

### Community 24 - "accounts_screen.dart"
Cohesion: 0.08
Nodes (25): ../../core/utils/phone_validator.dart, AccountsScreen, _AccountsScreenState, _buildCard, _buildCodeInput, _buildConnectedView, _buildErrorView, _buildLoadingView (+17 more)

### Community 25 - "ml_service.dart"
Cohesion: 0.07
Nodes (28): _cropFaceIsolate, cropped, CropTaskArgs, decodedImage, enhanced, h, height, imageBytes (+20 more)

### Community 26 - "ConsumerStatefulWidget"
Cohesion: 0.06
Nodes (39): ConsumerStatefulWidget, DriveScreen, MediaPlayerScreen, _GalleryItem, SmartTagsScreen, _SmartTagsScreenState, AudioPlayerScreen, DocumentScannerScreen (+31 more)

### Community 27 - "otp_input.dart"
Cohesion: 0.08
Nodes (24): FocusNode, activeColor, build, _checkCompleted, clear, controller, _controllers, createState (+16 more)

### Community 28 - "media_player_screen.dart"
Cohesion: 0.07
Nodes (27): fullscreen_video_screen.dart, _buildActionButton, controller, createState, didUpdateWidget, dispose, _duration, _error (+19 more)

### Community 29 - "drive_screen.dart"
Cohesion: 0.06
Nodes (35): domain/sync/realtime_sync_service.dart, file_picker_util.dart, _buildDropZoneOverlay, _buildLayoutSelector, _buildSortCategoryItem, _buildSortCriteriaItem, _buildSortOrderItem, _checkSecurityAndChannel (+27 more)

### Community 30 - "multi_account_screen.dart"
Cohesion: 0.08
Nodes (24): ../../core/widgets/otp_input.dart, ../../core/widgets/premium_button.dart, _buildCard, _buildCodeInput, _buildConnectedView, _buildErrorView, _buildLoadingView, _buildPhoneInput (+16 more)

### Community 31 - "my_application.cc"
Cohesion: 0.09
Nodes (22): FlPluginRegistry, FlView, GApplication, gboolean, gchar, GObject, GtkApplication, fl_register_plugins() (+14 more)

### Community 32 - "currentFolderIdProvider"
Cohesion: 0.11
Nodes (39): channelDiscoveryServiceProvider, isAppUnlockedProvider, build, _ResponsiveScaffoldState, folderScannerProvider, build, _buildPathOverview, _DriveScreenState (+31 more)

### Community 33 - "integrity_verification_service.dart"
Cohesion: 0.08
Nodes (25): Digest?, add, chunksChecked, chunksPassed, close, dekWrappingResult, details, _engine (+17 more)

### Community 34 - "search_screen.dart"
Cohesion: 0.10
Nodes (25): ../drive/widgets/file_list_item.dart, ../drive/widgets/folder_grid_item.dart, build, db, filterType, firstMatch, matchedFiles, matchedFolders (+17 more)

### Community 35 - "premium_button.dart"
Cohesion: 0.07
Nodes (27): build, _controller, createState, dispose, enabled, fullWidth, gradient, height (+19 more)

### Community 36 - "places_screen.dart"
Cohesion: 0.07
Nodes (32): build, _buildPlaceFilesGrid, _buildPlacesList, _buildPlacesMap, country, counts, createState, db (+24 more)

### Community 37 - "telegramManagerProvider"
Cohesion: 0.04
Nodes (49): FileData get, AudioLoopMode, build, _buildDesktopLayout, _buildMainControls, _buildMobileLayout, _buildProgressBar, _buildSecondaryControls (+41 more)

### Community 38 - "notification_service.dart"
Cohesion: 0.08
Nodes (24): AndroidFlutterLocalNotificationsPlugin, FlutterLocalNotificationsPlugin, actionStream, _actionStreamController, _formatBytes, getSafeNotificationId, initialize, _initialized (+16 more)

### Community 39 - "media_gallery_screen.dart"
Cohesion: 0.09
Nodes (24): decrypted_image_viewer.dart, ../drive/media_player_screen.dart, build, createState, _currentIndex, dispose, files, ImageGalleryScreen (+16 more)

### Community 40 - "fullscreen_video_screen.dart"
Cohesion: 0.08
Nodes (26): domain/streaming/streaming_server.dart, build, _changeSpeed, controller, createState, dispose, _duration, _error (+18 more)

### Community 41 - "theme_provider.dart"
Cohesion: 0.23
Nodes (12): AppError, AuthError, cause, CryptoError, FileOperationError, floodWaitSeconds, message, NetworkError (+4 more)

### Community 42 - "dart:typed_data"
Cohesion: 0.20
Nodes (9): CaptionDecryptor, CaptionSerializer, _cipher, deserialize, _encryptAndEncode, _sanitizeForJson, serializeFile, serializeFolder (+1 more)

### Community 43 - "press_and_hold_preview.dart"
Cohesion: 0.09
Nodes (22): build, child, createState, _decryptedBytes, _dismissPreview, dispose, file, _formatBytes (+14 more)

### Community 44 - "Color"
Cohesion: 0.11
Nodes (20): Color, ../features/transfers/transfers_screen.dart, HexColor, transfersStreamProvider, build, createState, _formatSize, _getTransferName (+12 more)

### Community 45 - "ConsumerState"
Cohesion: 0.15
Nodes (16): AutoRetryCountDialog, _AutoRetryCountDialogState, BandwidthLimitDialog, _BandwidthLimitDialogState, build, createState, initState, _limit (+8 more)

### Community 46 - "infrastructure_providers.dart"
Cohesion: 0.09
Nodes (23): app_colors.dart, int get, accentColorValue, AeroThemeState, copyWith, fontScale, hashCode, highContrast (+15 more)

### Community 47 - "smart_analyzer.dart"
Cohesion: 0.08
Nodes (25): ai/face_clustering_engine.dart, double?, AnalysisResult, analyzeAndStore, analyzeImageForUpload, _convertExifGps, country, _db (+17 more)

### Community 48 - "auto_backup_watcher.dart"
Cohesion: 0.10
Nodes (20): AutoBackupWatcherService, dispose, _handleLocalDelete, _isRunning, _isWifiOrWifiNotRequired, _matchesFilter, _pollTimer, _queueFile (+12 more)

### Community 49 - "integration_settings_dialogs.dart"
Cohesion: 0.11
Nodes (21): ApiKeyManagementDialog, _ApiKeyManagementDialogState, build, createState, _currentKey, _generateKey, initState, InlineBotSetupDialog (+13 more)

### Community 50 - "marquee_text.dart"
Cohesion: 0.11
Nodes (17): AlignmentGeometry, alignment, build, _checkScroll, createState, didUpdateWidget, dispose, initState (+9 more)

### Community 51 - "responsive_scaffold.dart"
Cohesion: 0.10
Nodes (20): app_router.dart, ../constants.dart, features/drive/providers/drive_providers.dart, ../../features/sharing/import_link_dialog.dart, ../../features/transfers/widgets/global_progress_bar.dart, _buildStorageCard, child, createState (+12 more)

### Community 52 - "ConsumerWidget"
Cohesion: 0.11
Nodes (24): ConsumerWidget, _GalleryItem, _CleanerThumbnail, _loadPreview, _FaceGridItem, _GalleryItemState, _loadThumbnail, thumbnailServiceProvider (+16 more)

### Community 53 - "testing_ended_screen.dart"
Cohesion: 0.10
Nodes (20): CustomPainter, DogEarFilePainter, StarfieldPainter, build, createState, dispose, _exitApp, _GridPainter (+12 more)

### Community 54 - "infrastructure_provisioning_service.dart"
Cohesion: 0.07
Nodes (26): core/logger.dart, data/repositories/settings_repository.dart, ChannelLoadBalancer, getStorageChannels, selectFileBaseIndex, selectStorageChannel, _archiveAndMuteChannel, configChannelId (+18 more)

### Community 55 - "webdav_settings_dialog.dart"
Cohesion: 0.11
Nodes (19): ../../domain/webdav/webdav_config.dart, ../../domain/webdav/webdav_server.dart, build, _buildCopyRow, _configService, createState, _creds, dispose (+11 more)

### Community 56 - "health_check_screen.dart"
Cohesion: 0.11
Nodes (21): activeChannelIdProvider, activeChannelNameProvider, activeChannelStr, build, channel, channelId, _compromisedFiles, createState (+13 more)

### Community 57 - "../data/db/database.dart"
Cohesion: 0.10
Nodes (19): ../../domain/infrastructure/channel_discovery_service.dart, ../../../domain/infrastructure/infrastructure_provisioning_service.dart, allAccounts, configChannelId, discoveryResult, discoveryService, ensureInfrastructureProvider, InfrastructureStatus (+11 more)

### Community 58 - "api_service.dart"
Cohesion: 0.09
Nodes (21): domain/folder_scanner.dart, HttpServer?, _authMiddleware, container, _corsMiddleware, _fileToJson, _folderToJson, _handleCreateFolder (+13 more)

### Community 59 - "streaming_server.dart"
Cohesion: 0.08
Nodes (25): @visibleForTesting, ChunkData, _buildChunkInfos, buildChunkInfosForTesting, _cacheLocalFilePath, _cacheRemoteFileId, chunk, _createDecryptionStream (+17 more)

### Community 60 - "package:flutter_riverpod/flutter_riverpod.dart"
Cohesion: 0.09
Nodes (22): ../../domain/scanner/document_scanner_service.dart, compileImagesToPdf, DocumentColorFilter, DocumentScannerService, processImagePage, _uuid, _activePageIndex, _applyFilter (+14 more)

### Community 61 - "decrypted_text_viewer.dart"
Cohesion: 0.11
Nodes (19): build, _buildContent, _codePattern, _codeSpan, _contentWidth, createState, _data, DecryptedTextViewer (+11 more)

### Community 62 - "List"
Cohesion: 0.11
Nodes (18): _showLinkExistingChannelDialog, accounts, addClient, adminChannelsProvider, allAdminChannels, allEvents, allSessions, _eventController (+10 more)

### Community 63 - "Table"
Cohesion: 0.13
Nodes (19): @DataClassName, Accounts, BackupHistory, Channels, Chunks, FaceClusters, FilePlaces, Files (+11 more)

### Community 64 - "core/providers/repository_providers.dart"
Cohesion: 0.09
Nodes (21): Map, package:aerodrive/core/providers.dart, package:aerodrive/core/routing/app_router.dart, package:aerodrive/features/auth/auth_provider.dart, package:aerodrive/features/telegram/telegram_service.dart, main, noSuchMethod, clearAllSettings (+13 more)

### Community 65 - "shared_links_screen.dart"
Cohesion: 0.12
Nodes (18): dart:ui, _checkForInterruptedImports, _resumeImport, build, createState, _error, initState, _isLoading (+10 more)

### Community 66 - "repository_providers.dart"
Cohesion: 0.11
Nodes (18): ../../data/repositories/chunk_repository.dart, ../../data/repositories/file_repository.dart, ../../data/repositories/folder_repository.dart, ../../domain/download_orchestrator.dart, domain/download_queue_service.dart, ../../domain/upload_orchestrator.dart, domain/upload_queue_service.dart, ../../features/api/api_service.dart (+10 more)

### Community 67 - "dropbox_backup_screen.dart"
Cohesion: 0.10
Nodes (21): domain/backup_service.dart, dropbox_service.dart, backupServiceProvider, build, createState, DropboxBackupScreen, _DropboxBackupScreenState, _frequency (+13 more)

### Community 68 - "file_list_item.dart"
Cohesion: 0.12
Nodes (15): archive_viewer.dart, audio_player_screen.dart, file_decryption_util.dart, image_gallery_screen.dart, build, _downloadAndOpen, file, fileId (+7 more)

### Community 69 - "advanced_settings_dialogs.dart"
Cohesion: 0.10
Nodes (20): ../../domain/recovery/recovery_scanner.dart, build, _clearCache, ClearCacheDialog, _ClearCacheDialogState, createState, DatabaseStatsDialog, _DatabaseStatsDialogState (+12 more)

### Community 70 - "transfers_screen.dart"
Cohesion: 0.11
Nodes (18): _buildEmptyState, _buildFilterChip, _buildStatusBadge, _cancelTransfer, _clearHistory, createState, _currentFilter, db (+10 more)

### Community 71 - "State"
Cohesion: 0.15
Nodes (12): ../core/theme/app_colors.dart, ../core/utils/reset_helper.dart, build, build, StorageWidget, build, PreviewScreen, build (+4 more)

### Community 72 - "archive_viewer.dart"
Cohesion: 0.12
Nodes (16): Archive?, _archive, ArchiveViewer, _ArchiveViewerState, build, createState, _entries, _error (+8 more)

### Community 73 - "encryption_engine.dart"
Cohesion: 0.11
Nodes (17): Cipher, _argon2, _argon2LowEnd, _cipher, decryptBytes, decryptDiskToStream, deriveMasterKey, deriveMasterKeyFromPhrase (+9 more)

### Community 74 - "package:flutter/material.dart"
Cohesion: 0.13
Nodes (20): ../../domain/cleaner/duplicate_cleaner_service.dart, duplicateCleanerServiceProvider, build, _buildEmptyTab, cleanerDuplicatesProvider, cleanerLargeFilesProvider, CleanerScreen, cleanerScreenshotsProvider (+12 more)

### Community 75 - "StatelessWidget"
Cohesion: 0.10
Nodes (20): build, _cachedThumbs, createState, _currentIndex, dispose, files, initialIndex, initState (+12 more)

### Community 76 - "aerodrive_theme.dart"
Cohesion: 0.05
Nodes (42): AeroDriveTheme, AeroThemePreset, _buildTextTheme, _defaultAccent, _defaultSecondary, getDark, getLight, gradient (+34 more)

### Community 77 - "package:path_provider/path_provider.dart"
Cohesion: 0.20
Nodes (9): createFileEntry, _db, FileRepository, getFileByHash, getFilesInFolder, restoreFile, softDelete, trashFile (+1 more)

### Community 78 - "decrypted_image_viewer.dart"
Cohesion: 0.23
Nodes (12): allMediaFilesProvider, allMediaFoldersProvider, _buildAlbumsTab, _buildOptionsMenu, _buildPhotosTab, _buildTimelineContent, mediaColumnCountProvider, MediaScreen (+4 more)

### Community 79 - "tag_dialog.dart"
Cohesion: 0.10
Nodes (19): chunkLength, chunkLimit, computeFileHash, ctrIv, dekBytes, EncryptJobPayload, getOptimalChunkSize, handoffToTelegram (+11 more)

### Community 80 - "win32_window.cpp"
Cohesion: 0.18
Nodes (14): Point, Size, wchar_t, Scale(), Create, Destroy, UpdateTheme, Win32Window::Win32Window() (+6 more)

### Community 81 - "AeroDriveBackupService"
Cohesion: 0.17
Nodes (9): AeroDriveBackupService, Context, Int, Intent, start(), stop(), IBinder, Notification (+1 more)

### Community 82 - "realtime_sync_service.dart"
Cohesion: 0.09
Nodes (22): config_sync_service.dart, _allEventsSub, catchUp, _configChatId, dispose, _getConfigChatId, _getStorageChannelIds, _handleDeleteMessages (+14 more)

### Community 83 - "thumbnail_service.dart"
Cohesion: 0.29
Nodes (6): key, null, telegramService, userId, package:crypto/crypto.dart, ../security/master_key_provider.dart

### Community 84 - "dart:io"
Cohesion: 0.14
Nodes (15): dart:io, BackgroundServiceManager, _channel, startService, stopService, BootService, _channel, isBootCompleted (+7 more)

### Community 85 - "channels_screen.dart"
Cohesion: 0.11
Nodes (17): ../drive/widgets/channel_setup_wizard_dialog.dart, _activeChannelId, build, ChannelsScreen, _confirmAndAddChannel, createState, _currentStrategy, _formatStrategy (+9 more)

### Community 86 - "upload_orchestrator.dart"
Cohesion: 0.08
Nodes (25): ../../core/security/master_key_provider.dart, ../../data/crypto/encryption_engine.dart, ../../domain/offline/offline_pin_service.dart, build, createState, _decryptedFile, dispose, _downloadFullChunk (+17 more)

### Community 87 - "debug_error_screen.dart"
Cohesion: 0.11
Nodes (19): build, _commentController, _copyToClipboard, createState, DebugErrorScreen, _DebugErrorScreenState, dispose, error (+11 more)

### Community 88 - "appearance_settings_screen.dart"
Cohesion: 0.13
Nodes (14): core/theme/aerodrive_theme.dart, core/theme/theme_provider.dart, defaultVal, icon, isSelected, label, _ModeCard, onTap (+6 more)

### Community 89 - "folder_repository.dart"
Cohesion: 0.08
Nodes (24): Exception, createFolder, _db, FolderNameTooLongException, FolderPathTooLongException, FolderRepository, getFolderContents, getFolderPath (+16 more)

### Community 90 - "config_sync_service.dart"
Cohesion: 0.11
Nodes (18): ../../features/trash/trash_screen.dart, applyRemoteDriveState, _archiveAndMute, checkConfigStatus, _configChannelName, ConfigStatus, ConfigSyncService, _configWarningText (+10 more)

### Community 91 - "file_type_icon.dart"
Cohesion: 0.06
Nodes (31): IconData, _buildInfoRow, _buildOptionsMenu, _copyFolderRecursive, createState, folder, FolderGridItem, _formatFolderBadgeSize (+23 more)

### Community 92 - "file_grid_item.dart"
Cohesion: 0.07
Nodes (45): file_type_icon.dart, folder_picker_dialog.dart, offlinePinnedIdsProvider, offlinePinServiceProvider, _buildAppBar, _handleCopySelected, _handleDownloadSelected, _handleMoveSelected (+37 more)

### Community 93 - "memories_screen.dart"
Cohesion: 0.06
Nodes (31): IOSink?, _autoFlushTimer, _closeSink, _currentFileName, detectCrashedUpload, dispose, _ensureDir, _fileIoFailed (+23 more)

### Community 94 - "places_service.dart"
Cohesion: 0.09
Nodes (21): DateTime, FileSizeExtension, RelativeTimeExtension, truncate, TruncateExtension, admin, backfillPlaces, _cities (+13 more)

### Community 95 - "dropbox_service.dart"
Cohesion: 0.13
Nodes (14): _checkStatus, _clientId, _clientSecret, connected, connectWithCode, disconnect, _email, getAccessToken (+6 more)

### Community 96 - "FlutterWindow"
Cohesion: 0.13
Nodes (13): unique_ptr, DartProject, HWND, LPARAM, LRESULT, UINT, WPARAM, FlutterWindow (+5 more)

### Community 97 - "auth_provider.dart"
Cohesion: 0.08
Nodes (27): Battery, ../../core/providers/infrastructure_providers.dart, OfflinePinnedIdsNotifier, AuthNotifier, AuthState, _ensureInfrastructure, forceUnauthenticated, _hasBeenAuthenticated (+19 more)

### Community 98 - "gallery_screen.dart"
Cohesion: 0.22
Nodes (9): build, Route /diagnostics, Route /settings/about, Route /settings/accounts, Route /settings/backup/dropbox, Route /settings/channels/health, Route /settings/profile, Route /settings/session (+1 more)

### Community 99 - "logger.dart"
Cohesion: 0.12
Nodes (15): _addLog, AppLogger, clearSavedCrashLog, error, getSavedCrashLog, hasSavedCrashLog, info, init (+7 more)

### Community 100 - "face_recognition_service.dart"
Cohesion: 0.14
Nodes (14): avatarFileId, DbFaceService, FaceCluster, faceClustersProvider, FaceRecognitionService, faceRecognitionServiceProvider, faceService, getClusters (+6 more)

### Community 101 - "folder_picker_dialog.dart"
Cohesion: 0.13
Nodes (14): _breadcrumbs, build, _buildBreadcrumbs, createState, _currentFolderId, excludeFolderId, _findNestedFolderIds, FolderPickerDialog (+6 more)

### Community 102 - "proxy_settings_screen.dart"
Cohesion: 0.14
Nodes (13): build, createState, initState, _isEnabled, _isLoading, _loadSettings, _passCtrl, _portCtrl (+5 more)

### Community 103 - "preview_router.dart"
Cohesion: 0.13
Nodes (15): fileIconStyleProvider, build, _buildColored, _buildFilled, _buildMinimal, _buildOutlined, color, fileName (+7 more)

### Community 104 - "manifest_encoder.dart"
Cohesion: 0.15
Nodes (12): caption_codec.dart, _buildMap, _captionSafetyLimit, decodeManifest, encodeFileManifest, encodeFolderManifest, encodeThumbnailManifest, _estimatedEncryptedSize (+4 more)

### Community 105 - "channel_discovery_service.dart"
Cohesion: 0.07
Nodes (28): channel_description_codec.dart, ../../../core/constants.dart, dart:convert, ../features/telegram/telegram_service.dart, AppResetHelper, showResetConfirmation, ChannelDescriptionCodec, _cipher (+20 more)

### Community 106 - "purge_job.dart"
Cohesion: 0.17
Nodes (12): build, _buildExploreTab, exploreDataProvider, build, build, _openGeneric, _openUniversalViewer, MaterialPageRoute (+4 more)

### Community 107 - "backup_service.dart"
Cohesion: 0.14
Nodes (13): ../features/settings/dropbox_service.dart, BackupService, _collectBackupData, dropboxBackup, ensurePublicFolders, exportBackup, _getDropboxToken, getOrCreateBackupDir (+5 more)

### Community 108 - "webdav_config.dart"
Cohesion: 0.14
Nodes (13): FlutterSecureStorage, getCredentials, _keyPassword, _keyPort, _keyUsername, password, port, regenerateCredentials (+5 more)

### Community 109 - "folder_scanner.dart"
Cohesion: 0.12
Nodes (15): channel_load_balancer.dart, features/telegram/telegram_manager.dart, _createZipArchive, _db, FolderScanner, _queueSingleFile, _ref, scanAndQueueDirectory (+7 more)

### Community 110 - "Win32Window"
Cohesion: 0.20
Nodes (14): RECT, OnCreate, OnDestroy, HWND, Win32Window, child_content_, GetClientArea, OnCreate (+6 more)

### Community 111 - "aerodrive_logo.dart"
Cohesion: 0.13
Nodes (14): AeroDriveLogo, Animation, AnimationController, AeroDriveLogoSize, _AeroDriveLogoState, build, _controller, createState (+6 more)

### Community 112 - "video_gallery_screen.dart"
Cohesion: 0.18
Nodes (11): build, createState, _currentIndex, dispose, files, initialIndex, initState, _pageController (+3 more)

### Community 113 - "import_link_dialog.dart"
Cohesion: 0.07
Nodes (27): Completer, ../drive/widgets/folder_picker_dialog.dart, build, _buildActions, _buildContent, _buildDetailRow, _buildTitle, _confirmCompleter (+19 more)

### Community 114 - "app_error.dart"
Cohesion: 0.40
Nodes (4): AeroDriveLogo, build, size, ../theme/app_colors.dart

### Community 115 - "_AeroDriveAppState"
Cohesion: 0.25
Nodes (11): downloadQueueServiceProvider, uploadQueueServiceProvider, routerProvider, themeProvider, realtimeSyncServiceProvider, didChangeAppLifecycleState, AppearanceSettingsScreen, build (+3 more)

### Community 116 - "smart_tags_screen.dart"
Cohesion: 0.12
Nodes (16): FileData?, ../gallery/thumbnail_service.dart, file, _buildFallbackGradient, _buildTagFilesView, _buildTagsGridView, createState, file (+8 more)

### Community 117 - "about_screen.dart"
Cohesion: 0.15
Nodes (12): AboutScreen, build, _buildAppHero, _buildCard, _buildDeveloperCard, _buildDivider, _buildLinkTile, _buildSignatureCredit (+4 more)

### Community 118 - "companion_server_dialogs.dart"
Cohesion: 0.17
Nodes (12): build, CompanionServerDialog, _CompanionServerDialogState, createState, initState, _isLoading, _keyController, _load (+4 more)

### Community 119 - "core/logger.dart"
Cohesion: 0.40
Nodes (5): autoBackupWatcherProvider, ManageBackupFoldersScreen, _ManageBackupFoldersScreenState, _saveProfiles, initState

### Community 120 - "dart:async"
Cohesion: 0.14
Nodes (17): auth_provider.dart, dart:async, authProvider, build, build, createState, dispose, InfrastructureSetupScreen (+9 more)

### Community 121 - "video_thumbnail_service.dart"
Cohesion: 0.20
Nodes (9): Duration, duration, generateSmartThumbnail, _getDurationOnly, path, VideoThumbnailResult, VideoThumbnailService, videoThumbnailServiceProvider (+1 more)

### Community 122 - "wWinMain"
Cohesion: 0.24
Nodes (9): _In_, _In_opt_, vector, wWinMain(), string, wchar_t, CreateAndAttachConsole(), GetCommandLineArguments() (+1 more)

### Community 123 - "repository_test.dart"
Cohesion: 0.12
Nodes (18): ../../domain/importer/takeout_importer_service.dart, takeoutImporterServiceProvider, TakeoutImportSummary, build, _buildStatRow, createState, _formatBytes, _importProgress (+10 more)

### Community 124 - "network_settings_dialogs.dart"
Cohesion: 0.16
Nodes (13): settingsUpdateProvider, ResetSettingsDialog, _DropdownTile, _executeImport, build, ConnectionTimeoutDialog, _ConnectionTimeoutDialogState, createState (+5 more)

### Community 125 - "isSelectionModeProvider"
Cohesion: 0.12
Nodes (16): _apiHashController, _apiIdController, build, _buildStep, createState, dispose, _error, initState (+8 more)

### Community 126 - "media_settings_dialogs.dart"
Cohesion: 0.12
Nodes (15): ../../features/preview/file_decryption_util.dart, getOfflineDirectory, getOfflineFile, getTotalOfflineBytes, initialize, isPinned, _kOfflinePinnedSettingKey, _loadRegistry (+7 more)

### Community 127 - "splash_screen.dart"
Cohesion: 0.15
Nodes (14): hasNavigatedPastSplashProvider, build, createState, initState, paint, _progress, random, _runSync (+6 more)

### Community 128 - "purge_job.dart"
Cohesion: 0.14
Nodes (13): dart:isolate, chunksToDelete, completeHardDelete, deleteTelegramMessages, ExpiredMessagesPayload, fileIdsToPurge, findExpiredItems, folderIdsToPurge (+5 more)

### Community 129 - "settings_repository.dart"
Cohesion: 0.12
Nodes (15): clearAllSettings, clearSetting, _db, getBoolSetting, getInt, getIntSetting, getSetting, getString (+7 more)

### Community 130 - "build"
Cohesion: 0.06
Nodes (30): Digest? get, add, _BatchEncryptionEngine, BatchEncryptor, _BatchPayload, BatchResult, batchSize, _bufferSize (+22 more)

### Community 131 - "backup_folder_mapper.dart"
Cohesion: 0.10
Nodes (19): core/providers/repository_providers.dart, build, createState, initState, _isLoading, LoadBalancingScreen, _LoadBalancingScreenState, _loadSettings (+11 more)

### Community 132 - "manifest.json"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 133 - "master_key_provider.dart"
Cohesion: 0.25
Nodes (8): build, _confirmTerminateAllOtherSessions, _confirmTerminateSession, _formatLastActive, _getDeviceIcon, SessionScreen, activeSessionsProvider, package:intl/intl.dart

### Community 134 - "MessageHandler"
Cohesion: 0.36
Nodes (10): HWND, LPARAM, LRESULT, UINT, WPARAM, EnableFullDpiSupportIfAvailable(), GetHandle, GetThisFromHandle (+2 more)

### Community 135 - "file_decryption_util.dart"
Cohesion: 0.12
Nodes (15): blobToEmbedding, clusterExistingFaces, cosineSimilarity, embeddingDimension, embeddingToBlob, extractFaceEmbedding, FaceClusteringEngine, findOrCreateCluster (+7 more)

### Community 136 - "dart:convert"
Cohesion: 0.20
Nodes (9): bool get, clearKey, _instance, isUnlocked, _key, MasterKeyProvider, setKey, static final MasterKeyProvider (+1 more)

### Community 137 - "recovery_scanner.dart"
Cohesion: 0.17
Nodes (12): _db, RecoveryScanner, _ref, runDisasterRecovery, telegram, _telegramService, ZeroDBRecoveryService, manifest_encoder.dart (+4 more)

### Community 138 - "package:cryptography/cryptography.dart"
Cohesion: 0.14
Nodes (13): ../../../domain/channel_load_balancer.dart, ../../domain/recovery/manifest_encoder.dart, build, CreateFolderDialog, createState, dispose, _nameController, _selectedColorHex (+5 more)

### Community 139 - "thumbnail_cache_service.dart"
Cohesion: 0.22
Nodes (8): _db, _enforceLruCacheLimit, _getCacheDirectory, getThumbnail, maxCacheSizeBytes, saveThumbnail, ThumbnailCacheService, static const int

### Community 140 - "phone_validator.dart"
Cohesion: 0.29
Nodes (6): errorMessage, formattedNumber, isValid, PhoneValidationResult, PhoneValidator, validate

### Community 141 - "_buildExploreTab"
Cohesion: 0.08
Nodes (23): _adminChannels, build, _buildChannelDropdown, _buildChannelItem, _buildExistingSelectionView, _buildOverviewView, _buildProgressView, _buildRuleItem (+15 more)

### Community 142 - "BootReceiver"
Cohesion: 0.33
Nodes (4): BootReceiver, Context, Intent, BroadcastReceiver

### Community 143 - "DateTime"
Cohesion: 0.14
Nodes (12): dart:typed_data, decryptStreamRange, _incrementIv, StreamingEncryptionEngine, _cipher, clearCache, _getCacheThumbsDirectory, readThumbnail (+4 more)

### Community 144 - "propfind_handler.dart"
Cohesion: 0.33
Nodes (5): handle, PropfindHandler, package:shelf/shelf.dart, package:xml/xml.dart, XmlElement

### Community 145 - "file_tags_row.dart"
Cohesion: 0.12
Nodes (15): ../data/db/database.dart, db, build, fileId, FileTagsRow, db, fileTagsProvider, fileTagsStreamProvider (+7 more)

### Community 146 - "MainActivity"
Cohesion: 0.29
Nodes (4): MainActivity, Bundle, FlutterEngine, FlutterFragmentActivity

### Community 147 - "thumbnail_service.dart"
Cohesion: 0.20
Nodes (9): ../../core/providers/security_providers.dart, ../../domain/thumbnail_cache_manager.dart, _downloadFile, _fetchThumbnailFromTelegram, _generateAndCacheThumbnail, getThumbnail, _ref, ThumbnailService (+1 more)

### Community 149 - "MaterialPageRoute"
Cohesion: 0.14
Nodes (14): FolderData, build, createState, dispose, _error, file, folder, _hasPassword (+6 more)

### Community 151 - "gallery_screen.dart"
Cohesion: 0.16
Nodes (13): File?, build, createState, db, file, _GalleryItem, GalleryScreenContent, initState (+5 more)

### Community 159 - "takeout_importer_service.dart"
Cohesion: 0.14
Nodes (13): ../folder_scanner.dart, analyzeDirectory, _ensureFolderHierarchy, foldersCreated, importTakeoutDirectory, _mediaExtensions, _ref, sidecarsMatched (+5 more)

### Community 160 - "StatelessWidget"
Cohesion: 0.14
Nodes (14): _DesktopLayout, _MobileLayout, _TabletLayout, PremiumSwitch, PremiumTextField, StorageBanner, _PlaceMarkerBadge, _DocxViewer (+6 more)

### Community 161 - "State"
Cohesion: 0.19
Nodes (14): OtpInput, _OtpInputState, PremiumButton, _PremiumButtonState, MarqueeText, _MarqueeTextState, _CodeTextViewer, _CodeTextViewerState (+6 more)

### Community 162 - "queue_repository.dart"
Cohesion: 0.12
Nodes (15): ../db/database.dart, ChunkRepository, _db, getChunksForFile, insertChunk, updateChunkMessageId, _uuid, _db (+7 more)

### Community 163 - "download_orchestrator.dart"
Cohesion: 0.15
Nodes (12): ctrIv, DecryptJobPayload, dedupFilePath, dekBytes, DownloadOrchestrator, ensureDownloadDirectory, _notifyMediaScanner, outputFilePath (+4 more)

### Community 164 - "app_lock_screen.dart"
Cohesion: 0.18
Nodes (11): biometric_auth_service.dart, AppLockScreen, _AppLockScreenState, build, createState, _errorMessage, initState, _isAuthenticating (+3 more)

### Community 165 - "biometric_auth_service.dart"
Cohesion: 0.17
Nodes (11): appLockEnabledProvider, authenticate, BiometricAuthService, isAppLockEnabled, isBiometricsSupported, isVaultUnlockedProvider, _localAuth, ref (+3 more)

### Community 166 - "duplicate_cleaner_service.dart"
Cohesion: 0.18
Nodes (10): db, DuplicateCleanerService, DuplicateGroup, files, getDuplicateGroups, getLargeFiles, getScreenshots, hashOrKey (+2 more)

### Community 167 - "../core/providers.dart"
Cohesion: 0.24
Nodes (9): ../core/providers.dart, _TransferBadge, _showBackgroundTasksBottomSheet, aggregateTransferProgressProvider, build, db, GlobalProgressBar, select (+1 more)

### Community 168 - "encryption_engine_test.dart"
Cohesion: 0.25
Nodes (7): Directory, EncryptionEngine, package:aerodrive/data/crypto/encryption_engine.dart, package:path/path.dart, engine, main, tempDir

### Community 169 - "package:path_provider/path_provider.dart"
Cohesion: 0.29
Nodes (6): migration, _openConnection, schemaVersion, MigrationStrategy get, package:path_provider/path_provider.dart, tables.dart

### Community 170 - "return"
Cohesion: 0.29
Nodes (6): channel, paths, pickFilesForUpload, result, package:file_picker/file_picker.dart, return

### Community 171 - "dart:math"
Cohesion: 0.50
Nodes (3): dart:math, package:aerodrive/domain/upload_orchestrator.dart, main

### Community 172 - "people_screen.dart"
Cohesion: 0.50
Nodes (3): ../faces/faces_screen.dart, build, PeopleScreenContent

### Community 173 - "streamingServerProvider"
Cohesion: 0.50
Nodes (4): streamingServerProvider, _initStream, _initStream, _initStreamForCurrent

### Community 174 - "_DigestSink"
Cohesion: 0.67
Nodes (3): _DigestSink, _DigestSink, Sink

## Knowledge Gaps
- **2334 isolated node(s):** `message`, `cause`, `floodWaitSeconds`, `toString`, `AppConstants` (+2329 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AeroDriveDatabase` connect `package:drift/drift.dart` to `settings_repository.dart`, `queue_repository.dart`, `upload_queue_service.dart`, `duplicate_cleaner_service.dart`, `package:path_provider/path_provider.dart`, `recovery_scanner.dart`, `thumbnail_cache_service.dart`, `package:path_provider/path_provider.dart`, `download_queue_service.dart`, `folder_scanner.dart`, `smart_analyzer.dart`, `file_tags_row.dart`, `folder_repository.dart`?**
  _High betweenness centrality (0.011) - this node is a cross-community bridge._
- **Why does `settingsRepositoryProvider` connect `settingsRepositoryProvider` to `currentFolderIdProvider`, `repository_providers.dart`, `dropbox_backup_screen.dart`, `backup_folder_mapper.dart`, `proxy_settings_screen.dart`, `purge_job.dart`, `ConsumerState`, `network_settings_dialogs.dart`, `auto_backup_settings_dialogs.dart`, `_AeroDriveAppState`, `backup_dialogs.dart`, `channels_screen.dart`, `core/logger.dart`, `ConsumerStatefulWidget`, `media_player_screen.dart`, `isSelectionModeProvider`, `List`?**
  _High betweenness centrality (0.006) - this node is a cross-community bridge._
- **Why does `_DriveScreenState` connect `currentFolderIdProvider` to `shared_links_screen.dart`, `../core/providers.dart`, `databaseProvider`, `Color`, `settingsRepositoryProvider`, `_AeroDriveAppState`, `ConsumerStatefulWidget`, `file_grid_item.dart`, `drive_screen.dart`?**
  _High betweenness centrality (0.004) - this node is a cross-community bridge._
- **What connects `message`, `cause`, `floodWaitSeconds` to the rest of the system?**
  _2334 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `tables.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.021052631578947368 - nodes in this community are weakly interconnected._
- **Should `telegram_service.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.022727272727272728 - nodes in this community are weakly interconnected._
- **Should `media_screen.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.030303030303030304 - nodes in this community are weakly interconnected._