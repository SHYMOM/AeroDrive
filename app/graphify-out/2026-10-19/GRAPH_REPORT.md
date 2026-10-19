# Graph Report - app  (2026-10-19)

## Corpus Check
- 195 files · ~158,392 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3383 nodes · 5602 edges · 163 communities (156 shown, 7 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS · INFERRED: 18 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `4c58032d`
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
- recovery_scanner.dart
- isSelectionModeProvider
- media_settings_dialogs.dart
- splash_screen.dart
- Ref
- settings_repository.dart
- build
- backup_folder_mapper.dart
- manifest.json
- master_key_provider.dart
- MessageHandler
- file_decryption_util.dart
- dart:convert
- database.dart
- package:cryptography/cryptography.dart
- thumbnail_cache_service.dart
- phone_validator.dart
- _buildExploreTab
- BootReceiver
- DateTime
- propfind_handler.dart
- file_tags_row.dart
- MainActivity
- aerodrive_logo.dart
- MaterialPageRoute
- RegisterPlugins
- _DigestSink
- aerodrive
- @your_bot_name
- int?
- String?
- queue_repository.dart
- build
- _HealthCheckScreenState
- aerodrive_logo.dart
- MaterialPageRoute

## God Nodes (most connected - your core abstractions)
1. `databaseProvider` - 75 edges
2. `settingsRepositoryProvider` - 71 edges
3. `telegramManagerProvider` - 37 edges
4. `dbRebuildVersionProvider` - 33 edges
5. `_DriveScreenState` - 28 edges
6. `masterKeyProvider` - 23 edges
7. `currentFolderIdProvider` - 23 edges
8. `telegramServiceProvider` - 22 edges
9. `Win32Window` - 22 edges
10. `selectedItemsProvider` - 21 edges

## Surprising Connections (you probably didn't know these)
- `_handleStream` --references--> `databaseProvider`  [EXTRACTED]
  lib/domain/streaming/streaming_server.dart → lib/core/providers.dart
- `_loadFolderInfo` --references--> `databaseProvider`  [EXTRACTED]
  lib/features/drive/media_player_screen.dart → lib/core/providers.dart
- `_toggleFavorite` --references--> `databaseProvider`  [EXTRACTED]
  lib/features/drive/media_player_screen.dart → lib/core/providers.dart
- `_loadCurrentFolderContents` --references--> `databaseProvider`  [EXTRACTED]
  lib/features/drive/widgets/folder_picker_dialog.dart → lib/core/providers.dart
- `_renameCluster` --references--> `databaseProvider`  [EXTRACTED]
  lib/features/faces/faces_screen.dart → lib/core/providers.dart

## Import Cycles
- None detected.

## Communities (163 total, 7 thin omitted)

### Community 0 - "tables.dart"
Cohesion: 0.02
Nodes (94): BlobColumn get, BoolColumn get, DateTimeColumn get, IntColumn get, accountId, adminArea, boxHeight, boxLeft (+86 more)

### Community 1 - "telegram_service.dart"
Cohesion: 0.03
Nodes (78): accountId, addAdminToChat, addProxy, _apiHash, _apiId, authState, chats, checkAdminStatus (+70 more)

### Community 2 - "media_screen.dart"
Cohesion: 0.04
Nodes (46): _AlbumItemData, allFiles, allTags, build, _buildActiveFiltersHeader, _buildAlbumCard, _buildBody, _buildBottomSubNavBar (+38 more)

### Community 3 - "share_service.dart"
Cohesion: 0.04
Nodes (47): _addTempJoinedChannel, _archiveAndMute, _buildFlatImportList, channelId, cleanupInterruptedTempChannels, _copyAndReEncryptFile, _copyAndReEncryptFileResumable, createdAt (+39 more)

### Community 4 - "upload_queue_service.dart"
Cohesion: 0.04
Nodes (53): ../features/ml/ml_service.dart, ../features/places/places_service.dart, _abortedFileIds, _activeUploadDirs, ActiveUploadInfo, _allChunksSentAt, _calculateFileHash, chatId (+45 more)

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
Cohesion: 0.07
Nodes (42): folder_picker_dialog.dart, databaseProvider, dbRebuildVersionProvider, _showCopyDialog, _showMoveDialog, _toggleFavorite, _showCopyDialog, _showMoveDialog (+34 more)

### Community 9 - "app_router.dart"
Cohesion: 0.05
Nodes (39): ../../features/auth/auth_provider.dart, ../../features/auth/auth_screen.dart, ../../features/auth/infrastructure_setup_screen.dart, features/debug/debug_error_screen.dart, ../../features/drive/drive_screen.dart, ../../features/drive/quick_access_tools_screen.dart, ../../features/faces/faces_screen.dart, ../../features/media/audio_screen.dart (+31 more)

### Community 10 - "drive_providers.dart"
Cohesion: 0.05
Nodes (38): anyFile, audioCount, breadcrumbs, calculateFolderSize, categoryPriority, contents, copyWith, criteria (+30 more)

### Community 11 - "folder_picker_dialog.dart"
Cohesion: 0.08
Nodes (24): _allFolders, build, _buildFolderTile, _buildRootTile, _buildTree, _collectDescendantIds, createState, currentFolderId (+16 more)

### Community 12 - "FileData?"
Cohesion: 0.06
Nodes (44): ../drive/providers/drive_providers.dart, ../drive/widgets/press_and_hold_preview.dart, FileData?, clearKey, _instance, isUnlocked, _key, MasterKeyProvider (+36 more)

### Community 13 - "main.dart"
Cohesion: 0.05
Nodes (39): @pragma, AppLinks, core/routing/app_router.dart, domain/boot_service.dart, domain/notification_service.dart, domain/sync/realtime_sync_service.dart, domain/upload_crash_debugger.dart, features/sharing/share_service.dart (+31 more)

### Community 14 - "download_queue_service.dart"
Cohesion: 0.05
Nodes (39): ../download_orchestrator.dart, ActiveDownloadInfo, _activeDownloads, chunkIndex, _chunkTimeout, _completionController, _db, dispose (+31 more)

### Community 15 - "constants.dart"
Cohesion: 0.06
Nodes (35): animFast, animNormal, animSlow, AppConstants, appName, appVersion, argon2Iterations, argon2Memory (+27 more)

### Community 16 - "auto_backup_settings_dialogs.dart"
Cohesion: 0.06
Nodes (34): domain/auto_backup_watcher.dart, autoBackupWatcherProvider, AddBackupProfileDialog, _AddBackupProfileDialogState, _backupMode, build, _checkBatteryOptimizations, createState (+26 more)

### Community 17 - "settingsRepositoryProvider"
Cohesion: 0.13
Nodes (37): channelDiscoveryServiceProvider, infrastructureProvisioningServiceProvider, folderRepositoryProvider, settingsRepositoryProvider, isAppUnlockedProvider, masterKeyProvider, folderScannerProvider, recoveryServiceProvider (+29 more)

### Community 18 - "universal_file_viewer.dart"
Cohesion: 0.06
Nodes (33): html,
  markdown,
  pdf,
  docx,, build, _buildCodeContent, _buildHighlightedLine, createState, _data, dispose, _error (+25 more)

### Community 19 - "backup_dialogs.dart"
Cohesion: 0.07
Nodes (31): ../../domain/ai/face_recognition_service.dart, ../gallery/gallery_screen.dart, _backupData, BackupExportDialog, _BackupExportDialogState, BackupImportDialog, _BackupImportDialogState, BackupScheduleDialog (+23 more)

### Community 20 - "auth_screen.dart"
Cohesion: 0.06
Nodes (32): ../../core/widgets/aerodrive_logo.dart, AuthScreen, _buildAuthSection, _buildCard, _buildCodeEntry, _buildCurrentView, _buildErrorView, _buildFooter (+24 more)

### Community 21 - "faces_screen.dart"
Cohesion: 0.08
Nodes (25): _buildClusterPhotosGrid, _buildClustersList, cacheDir, clusters, createState, cropFile, cropFiles, db (+17 more)

### Community 22 - "package:drift/drift.dart"
Cohesion: 0.20
Nodes (9): createFileEntry, _db, FileRepository, getFileByHash, getFilesInFolder, restoreFile, softDelete, trashFile (+1 more)

### Community 23 - "settings_screen.dart"
Cohesion: 0.07
Nodes (28): advanced_settings_dialogs.dart, appearance_settings_screen.dart, auto_backup_settings_dialogs.dart, backup_dialogs.dart, domain/background_service_manager.dart, _buildDynamicItem, _buildLogoutButton, _buildSearchBar (+20 more)

### Community 24 - "accounts_screen.dart"
Cohesion: 0.06
Nodes (36): ../../core/utils/phone_validator.dart, _loadAdminChannels, DecryptedImageViewer, _DecryptedImageViewerState, AccountsScreen, _AccountsScreenState, build, _buildCard (+28 more)

### Community 25 - "ml_service.dart"
Cohesion: 0.07
Nodes (28): _cropFaceIsolate, cropped, CropTaskArgs, decodedImage, enhanced, h, height, imageBytes (+20 more)

### Community 26 - "ConsumerStatefulWidget"
Cohesion: 0.09
Nodes (27): ConsumerStatefulWidget, DriveScreen, MediaPlayerScreen, _GalleryItem, TelegramAccountCard, AutoLockTimeoutDialog, _AutoLockTimeoutDialogState, build (+19 more)

### Community 27 - "otp_input.dart"
Cohesion: 0.08
Nodes (27): FocusNode, activeColor, build, _checkCompleted, clear, controller, _controllers, createState (+19 more)

### Community 28 - "media_player_screen.dart"
Cohesion: 0.07
Nodes (27): fullscreen_video_screen.dart, _buildActionButton, controller, createState, didUpdateWidget, dispose, _duration, _error (+19 more)

### Community 29 - "drive_screen.dart"
Cohesion: 0.06
Nodes (33): file_picker_util.dart, _buildDropZoneOverlay, _buildLayoutSelector, _buildSortCategoryItem, _buildSortCriteriaItem, _buildSortOrderItem, _checkSecurityAndChannel, _copyFile (+25 more)

### Community 30 - "multi_account_screen.dart"
Cohesion: 0.08
Nodes (24): ../../core/widgets/otp_input.dart, ../../core/widgets/premium_button.dart, _buildCard, _buildCodeInput, _buildConnectedView, _buildErrorView, _buildLoadingView, _buildPhoneInput (+16 more)

### Community 31 - "my_application.cc"
Cohesion: 0.09
Nodes (22): FlPluginRegistry, FlView, GApplication, gboolean, gchar, GObject, GtkApplication, fl_register_plugins() (+14 more)

### Community 32 - "currentFolderIdProvider"
Cohesion: 0.16
Nodes (25): build, _ResponsiveScaffoldState, _buildPathOverview, currentFolderIdProvider, folderItemsCountProvider, folderSizeProvider, isFavoriteOnlyProvider, navigationStackProvider (+17 more)

### Community 33 - "integrity_verification_service.dart"
Cohesion: 0.07
Nodes (28): Digest?, add, chunksChecked, chunksPassed, close, dekWrappingResult, details, _DigestSink (+20 more)

### Community 34 - "search_screen.dart"
Cohesion: 0.10
Nodes (25): ../drive/widgets/file_list_item.dart, ../drive/widgets/folder_grid_item.dart, build, db, filterType, firstMatch, matchedFiles, matchedFolders (+17 more)

### Community 35 - "premium_button.dart"
Cohesion: 0.07
Nodes (29): build, _controller, createState, dispose, enabled, fullWidth, gradient, height (+21 more)

### Community 36 - "places_screen.dart"
Cohesion: 0.09
Nodes (25): build, _buildPlaceFilesGrid, _buildPlacesList, country, counts, createState, db, file (+17 more)

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
Cohesion: 0.10
Nodes (20): app_colors.dart, int get, accentColorValue, copyWith, fontScale, hashCode, highContrast, _loadTheme (+12 more)

### Community 42 - "dart:typed_data"
Cohesion: 0.09
Nodes (20): dart:typed_data, decryptStreamRange, _incrementIv, StreamingEncryptionEngine, CaptionDecryptor, CaptionSerializer, _cipher, deserialize (+12 more)

### Community 43 - "press_and_hold_preview.dart"
Cohesion: 0.09
Nodes (23): build, child, createState, _decryptedBytes, _dismissPreview, dispose, file, _formatBytes (+15 more)

### Community 44 - "Color"
Cohesion: 0.11
Nodes (20): Color, ../features/transfers/transfers_screen.dart, HexColor, transfersStreamProvider, build, createState, _formatSize, _getTransferName (+12 more)

### Community 45 - "ConsumerState"
Cohesion: 0.09
Nodes (28): ConsumerState, FolderPickerDialog, _AuthScreenState, AudioPlayerScreen, _AudioPlayerScreenState, _TelegramAccountCardState, MultiAccountScreen, _MultiAccountScreenState (+20 more)

### Community 46 - "infrastructure_providers.dart"
Cohesion: 0.10
Nodes (20): ../../domain/infrastructure/channel_discovery_service.dart, ../../../domain/infrastructure/infrastructure_provisioning_service.dart, allAccounts, configChannelId, discoveryResult, discoveryService, ensureInfrastructureProvider, InfrastructureStatus (+12 more)

### Community 47 - "smart_analyzer.dart"
Cohesion: 0.08
Nodes (24): double?, AnalysisResult, analyzeAndStore, analyzeImageForUpload, _convertExifGps, country, _db, faces (+16 more)

### Community 48 - "auto_backup_watcher.dart"
Cohesion: 0.09
Nodes (21): folder_scanner.dart, AutoBackupWatcherService, dispose, _handleLocalDelete, _isRunning, _isWifiOrWifiNotRequired, _matchesFilter, _pollTimer (+13 more)

### Community 49 - "integration_settings_dialogs.dart"
Cohesion: 0.10
Nodes (28): _CodeTextViewer, _CodeTextViewerState, _PdfViewer, _PdfViewerState, ApiKeyManagementDialog, _ApiKeyManagementDialogState, build, createState (+20 more)

### Community 50 - "marquee_text.dart"
Cohesion: 0.10
Nodes (20): AlignmentGeometry, alignment, build, _checkScroll, createState, didUpdateWidget, dispose, initState (+12 more)

### Community 51 - "responsive_scaffold.dart"
Cohesion: 0.10
Nodes (20): app_router.dart, ../constants.dart, features/drive/providers/drive_providers.dart, ../../features/sharing/import_link_dialog.dart, ../../features/transfers/widgets/global_progress_bar.dart, _buildStorageCard, child, createState (+12 more)

### Community 52 - "ConsumerWidget"
Cohesion: 0.15
Nodes (21): ConsumerWidget, _GalleryItem, settingsUpdateProvider, FileListItem, _FaceGridItem, _GalleryItemState, thumbnailServiceProvider, _AudioItem (+13 more)

### Community 53 - "testing_ended_screen.dart"
Cohesion: 0.10
Nodes (20): CustomPainter, DogEarFilePainter, StarfieldPainter, build, createState, dispose, _exitApp, _GridPainter (+12 more)

### Community 54 - "infrastructure_provisioning_service.dart"
Cohesion: 0.09
Nodes (21): _archiveAndMuteChannel, configChannelId, configureExistingChannelsAsInfrastructure, _createTelegramFolder, ensureAccountPromotionsAndFolder, ensureInfrastructure, errorMessage, InfrastructureResult (+13 more)

### Community 55 - "webdav_settings_dialog.dart"
Cohesion: 0.11
Nodes (19): ../../domain/webdav/webdav_config.dart, ../../domain/webdav/webdav_server.dart, build, _buildCopyRow, _configService, createState, _creds, dispose (+11 more)

### Community 56 - "health_check_screen.dart"
Cohesion: 0.12
Nodes (15): activeChannelStr, channel, channelId, _compromisedFiles, createState, db, getSetting, _hasScanned (+7 more)

### Community 57 - "../data/db/database.dart"
Cohesion: 0.18
Nodes (10): attachTagToFile, curatedColors, getOrCreateTag, getTagsForFile, _ref, removeTagFromFile, TagService, watchAllTags (+2 more)

### Community 58 - "api_service.dart"
Cohesion: 0.10
Nodes (20): domain/folder_scanner.dart, _authMiddleware, container, _corsMiddleware, _fileToJson, _folderToJson, _handleCreateFolder, _handleGetFile (+12 more)

### Community 59 - "streaming_server.dart"
Cohesion: 0.10
Nodes (20): HttpServer?, _cacheLocalFilePath, _cacheRemoteFileId, _createDecryptionStream, _downloadAndReadRange, _downloadLocks, _handleStream, _localFilePathCache (+12 more)

### Community 60 - "package:flutter_riverpod/flutter_riverpod.dart"
Cohesion: 0.16
Nodes (11): IconData, categories, icon, iconColor, QuickAccessCategory, title, package:aerodrive/features/drive/widgets/channel_setup_wizard_dialog.dart, package:flutter_riverpod/flutter_riverpod.dart (+3 more)

### Community 61 - "decrypted_text_viewer.dart"
Cohesion: 0.11
Nodes (19): build, _buildContent, _codePattern, _codeSpan, _contentWidth, createState, _data, DecryptedTextViewer (+11 more)

### Community 62 - "List"
Cohesion: 0.12
Nodes (16): accounts, addClient, allAdminChannels, allEvents, allSessions, _eventController, getClient, _initPrimaryAndRestore (+8 more)

### Community 63 - "Table"
Cohesion: 0.13
Nodes (19): @DataClassName, Accounts, BackupHistory, Channels, Chunks, FaceClusters, FilePlaces, Files (+11 more)

### Community 64 - "core/providers/repository_providers.dart"
Cohesion: 0.12
Nodes (17): core/providers/repository_providers.dart, build, createState, initState, _isLoading, LoadBalancingScreen, _LoadBalancingScreenState, _loadSettings (+9 more)

### Community 65 - "shared_links_screen.dart"
Cohesion: 0.12
Nodes (18): dart:ui, _checkForInterruptedImports, _resumeImport, build, createState, _error, initState, _isLoading (+10 more)

### Community 66 - "repository_providers.dart"
Cohesion: 0.11
Nodes (18): ../../data/repositories/chunk_repository.dart, ../../data/repositories/file_repository.dart, ../../data/repositories/folder_repository.dart, ../../domain/download_orchestrator.dart, domain/download_queue_service.dart, ../../domain/upload_orchestrator.dart, domain/upload_queue_service.dart, ../../features/api/api_service.dart (+10 more)

### Community 67 - "dropbox_backup_screen.dart"
Cohesion: 0.12
Nodes (18): domain/backup_service.dart, dropbox_service.dart, build, createState, DropboxBackupScreen, _DropboxBackupScreenState, _frequency, initState (+10 more)

### Community 68 - "file_list_item.dart"
Cohesion: 0.23
Nodes (12): AppError, AuthError, cause, CryptoError, FileOperationError, floodWaitSeconds, message, NetworkError (+4 more)

### Community 69 - "advanced_settings_dialogs.dart"
Cohesion: 0.10
Nodes (20): ../../domain/recovery/recovery_scanner.dart, build, _clearCache, ClearCacheDialog, _ClearCacheDialogState, createState, DatabaseStatsDialog, _DatabaseStatsDialogState (+12 more)

### Community 70 - "transfers_screen.dart"
Cohesion: 0.11
Nodes (18): _buildEmptyState, _buildFilterChip, _buildStatusBadge, _cancelTransfer, _clearHistory, createState, _currentFilter, db (+10 more)

### Community 71 - "State"
Cohesion: 0.23
Nodes (12): allMediaFilesProvider, allMediaFoldersProvider, _buildAlbumsTab, _buildOptionsMenu, _buildPhotosTab, _buildTimelineContent, mediaColumnCountProvider, MediaScreen (+4 more)

### Community 72 - "archive_viewer.dart"
Cohesion: 0.12
Nodes (17): Archive?, file_decryption_util.dart, _archive, ArchiveViewer, _ArchiveViewerState, build, createState, _entries (+9 more)

### Community 73 - "encryption_engine.dart"
Cohesion: 0.11
Nodes (17): Cipher, _argon2, _argon2LowEnd, _cipher, decryptBytes, decryptDiskToStream, deriveMasterKey, deriveMasterKeyFromPhrase (+9 more)

### Community 74 - "package:flutter/material.dart"
Cohesion: 0.40
Nodes (5): build, fileId, FileTagsRow, fileTagsStreamProvider, ../../tags/tag_providers.dart

### Community 75 - "StatelessWidget"
Cohesion: 0.11
Nodes (17): ../faces/faces_screen.dart, _DesktopLayout, _MobileLayout, _TabletLayout, PremiumSwitch, PremiumTextField, StorageBanner, StorageWidget (+9 more)

### Community 76 - "aerodrive_theme.dart"
Cohesion: 0.12
Nodes (16): AeroDriveTheme, _buildTextTheme, _defaultAccent, _defaultSecondary, getDark, getLight, gradient, icon (+8 more)

### Community 77 - "package:path_provider/path_provider.dart"
Cohesion: 0.07
Nodes (30): dart:io, AppResetHelper, showResetConfirmation, migration, _openConnection, schemaVersion, BootService, _channel (+22 more)

### Community 78 - "decrypted_image_viewer.dart"
Cohesion: 0.12
Nodes (16): build, createState, _decryptedFile, dispose, _downloadFullChunk, _error, file, initState (+8 more)

### Community 79 - "tag_dialog.dart"
Cohesion: 0.14
Nodes (17): _addTag, build, createState, file, _fileTags, fromHex, initState, _isLoading (+9 more)

### Community 80 - "win32_window.cpp"
Cohesion: 0.18
Nodes (14): Point, Size, wchar_t, Scale(), Create, Destroy, UpdateTheme, Win32Window::Win32Window() (+6 more)

### Community 81 - "AeroDriveBackupService"
Cohesion: 0.17
Nodes (10): AeroDriveBackupService, Context, FlutterEngine, Int, Intent, start(), stop(), IBinder (+2 more)

### Community 82 - "realtime_sync_service.dart"
Cohesion: 0.12
Nodes (15): config_sync_service.dart, _configChatId, dispose, _getConfigChatId, _handleDeleteMessages, _handleMessageContent, _handleNewMessage, _initializeBackgroundSyncChats (+7 more)

### Community 83 - "thumbnail_service.dart"
Cohesion: 0.12
Nodes (14): core/logger.dart, ../../data/crypto/encryption_engine.dart, ../../domain/thumbnail_cache_manager.dart, BackgroundServiceManager, _channel, startService, stopService, _downloadFile (+6 more)

### Community 84 - "dart:io"
Cohesion: 0.13
Nodes (13): dart:math, data/repositories/settings_repository.dart, Directory, EncryptionEngine, ChannelLoadBalancer, getStorageChannels, selectFileBaseIndex, selectStorageChannel (+5 more)

### Community 85 - "channels_screen.dart"
Cohesion: 0.10
Nodes (22): ../../domain/sync/config_sync_service.dart, ../drive/widgets/channel_setup_wizard_dialog.dart, configSyncServiceProvider, _activeChannelId, build, ChannelsScreen, _ChannelsScreenState, _confirmAndAddChannel (+14 more)

### Community 86 - "upload_orchestrator.dart"
Cohesion: 0.10
Nodes (19): chunkLength, chunkLimit, computeFileHash, ctrIv, dekBytes, EncryptJobPayload, getOptimalChunkSize, handoffToTelegram (+11 more)

### Community 87 - "debug_error_screen.dart"
Cohesion: 0.11
Nodes (19): build, _commentController, _copyToClipboard, createState, DebugErrorScreen, _DebugErrorScreenState, dispose, error (+11 more)

### Community 88 - "appearance_settings_screen.dart"
Cohesion: 0.12
Nodes (15): core/theme/aerodrive_theme.dart, core/theme/theme_provider.dart, AeroThemePreset, defaultVal, icon, isSelected, label, onTap (+7 more)

### Community 89 - "folder_repository.dart"
Cohesion: 0.13
Nodes (15): Exception, createFolder, _db, FolderNameTooLongException, FolderPathTooLongException, getFolderContents, getFolderPath, getSubfolders (+7 more)

### Community 90 - "config_sync_service.dart"
Cohesion: 0.12
Nodes (15): _archiveAndMute, checkConfigStatus, _configChannelName, ConfigStatus, ConfigSyncService, _configWarningText, error, findConfigChannel (+7 more)

### Community 91 - "file_type_icon.dart"
Cohesion: 0.13
Nodes (15): fileIconStyleProvider, build, _buildColored, _buildFilled, _buildMinimal, _buildOutlined, color, fileName (+7 more)

### Community 92 - "file_grid_item.dart"
Cohesion: 0.07
Nodes (29): file_type_icon.dart, ../gallery/thumbnail_service.dart, _buildFilePlaceholder, _buildOptionsMenu, _buildTypeBadgeIcon, createState, didUpdateWidget, file (+21 more)

### Community 93 - "memories_screen.dart"
Cohesion: 0.06
Nodes (31): IOSink?, _autoFlushTimer, _closeSink, _currentFileName, detectCrashedUpload, dispose, _ensureDir, _fileIoFailed (+23 more)

### Community 94 - "places_service.dart"
Cohesion: 0.12
Nodes (15): admin, _cities, _convertToDecimal, country, fromJson, lat, _loadCities, lon (+7 more)

### Community 95 - "dropbox_service.dart"
Cohesion: 0.09
Nodes (20): key, null, telegramService, userId, _checkStatus, _clientId, _clientSecret, connected (+12 more)

### Community 96 - "FlutterWindow"
Cohesion: 0.13
Nodes (13): unique_ptr, DartProject, HWND, LPARAM, LRESULT, UINT, WPARAM, FlutterWindow (+5 more)

### Community 97 - "auth_provider.dart"
Cohesion: 0.18
Nodes (11): ../../core/providers/infrastructure_providers.dart, ../../core/providers/security_providers.dart, AuthNotifier, AuthState, _ensureInfrastructure, forceUnauthenticated, _hasBeenAuthenticated, _init (+3 more)

### Community 98 - "gallery_screen.dart"
Cohesion: 0.15
Nodes (14): File?, build, createState, db, file, _GalleryItem, GalleryScreenContent, initState (+6 more)

### Community 99 - "logger.dart"
Cohesion: 0.12
Nodes (15): _addLog, AppLogger, clearSavedCrashLog, error, getSavedCrashLog, hasSavedCrashLog, info, init (+7 more)

### Community 100 - "face_recognition_service.dart"
Cohesion: 0.14
Nodes (14): avatarFileId, DbFaceService, FaceCluster, faceClustersProvider, FaceRecognitionService, faceRecognitionServiceProvider, faceService, getClusters (+6 more)

### Community 101 - "folder_picker_dialog.dart"
Cohesion: 0.09
Nodes (22): ../../../domain/channel_load_balancer.dart, ../../domain/recovery/manifest_encoder.dart, build, CreateFolderDialog, createState, dispose, _nameController, _selectedColorHex (+14 more)

### Community 102 - "proxy_settings_screen.dart"
Cohesion: 0.14
Nodes (14): build, createState, initState, _isEnabled, _isLoading, _loadSettings, _passCtrl, _portCtrl (+6 more)

### Community 103 - "preview_router.dart"
Cohesion: 0.13
Nodes (14): archive_viewer.dart, audio_player_screen.dart, image_gallery_screen.dart, build, _downloadAndOpen, fileId, _isPreviewable, openPreview (+6 more)

### Community 104 - "manifest_encoder.dart"
Cohesion: 0.09
Nodes (20): caption_codec.dart, _buildMap, _captionSafetyLimit, decodeManifest, encodeFileManifest, encodeFolderManifest, encodeThumbnailManifest, _estimatedEncryptedSize (+12 more)

### Community 105 - "channel_discovery_service.dart"
Cohesion: 0.10
Nodes (18): bool get, channel_description_codec.dart, ../core/utils/reset_helper.dart, ../features/telegram/telegram_service.dart, ChannelDiscoveryService, configChannelId, discoverInfrastructure, DiscoveryResult (+10 more)

### Community 106 - "purge_job.dart"
Cohesion: 0.14
Nodes (13): dart:isolate, chunksToDelete, completeHardDelete, deleteTelegramMessages, ExpiredMessagesPayload, fileIdsToPurge, findExpiredItems, folderIdsToPurge (+5 more)

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
Cohesion: 0.20
Nodes (10): build, createState, _currentIndex, dispose, files, initialIndex, initState, _pageController (+2 more)

### Community 113 - "import_link_dialog.dart"
Cohesion: 0.07
Nodes (27): Completer, ../drive/widgets/folder_picker_dialog.dart, build, _buildActions, _buildContent, _buildDetailRow, _buildTitle, _confirmCompleter (+19 more)

### Community 114 - "app_error.dart"
Cohesion: 0.29
Nodes (7): _buildExploreTab, exploreDataProvider, build, Route /media/memories, Route /media/people, Route /media/places, Route /media/smart-tags

### Community 115 - "_AeroDriveAppState"
Cohesion: 0.21
Nodes (13): downloadQueueServiceProvider, uploadQueueServiceProvider, routerProvider, themeProvider, backupServiceProvider, realtimeSyncServiceProvider, AppearanceSettingsScreen, build (+5 more)

### Community 116 - "smart_tags_screen.dart"
Cohesion: 0.17
Nodes (12): _buildFallbackGradient, _buildTagFilesView, _buildTagsGridView, createState, file, _isLoadingFiles, _loadTagFiles, _selectedTag (+4 more)

### Community 117 - "about_screen.dart"
Cohesion: 0.15
Nodes (12): AboutScreen, build, _buildAppHero, _buildCard, _buildDeveloperCard, _buildDivider, _buildLinkTile, _buildSignatureCredit (+4 more)

### Community 118 - "companion_server_dialogs.dart"
Cohesion: 0.17
Nodes (12): build, CompanionServerDialog, _CompanionServerDialogState, createState, initState, _isLoading, _keyController, _load (+4 more)

### Community 119 - "core/logger.dart"
Cohesion: 0.40
Nodes (5): faceClustersProvider, build, FacesScreen, _FacesScreenState, _mergeSelectedClusters

### Community 120 - "dart:async"
Cohesion: 0.15
Nodes (16): auth_provider.dart, dart:async, authProvider, build, build, createState, dispose, InfrastructureSetupScreen (+8 more)

### Community 121 - "video_thumbnail_service.dart"
Cohesion: 0.20
Nodes (9): Duration, duration, generateSmartThumbnail, _getDurationOnly, path, VideoThumbnailResult, VideoThumbnailService, videoThumbnailServiceProvider (+1 more)

### Community 122 - "wWinMain"
Cohesion: 0.24
Nodes (9): _In_, _In_opt_, vector, wWinMain(), string, wchar_t, CreateAndAttachConsole(), GetCommandLineArguments() (+1 more)

### Community 123 - "repository_test.dart"
Cohesion: 0.11
Nodes (18): ChunkRepository, FolderRepository, SettingsRepository, package:aerodrive/data/db/database.dart, package:aerodrive/data/repositories/chunk_repository.dart, package:aerodrive/data/repositories/file_repository.dart, package:aerodrive/data/repositories/folder_repository.dart, package:aerodrive/data/repositories/settings_repository.dart (+10 more)

### Community 124 - "recovery_scanner.dart"
Cohesion: 0.18
Nodes (11): _db, RecoveryScanner, _ref, runDisasterRecovery, telegram, _telegramService, ZeroDBRecoveryService, manifest_encoder.dart (+3 more)

### Community 125 - "isSelectionModeProvider"
Cohesion: 0.21
Nodes (17): _buildAppBar, _handleCopySelected, _handleDeleteSelected, _handleDownloadSelected, _handleMoveSelected, isSelectionModeProvider, selectedItemsProvider, build (+9 more)

### Community 126 - "media_settings_dialogs.dart"
Cohesion: 0.20
Nodes (11): build, ClearThumbnailCacheDialog, createState, initState, _load, _quality, _size, ThumbnailCacheSizeDialog (+3 more)

### Community 127 - "splash_screen.dart"
Cohesion: 0.15
Nodes (13): build, createState, initState, paint, _progress, random, _runSync, shouldRepaint (+5 more)

### Community 128 - "Ref"
Cohesion: 0.11
Nodes (17): Battery, ../core/providers.dart, AIQueueService, aiQueueServiceProvider, _battery, _isProcessing, _ref, triggerQueue (+9 more)

### Community 129 - "settings_repository.dart"
Cohesion: 0.15
Nodes (12): _, @DriftDatabase, AeroDriveDatabase, clearAllSettings, clearSetting, _db, getBoolSetting, getIntSetting (+4 more)

### Community 130 - "build"
Cohesion: 0.06
Nodes (30): Digest? get, add, _BatchEncryptionEngine, BatchEncryptor, _BatchPayload, BatchResult, batchSize, _bufferSize (+22 more)

### Community 131 - "backup_folder_mapper.dart"
Cohesion: 0.20
Nodes (10): BackupFolderMapper, _BackupFolderMapperState, build, _controller, createState, dispose, initState, _isLoading (+2 more)

### Community 132 - "manifest.json"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 133 - "master_key_provider.dart"
Cohesion: 0.50
Nodes (4): AeroThemeState, ThemeNotifier, DropboxService, StateNotifier

### Community 134 - "MessageHandler"
Cohesion: 0.36
Nodes (10): HWND, LPARAM, LRESULT, UINT, WPARAM, EnableFullDpiSupportIfAvailable(), GetHandle, GetThisFromHandle (+2 more)

### Community 135 - "file_decryption_util.dart"
Cohesion: 0.11
Nodes (17): ../../core/security/master_key_provider.dart, ../data/db/database.dart, db, hasNavigatedPastSplashProvider, channel, paths, pickFilesForUpload, result (+9 more)

### Community 136 - "dart:convert"
Cohesion: 0.50
Nodes (4): streamingServerProvider, _initStream, _initStream, _initStreamForCurrent

### Community 137 - "database.dart"
Cohesion: 0.10
Nodes (20): ../core/theme/app_colors.dart, build, build, build, PreviewScreen, build, _buildAvatar, ProfileScreen (+12 more)

### Community 138 - "package:cryptography/cryptography.dart"
Cohesion: 0.10
Nodes (17): ../../../core/constants.dart, dart:convert, ChannelDescriptionCodec, _cipher, decode, encode, readPurpose, package:aerodrive/core/constants.dart (+9 more)

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
Cohesion: 0.33
Nodes (5): DateTime, FileSizeExtension, RelativeTimeExtension, truncate, TruncateExtension

### Community 144 - "propfind_handler.dart"
Cohesion: 0.33
Nodes (5): handle, PropfindHandler, package:shelf/shelf.dart, package:xml/xml.dart, XmlElement

### Community 145 - "file_tags_row.dart"
Cohesion: 0.28
Nodes (8): _TransferBadge, _showBackgroundTasksBottomSheet, aggregateTransferProgressProvider, build, db, GlobalProgressBar, select, Route /transfers

### Community 146 - "MainActivity"
Cohesion: 0.40
Nodes (3): FlutterEngine, MainActivity, FlutterFragmentActivity

### Community 149 - "MaterialPageRoute"
Cohesion: 0.14
Nodes (14): FolderData, build, createState, dispose, _error, file, folder, _hasPassword (+6 more)

### Community 151 - "_DigestSink"
Cohesion: 0.19
Nodes (12): fileRepositoryProvider, _showDeleteConfirm, _showDeleteConfirm, _showDeleteConfirm, build, db, files, folders (+4 more)

### Community 162 - "queue_repository.dart"
Cohesion: 0.13
Nodes (15): ../db/database.dart, _db, getChunksForFile, insertChunk, updateChunkMessageId, _uuid, _db, enqueueUpload (+7 more)

### Community 163 - "build"
Cohesion: 0.22
Nodes (9): build, Route /diagnostics, Route /settings/about, Route /settings/accounts, Route /settings/backup/dropbox, Route /settings/channels/health, Route /settings/profile, Route /settings/session (+1 more)

### Community 167 - "_HealthCheckScreenState"
Cohesion: 0.40
Nodes (6): activeChannelIdProvider, activeChannelNameProvider, build, HealthCheckScreen, _HealthCheckScreenState, Route /settings/channels

### Community 168 - "aerodrive_logo.dart"
Cohesion: 0.40
Nodes (4): AeroDriveLogo, build, size, ../theme/app_colors.dart

### Community 169 - "MaterialPageRoute"
Cohesion: 0.50
Nodes (4): build, _openGeneric, _openUniversalViewer, MaterialPageRoute

## Knowledge Gaps
- **2121 isolated node(s):** `message`, `cause`, `floodWaitSeconds`, `toString`, `AppConstants` (+2116 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **7 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `settingsRepositoryProvider` connect `settingsRepositoryProvider` to `core/providers/repository_providers.dart`, `repository_providers.dart`, `dropbox_backup_screen.dart`, `backup_folder_mapper.dart`, `proxy_settings_screen.dart`, `MaterialPageRoute`, `ConsumerState`, `auto_backup_settings_dialogs.dart`, `_AeroDriveAppState`, `ConsumerWidget`, `backup_dialogs.dart`, `channels_screen.dart`, `accounts_screen.dart`, `List`, `ConsumerStatefulWidget`, `media_player_screen.dart`, `media_settings_dialogs.dart`?**
  _High betweenness centrality (0.009) - this node is a cross-community bridge._
- **Why does `AeroDriveDatabase` connect `settings_repository.dart` to `Ref`, `queue_repository.dart`, `upload_queue_service.dart`, `file_decryption_util.dart`, `manifest_encoder.dart`, `package:path_provider/path_provider.dart`, `download_queue_service.dart`, `folder_scanner.dart`, `smart_analyzer.dart`, `package:drift/drift.dart`, `folder_repository.dart`, `repository_test.dart`, `recovery_scanner.dart`?**
  _High betweenness centrality (0.005) - this node is a cross-community bridge._
- **Why does `_DriveScreenState` connect `settingsRepositoryProvider` to `currentFolderIdProvider`, `shared_links_screen.dart`, `databaseProvider`, `Color`, `ConsumerState`, `file_tags_row.dart`, `channels_screen.dart`, `isSelectionModeProvider`, `_DigestSink`, `ConsumerStatefulWidget`, `drive_screen.dart`?**
  _High betweenness centrality (0.004) - this node is a cross-community bridge._
- **What connects `message`, `cause`, `floodWaitSeconds` to the rest of the system?**
  _2121 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `tables.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.021052631578947368 - nodes in this community are weakly interconnected._
- **Should `telegram_service.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.02531645569620253 - nodes in this community are weakly interconnected._
- **Should `media_screen.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.0425531914893617 - nodes in this community are weakly interconnected._