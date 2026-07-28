# Graph Report - .  (2026-07-27)

## Corpus Check
- 247 files · ~155,162 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3444 nodes · 5662 edges · 195 communities (185 shown, 10 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 56 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Database & Schema
- Telegram Client Service
- Media UI Screens
- Windows Build Config
- Sharing Service
- Theme & Colors
- Upload Pipeline
- WebDAV Server
- Package Dependencies
- Linux Desktop Build
- Deep Link Handling
- Core Providers & DB
- Audio UI Screen
- Android Notifications
- Drive UI Providers
- Community 15
- Community 16
- Community 17
- Community 18
- Community 19
- Community 20
- Community 21
- Community 22
- Community 23
- Community 24
- Community 25
- Community 26
- Community 27
- Community 28
- Community 29
- Community 30
- Community 31
- Community 32
- Community 33
- Community 34
- Community 35
- Community 36
- Community 37
- Community 38
- Community 39
- Community 40
- Community 41
- Community 42
- Community 43
- Community 44
- Community 45
- Community 46
- Community 47
- Community 48
- Community 49
- Community 50
- Community 51
- Community 52
- Community 53
- Community 54
- Community 55
- Community 56
- Community 57
- Community 58
- Community 59
- Community 60
- Community 61
- Community 62
- Community 63
- Community 64
- Community 65
- Community 66
- Community 67
- Community 68
- Community 69
- Community 70
- Community 71
- Community 72
- Community 73
- Community 74
- Community 75
- Community 76
- Community 77
- Community 78
- Community 79
- Community 80
- Community 81
- Community 82
- Community 83
- Community 84
- Community 85
- Community 86
- Community 87
- Community 88
- Community 89
- Community 90
- Community 91
- Community 92
- Community 93
- Community 94
- Community 95
- Community 96
- Community 97
- Community 98
- Community 99
- Community 100
- Community 101
- Community 102
- Community 103
- Community 104
- Community 105
- Community 106
- Community 107
- Community 108
- Community 109
- Community 110
- Community 111
- Community 112
- Community 113
- Community 114
- Community 115
- Community 116
- Community 117
- Community 118
- Community 119
- Community 120
- Community 121
- Community 122
- Community 123
- Community 124
- Community 125
- Community 126
- Community 127
- Community 128
- Community 129
- Community 130
- Community 131
- Community 132
- Community 133
- Community 134
- Community 135
- Community 136
- Community 137
- Community 138
- Community 139
- Community 140
- Community 141
- Community 142
- Community 143
- Community 144
- Community 145
- Community 146
- Community 147
- Community 148
- Community 149
- Community 150
- Community 151
- Community 152
- Community 153
- Community 154
- Community 155
- Community 156
- Community 157
- Community 158
- Community 159
- Community 160
- Community 161
- Community 162
- Community 163
- Community 164
- Community 165
- Community 188
- Community 189
- Community 190

## God Nodes (most connected - your core abstractions)
1. `databaseProvider` - 70 edges
2. `settingsRepositoryProvider` - 65 edges
3. `Telegram` - 46 edges
4. `AsyncResult` - 36 edges
5. `dbRebuildVersionProvider` - 30 edges
6. `telegramManagerProvider` - 30 edges
7. `_DriveScreenState` - 27 edges
8. `currentFolderIdProvider` - 23 edges
9. `telegramServiceProvider` - 22 edges
10. `Win32Window` - 22 edges

## Surprising Connections (you probably didn't know these)
- `AeroDrive (README)` --semantically_similar_to--> `AeroDrive`  [INFERRED] [semantically similar]
  README.md → PROJECT_BRIEF.md
- `Zero-DB Recovery (README)` --semantically_similar_to--> `Zero-DB Recovery via Manifest Messages`  [INFERRED] [semantically similar]
  README.md → PROJECT_BRIEF.md
- `Local AI Face Clustering` --semantically_similar_to--> `On-Device ML Kit (face detection + labeling)`  [INFERRED] [semantically similar]
  README.md → PROJECT_BRIEF.md
- `Upload Data Flow` --references--> `UploadOrchestrator`  [INFERRED]
  docs/ARCHITECTURE.md → PROJECT_BRIEF.md
- `Graphify Knowledge Graph System` --conceptually_related_to--> `AeroDrive Project`  [INFERRED]
  AGENTS.md → app/README.md

## Import Cycles
- 1-file cycle: `tdlib_dl/extracted/telegram/text.py -> tdlib_dl/extracted/telegram/text.py`

## Hyperedges (group relationships)
- **Upload Pipeline** — project_brief_upload_orchestrator, project_brief_encryption_engine, project_brief_tdlib_ffi_bridge, project_brief_multi_account_pooling, project_brief_flood_wait_handling, project_brief_drift_schema [INFERRED 0.95]
- **Zero-Knowledge Security Architecture** — project_brief_zero_knowledge_encryption, project_brief_key_hierarchy, project_brief_aes256_gcm, project_brief_aes256_ctr, project_brief_argon2id_kdf, project_brief_duress_pin, project_brief_convenience_mode, project_brief_max_security_mode [INFERRED 0.95]
- **Zero-DB Recovery System** — project_brief_zero_db_recovery, project_brief_recovery_scanner, project_brief_caption_embedding, project_brief_manifest_versioning, project_brief_drift_schema [INFERRED 0.95]
- **Flutter Web Application Entry** — app_web_index, flutter_framework, flutter_web_bootstrap, aerodrive_project [EXTRACTED 1.00]
- **TDLib Native Package Distribution** — tdlib_dl_extracted_changelog, tdlib_native_package, tdlib_library, fornever_project [EXTRACTED 1.00]
- **Project Knowledge Management Infrastructure** — agents_md, graphify_knowledge_graph, aerodrive_project [EXTRACTED 1.00]

## Communities (195 total, 10 thin omitted)

### Community 0 - "Database & Schema"
Cohesion: 0.02
Nodes (94): accountId, adminArea, boxHeight, boxLeft, boxTop, boxWidth, burnAfterReading, bytesTransferred (+86 more)

### Community 1 - "Telegram Client Service"
Cohesion: 0.03
Nodes (72): accountId, addAdminToChat, addProxy, _apiHash, _apiId, authState, chats, checkAdminStatus (+64 more)

### Community 2 - "Media UI Screens"
Cohesion: 0.04
Nodes (61): _AlbumItemData, allFiles, allMediaFilesProvider, allMediaFoldersProvider, allTags, build, _buildActiveFiltersHeader, _buildAlbumCard (+53 more)

### Community 3 - "Windows Build Config"
Cohesion: 0.06
Nodes (53): RegisterPlugins(), DartProject, HWND, LPARAM, LRESULT, UINT, WPARAM, FlutterWindow (+45 more)

### Community 4 - "Sharing Service"
Cohesion: 0.04
Nodes (47): _addTempJoinedChannel, _archiveAndMute, _buildFlatImportList, channelId, cleanupInterruptedTempChannels, _copyAndReEncryptFile, _copyAndReEncryptFileResumable, createdAt (+39 more)

### Community 5 - "Theme & Colors"
Cohesion: 0.04
Nodes (46): AppColors, background, error, fileArchive, fileAudio, fileCode, fileDocument, fileFolder (+38 more)

### Community 6 - "Upload Pipeline"
Cohesion: 0.04
Nodes (45): ActiveUploadInfo, add, _calculateFileHash, chatId, chunkIndex, close, _db, dispose (+37 more)

### Community 7 - "WebDAV Server"
Cohesion: 0.04
Nodes (45): _activePort, _authMiddleware, creds, _delete, _downloadFile, _fromMainPort, _handleDelete, _handleGet (+37 more)

### Community 8 - "Package Dependencies"
Cohesion: 0.05
Nodes (46): Flutter Dependencies (pinned versions), API Rate Limiting, REST API Endpoints, WebDAV Protocol (on-the-fly decrypt/encrypt), Download Data Flow, System Architecture Layers, Upload Data Flow, AGPL-3.0 Compliance (+38 more)

### Community 9 - "Linux Desktop Build"
Cohesion: 0.08
Nodes (45): Linux aerodrive Executable Target, Windows aerodrive WIN32 Executable Target, Linux AOT Library lib/app.so, Windows AOT Library windows/app.so, Linux Top-level CMakeLists.txt, Linux Flutter CMakeLists.txt, Linux Runner CMakeLists.txt, Windows Top-level CMakeLists.txt (+37 more)

### Community 10 - "Deep Link Handling"
Cohesion: 0.05
Nodes (36): app_links, RegisterGeneratedPlugins(), AppDelegate, MainFlutterWindow, RunnerTests, audio_session, battery_plus, Bool (+28 more)

### Community 11 - "Core Providers & DB"
Cohesion: 0.09
Nodes (40): databaseProvider, fileRepositoryProvider, folderRepositoryProvider, _handleDeleteSelected, _showDeleteConfirm, dbRebuildVersionProvider, FileGridItem, _showDeleteConfirm (+32 more)

### Community 12 - "Audio UI Screen"
Cohesion: 0.07
Nodes (37): audioFiles, audiosProvider, AudiosScreen, build, db, file, _formatFileSize, build (+29 more)

### Community 13 - "Android Notifications"
Cohesion: 0.05
Nodes (39): AndroidFlutterLocalNotificationsPlugin, actionStream, _actionStreamController, _formatBytes, getSafeNotificationId, initialize, _initialized, instance (+31 more)

### Community 14 - "Drive UI Providers"
Cohesion: 0.05
Nodes (39): anyFile, audioCount, breadcrumbs, calculateFolderSize, categoryPriority, contents, copyWith, criteria (+31 more)

### Community 15 - "Community 15"
Cohesion: 0.05
Nodes (38): AppDestination, authState, hasNavigatedPastSplash, icon, label, path, selectedIcon, ../../features/auth/auth_provider.dart (+30 more)

### Community 16 - "Community 16"
Cohesion: 0.05
Nodes (36): ActiveDownloadInfo, _activeDownloads, chunkIndex, _chunkTimeout, _completionController, _db, dispose, DownloadCompletionEvent (+28 more)

### Community 17 - "Community 17"
Cohesion: 0.06
Nodes (35): animFast, animNormal, animSlow, AppConstants, appName, appVersion, argon2Iterations, argon2Memory (+27 more)

### Community 18 - "Community 18"
Cohesion: 0.06
Nodes (35): autoBackupWatcherProvider, AddBackupProfileDialog, _AddBackupProfileDialogState, _backupMode, build, _checkBatteryOptimizations, createState, _deleteBehavior (+27 more)

### Community 19 - "Community 19"
Cohesion: 0.06
Nodes (34): build, _archive, ArchiveViewer, _ArchiveViewerState, build, createState, _entries, _error (+26 more)

### Community 20 - "Community 20"
Cohesion: 0.07
Nodes (31): db, hasNavigatedPastSplashProvider, build, createState, _currentIndex, dispose, files, initialIndex (+23 more)

### Community 21 - "Community 21"
Cohesion: 0.06
Nodes (34): _appLinks, _backgroundContainer, _backgroundIsSyncing, _backgroundLockSocket, createState, currentFolderId, deviceName, dispose (+26 more)

### Community 22 - "Community 22"
Cohesion: 0.06
Nodes (33): build, _buildCodeContent, _buildHighlightedLine, createState, _data, dispose, _error, ext (+25 more)

### Community 23 - "Community 23"
Cohesion: 0.09
Nodes (15): Adds new contacts or edits existing contacts by their phone numbers.         htt, This is offline request, if there is no chat in your database it will not be fou, Returns a list of chats:          Returns:             {                 '@type', Returns history of a chat          Args:             chat_id             limit, Return a message via its message_id          Args:             chat_id, Delete a list of messages in a chat          Args:             chat_id, Get the full info of a supergroup          Args:             supergroup_id, Create a chat from a basic group          Args:             basic_group_id (+7 more)

### Community 24 - "Community 24"
Cohesion: 0.07
Nodes (32): AeroDriveLogo, build, _controller, createState, dispose, enabled, fullWidth, gradient (+24 more)

### Community 25 - "Community 25"
Cohesion: 0.11
Nodes (31): settingsRepositoryProvider, masterKeyProvider, recoveryServiceProvider, configSyncServiceProvider, _runConfigAndSetupCheck, _showNewOptionsBottomSheet, _MediaPlayerScreenState, _CreateFolderDialogState (+23 more)

### Community 26 - "Community 26"
Cohesion: 0.06
Nodes (31): _buildAuthSection, _buildCard, _buildCodeEntry, _buildCurrentView, _buildErrorView, _buildFooter, _buildInitializing, _buildLogo (+23 more)

### Community 27 - "Community 27"
Cohesion: 0.07
Nodes (31): _backupData, BackupExportDialog, _BackupExportDialogState, BackupImportDialog, _BackupImportDialogState, BackupScheduleDialog, _BackupScheduleDialogState, build (+23 more)

### Community 28 - "Community 28"
Cohesion: 0.07
Nodes (28): infrastructureProvisioningServiceProvider, AccountsScreen, _AccountsScreenState, _buildCard, _buildCodeInput, _buildConnectedView, _buildErrorView, _buildLoadingView (+20 more)

### Community 29 - "Community 29"
Cohesion: 0.14
Nodes (28): isAppUnlockedProvider, build, _ResponsiveScaffoldState, folderScannerProvider, build, _buildPathOverview, _DriveScreenState, initState (+20 more)

### Community 30 - "Community 30"
Cohesion: 0.07
Nodes (28): _createDecryptionStream, StreamingServer, AuthScreen, _AuthScreenState, TelegramSelfBackupDialog, _startScan, build, createState (+20 more)

### Community 31 - "Community 31"
Cohesion: 0.07
Nodes (28): _buildLayoutSelector, _buildSortCategoryItem, _buildSortCriteriaItem, _buildSortOrderItem, _checkSecurityAndChannel, _copyFile, _copyFolder, createState (+20 more)

### Community 32 - "Community 32"
Cohesion: 0.08
Nodes (27): _buildFilePlaceholder, _buildOptionsMenu, _buildTypeBadgeIcon, createState, didUpdateWidget, file, _FileThumbnail, _FileThumbnailState (+19 more)

### Community 33 - "Community 33"
Cohesion: 0.07
Nodes (28): _cropFaceIsolate, cropped, CropTaskArgs, decodedImage, enhanced, h, height, imageBytes (+20 more)

### Community 34 - "Community 34"
Cohesion: 0.07
Nodes (27): advanced_settings_dialogs.dart, _buildDynamicItem, _buildLogoutButton, _buildSearchBar, _buildSettingsGroup, _buildSwitchTile, _buildTile, createState (+19 more)

### Community 35 - "Community 35"
Cohesion: 0.07
Nodes (26): FileSizeExtension, RelativeTimeExtension, truncate, TruncateExtension, AnalysisResult, analyzeAndStore, analyzeImageForUpload, _convertExifGps (+18 more)

### Community 36 - "Community 36"
Cohesion: 0.08
Nodes (27): activeColor, build, _checkCompleted, clear, controller, _controllers, createState, dispose (+19 more)

### Community 37 - "Community 37"
Cohesion: 0.07
Nodes (27): _buildActionButton, controller, createState, didUpdateWidget, dispose, _duration, _error, file (+19 more)

### Community 38 - "Community 38"
Cohesion: 0.08
Nodes (26): _buildCard, _buildCodeInput, _buildConnectedView, _buildErrorView, _buildLoadingView, _buildPhoneInput, _buildViewForState, client (+18 more)

### Community 39 - "Community 39"
Cohesion: 0.09
Nodes (22): fl_register_plugins(), main(), first_frame_cb(), my_application_activate(), my_application_class_init(), my_application_dispose(), my_application_init(), my_application_local_command_line() (+14 more)

### Community 40 - "Community 40"
Cohesion: 0.08
Nodes (25): add, chunksChecked, chunksPassed, close, dekWrappingResult, details, _engine, fileId (+17 more)

### Community 41 - "Community 41"
Cohesion: 0.10
Nodes (25): MediaPlayerScreen, CreateFolderDialog, AutoLockTimeoutDialog, _AutoLockTimeoutDialogState, build, createState, DuressPinDialog, _DuressPinDialogState (+17 more)

### Community 42 - "Community 42"
Cohesion: 0.08
Nodes (25): _buildClusterPhotosGrid, _buildClustersList, cacheDir, clusters, createState, cropFile, cropFiles, db (+17 more)

### Community 43 - "Community 43"
Cohesion: 0.09
Nodes (25): build, _buildPlaceFilesGrid, _buildPlacesList, country, counts, createState, db, file (+17 more)

### Community 44 - "Community 44"
Cohesion: 0.10
Nodes (25): build, db, filterType, firstMatch, matchedFiles, matchedFolders, matches, parsed (+17 more)

### Community 45 - "Community 45"
Cohesion: 0.08
Nodes (24): _allFolders, build, _buildFolderTile, _buildRootTile, _buildTree, _collectDescendantIds, createState, currentFolderId (+16 more)

### Community 46 - "Community 46"
Cohesion: 0.12
Nodes (10): FrameType, Any, Calls `close` tdlib method and waits until authorization_state becomes CLOSED., Requests information of the current user (getMe method)          https://core.te, Requests information about a user with id = user_id.          https://core.teleg, Requests the full information about a user with id = user_id.          https://c, Use this method to call any other method of the tdlib          Args:, Remove a handler with the specified type (+2 more)

### Community 47 - "Community 47"
Cohesion: 0.09
Nodes (21): BackgroundServiceManager, _channel, startService, stopService, BootService, _channel, isBootCompleted, chunkLimit (+13 more)

### Community 48 - "Community 48"
Cohesion: 0.09
Nodes (22): build, createState, dispose, InfrastructureSetupScreen, _InfrastructureSetupScreenState, initState, _progress, _progressTimer (+14 more)

### Community 49 - "Community 49"
Cohesion: 0.08
Nodes (23): build, _changeSpeed, controller, createState, dispose, _duration, _error, file (+15 more)

### Community 50 - "Community 50"
Cohesion: 0.09
Nodes (22): app_colors.dart, accentColorValue, AeroThemeState, copyWith, fontScale, hashCode, highContrast, _loadTheme (+14 more)

### Community 51 - "Community 51"
Cohesion: 0.09
Nodes (22): build, child, createState, _decryptedBytes, _dismissPreview, dispose, file, _formatBytes (+14 more)

### Community 52 - "Community 52"
Cohesion: 0.12
Nodes (22): _GalleryItemState, _GalleryItemState, AutoRetryCountDialog, _AutoRetryCountDialogState, BandwidthLimitDialog, _BandwidthLimitDialogState, build, createState (+14 more)

### Community 53 - "Community 53"
Cohesion: 0.09
Nodes (21): AutoBackupWatcherService, dispose, _handleLocalDelete, _isRunning, _isWifiOrWifiNotRequired, _matchesFilter, _pollTimer, _queueFile (+13 more)

### Community 54 - "Community 54"
Cohesion: 0.10
Nodes (21): backupServiceProvider, build, createState, DropboxBackupScreen, _DropboxBackupScreenState, _frequency, initState, _isBackingUp (+13 more)

### Community 55 - "Community 55"
Cohesion: 0.11
Nodes (21): build, _buildPasswordInput, _confirmDelete, _TelegramAccountCardState, build, _loadSettings, _showPoolConfirmationDialog, build (+13 more)

### Community 56 - "Community 56"
Cohesion: 0.11
Nodes (21): ApiKeyManagementDialog, _ApiKeyManagementDialogState, build, createState, _currentKey, _generateKey, initState, InlineBotSetupDialog (+13 more)

### Community 57 - "Community 57"
Cohesion: 0.10
Nodes (20): AlignmentGeometry, alignment, build, _checkScroll, createState, didUpdateWidget, dispose, initState (+12 more)

### Community 58 - "Community 58"
Cohesion: 0.10
Nodes (20): allAccounts, channelDiscoveryServiceProvider, configChannelId, discoveryResult, discoveryService, ensureInfrastructureProvider, InfrastructureStatus, infrastructureStatusProvider (+12 more)

### Community 59 - "Community 59"
Cohesion: 0.10
Nodes (20): _buildStorageCard, child, createState, _currentIndex, _formatBytes, _isRootRoute, onDestinationSelected, _onPopInvoked (+12 more)

### Community 60 - "Community 60"
Cohesion: 0.10
Nodes (20): _archiveAndMuteChannel, configChannelId, _createTelegramFolder, ensureAccountPromotionsAndFolder, ensureInfrastructure, errorMessage, InfrastructureResult, _promoteAccountsToChannels (+12 more)

### Community 61 - "Community 61"
Cohesion: 0.10
Nodes (20): DogEarFilePainter, StarfieldPainter, build, createState, dispose, _exitApp, _GridPainter, icon (+12 more)

### Community 62 - "Community 62"
Cohesion: 0.11
Nodes (16): categories, icon, iconColor, QuickAccessCategory, title, build, StorageBanner, build (+8 more)

### Community 63 - "Community 63"
Cohesion: 0.10
Nodes (19): apiServiceProvider, chunkRepositoryProvider, downloadOrchestratorProvider, encryptionEngineProvider, service, uploadOrchestratorProvider, DownloadQueueService, UploadQueueService (+11 more)

### Community 64 - "Community 64"
Cohesion: 0.10
Nodes (18): _DesktopLayout, _MobileLayout, _TabletLayout, AeroDriveLogo, build, size, PremiumSwitch, PremiumTextField (+10 more)

### Community 65 - "Community 65"
Cohesion: 0.10
Nodes (19): _authMiddleware, container, _corsMiddleware, _fileToJson, _folderToJson, _handleCreateFolder, _handleGetFile, _handleHealth (+11 more)

### Community 66 - "Community 66"
Cohesion: 0.11
Nodes (19): build, _commentController, _copyToClipboard, createState, DebugErrorScreen, _DebugErrorScreenState, dispose, error (+11 more)

### Community 67 - "Community 67"
Cohesion: 0.11
Nodes (19): _buildExploreTab, exploreDataProvider, build, _buildFallbackGradient, _buildTagFilesView, _buildTagsGridView, createState, file (+11 more)

### Community 68 - "Community 68"
Cohesion: 0.11
Nodes (19): build, _buildContent, _codePattern, _codeSpan, _contentWidth, createState, _data, DecryptedTextViewer (+11 more)

### Community 69 - "Community 69"
Cohesion: 0.13
Nodes (19): activeChannelIdProvider, activeChannelNameProvider, activeChannelStr, build, channel, channelId, _compromisedFiles, createState (+11 more)

### Community 70 - "Community 70"
Cohesion: 0.11
Nodes (19): build, _buildCopyRow, _configService, createState, _creds, dispose, _error, initState (+11 more)

### Community 71 - "Community 71"
Cohesion: 0.12
Nodes (18): transfersStreamProvider, build, createState, _formatSize, _getTransferName, UploadQueueScreen, _UploadQueueScreenState, build (+10 more)

### Community 72 - "Community 72"
Cohesion: 0.13
Nodes (19): @DataClassName, Accounts, BackupHistory, Channels, Chunks, FaceClusters, FilePlaces, Files (+11 more)

### Community 73 - "Community 73"
Cohesion: 0.11
Nodes (18): themeProvider, AppearanceSettingsScreen, build, defaultVal, icon, isSelected, label, _ModeCard (+10 more)

### Community 74 - "Community 74"
Cohesion: 0.12
Nodes (16): ChunkRepository, _db, getChunksForFile, insertChunk, updateChunkMessageId, _uuid, _db, enqueueUpload (+8 more)

### Community 75 - "Community 75"
Cohesion: 0.19
Nodes (19): _buildAppBar, _handleCopySelected, _handleDownloadSelected, _handleMoveSelected, folderItemsCountProvider, folderSizeProvider, isSelectionModeProvider, selectedItemsProvider (+11 more)

### Community 76 - "Community 76"
Cohesion: 0.12
Nodes (18): _checkForInterruptedImports, _resumeImport, build, createState, _error, initState, _isLoading, _loadShares (+10 more)

### Community 77 - "Community 77"
Cohesion: 0.11
Nodes (18): _buildEmptyState, _buildFilterChip, _buildStatusBadge, _cancelTransfer, _clearHistory, createState, _currentFilter, db (+10 more)

### Community 78 - "Community 78"
Cohesion: 0.13
Nodes (8): Path, Queue, Args:             api_id - ID of your app (https://my.telegram.org/apps/), Since telegram.text is based on a third-party module telegram-text, you can find, BaseWorker, Base worker class.     Each worker must implement the run method to start listen, Simple one-thread worker, SimpleWorker

### Community 79 - "Community 79"
Cohesion: 0.14
Nodes (17): AeroDrive Project, app/analysis_options.yaml, app/README.md, app/scratch.txt, app/web/index.html, Boost Software License 1.0, Code Injection Planning, Flutter Framework (+9 more)

### Community 80 - "Community 80"
Cohesion: 0.11
Nodes (17): AeroDriveTheme, AeroThemePreset, _buildTextTheme, _defaultAccent, _defaultSecondary, getDark, getLight, gradient (+9 more)

### Community 81 - "Community 81"
Cohesion: 0.13
Nodes (15): AppResetHelper, showResetConfirmation, _cipher, clearCache, _getCacheThumbsDirectory, readThumbnail, saveThumbnail, ThumbnailCacheManager (+7 more)

### Community 82 - "Community 82"
Cohesion: 0.11
Nodes (17): _argon2, _argon2LowEnd, _cipher, decryptBytes, decryptDiskToStream, deriveMasterKey, deriveMasterKeyFromPhrase, encryptSingleChunkToDisk (+9 more)

### Community 83 - "Community 83"
Cohesion: 0.11
Nodes (17): _cacheLocalFilePath, _cacheRemoteFileId, _downloadAndReadRange, _handleStream, _localFilePathCache, _maxCacheSize, port, ref (+9 more)

### Community 84 - "Community 84"
Cohesion: 0.11
Nodes (17): _configChatId, dispose, _getConfigChatId, _handleDeleteMessages, _handleMessageContent, _handleNewMessage, _initializeBackgroundSyncChats, _isListening (+9 more)

### Community 85 - "Community 85"
Cohesion: 0.12
Nodes (17): build, createState, _decryptedBytes, DecryptedImageViewer, _DecryptedImageViewerState, dispose, _downloadFullChunk, _error (+9 more)

### Community 86 - "Community 86"
Cohesion: 0.12
Nodes (17): build, _clearCache, createState, DatabaseStatsDialog, _DatabaseStatsDialogState, _dbSize, _fileCount, _folderCount (+9 more)

### Community 87 - "Community 87"
Cohesion: 0.14
Nodes (17): _addTag, build, createState, file, _fileTags, fromHex, initState, _isLoading (+9 more)

### Community 88 - "Community 88"
Cohesion: 0.17
Nodes (10): AeroDriveBackupService, Context, FlutterEngine, Int, Intent, start(), stop(), IBinder (+2 more)

### Community 89 - "Community 89"
Cohesion: 0.12
Nodes (15): build, createState, dispose, _nameController, _selectedColorHex, _downloadFile, _fetchThumbnailFromTelegram, _generateAndCacheThumbnail (+7 more)

### Community 90 - "Community 90"
Cohesion: 0.12
Nodes (16): prebuilt-tdlib, aerodrive, tdlib, telegram, author, dependencies, prebuilt-tdlib, description (+8 more)

### Community 91 - "Community 91"
Cohesion: 0.12
Nodes (14): decryptStreamRange, _incrementIv, StreamingEncryptionEngine, CaptionDecryptor, CaptionSerializer, _cipher, deserialize, _encryptAndEncode (+6 more)

### Community 92 - "Community 92"
Cohesion: 0.13
Nodes (15): createFolder, _db, FolderNameTooLongException, FolderPathTooLongException, getFolderContents, getFolderPath, getSubfolders, message (+7 more)

### Community 93 - "Community 93"
Cohesion: 0.12
Nodes (15): _archiveAndMute, checkConfigStatus, _configChannelName, ConfigStatus, ConfigSyncService, _configWarningText, error, findConfigChannel (+7 more)

### Community 94 - "Community 94"
Cohesion: 0.12
Nodes (16): build, _showChannelSetupPrompt, build, _runSync, build, Route /auth, Route /diagnostics, Route /drive (+8 more)

### Community 95 - "Community 95"
Cohesion: 0.13
Nodes (15): fileIconStyleProvider, build, _buildColored, _buildFilled, _buildMinimal, _buildOutlined, color, fileName (+7 more)

### Community 96 - "Community 96"
Cohesion: 0.12
Nodes (15): admin, _cities, _convertToDecimal, country, fromJson, lat, _loadCities, lon (+7 more)

### Community 97 - "Community 97"
Cohesion: 0.12
Nodes (15): _checkStatus, _clientId, _clientSecret, connected, connectWithCode, disconnect, DropboxService, _email (+7 more)

### Community 98 - "Community 98"
Cohesion: 0.13
Nodes (14): _addLog, AppLogger, clearSavedCrashLog, error, getSavedCrashLog, hasSavedCrashLog, info, init (+6 more)

### Community 99 - "Community 99"
Cohesion: 0.21
Nodes (15): _TransferBadge, _loadThumbnail, build, _FaceGridItem, thumbnailServiceProvider, _AudioItem, _DocumentItem, _ImageItem (+7 more)

### Community 100 - "Community 100"
Cohesion: 0.14
Nodes (14): avatarFileId, DbFaceService, FaceCluster, faceClustersProvider, FaceRecognitionService, faceRecognitionServiceProvider, faceService, getClusters (+6 more)

### Community 101 - "Community 101"
Cohesion: 0.15
Nodes (14): AuthNotifier, authProvider, AuthState, _ensureInfrastructure, forceUnauthenticated, _hasBeenAuthenticated, _init, _ref (+6 more)

### Community 102 - "Community 102"
Cohesion: 0.14
Nodes (13): build, fileId, FileTagsRow, bytes, _downloadChunk, file, loadDecryptedFile, localPath (+5 more)

### Community 103 - "Community 103"
Cohesion: 0.13
Nodes (14): _breadcrumbs, build, _buildBreadcrumbs, createState, _currentFolderId, excludeFolderId, _findNestedFolderIds, FolderPickerDialog (+6 more)

### Community 104 - "Community 104"
Cohesion: 0.15
Nodes (14): build, createState, db, file, _GalleryItem, GalleryScreenContent, initState, _isLoading (+6 more)

### Community 105 - "Community 105"
Cohesion: 0.18
Nodes (15): ImageGalleryScreen, _ImageGalleryScreenState, MediaGalleryScreen, _MediaGalleryScreenState, _CodeTextViewer, _CodeTextViewerState, _PdfViewer, _PdfViewerState (+7 more)

### Community 106 - "Community 106"
Cohesion: 0.15
Nodes (14): _buildDetailRow, _controller, createState, dispose, _formatBytes, ImportLinkDialog, _ImportLinkDialogState, _resolveFolderName (+6 more)

### Community 107 - "Community 107"
Cohesion: 0.16
Nodes (13): settingsUpdateProvider, ResetSettingsDialog, _DropdownTile, _executeImport, build, ConnectionTimeoutDialog, _ConnectionTimeoutDialogState, createState (+5 more)

### Community 108 - "Community 108"
Cohesion: 0.14
Nodes (12): key, null, telegramService, userId, TelegramInitDebugInfo, build, SyncDebugOverlay, ../core/utils/reset_helper.dart (+4 more)

### Community 109 - "Community 109"
Cohesion: 0.14
Nodes (13): BackupService, _collectBackupData, dropboxBackup, ensurePublicFolders, exportBackup, _getDropboxToken, getOrCreateBackupDir, _ref (+5 more)

### Community 110 - "Community 110"
Cohesion: 0.14
Nodes (13): _createZipArchive, _db, FolderScanner, _queueSingleFile, _ref, scanAndQueueDirectory, uploadFolderManifest, _uuid (+5 more)

### Community 111 - "Community 111"
Cohesion: 0.14
Nodes (13): ChannelDiscoveryService, configChannelId, discoverInfrastructure, DiscoveryResult, errorMessage, isComplete, _ref, restoreFromDiscovery (+5 more)

### Community 112 - "Community 112"
Cohesion: 0.14
Nodes (13): chunksToDelete, completeHardDelete, deleteTelegramMessages, ExpiredMessagesPayload, fileIdsToPurge, findExpiredItems, folderIdsToPurge, PurgeJob (+5 more)

### Community 113 - "Community 113"
Cohesion: 0.14
Nodes (13): _buildMap, _captionSafetyLimit, decodeManifest, encodeFileManifest, encodeFolderManifest, encodeThumbnailManifest, _estimatedEncryptedSize, _estimateJsonLength (+5 more)

### Community 114 - "Community 114"
Cohesion: 0.14
Nodes (13): getCredentials, _keyPassword, _keyPort, _keyUsername, password, port, regenerateCredentials, setPort (+5 more)

### Community 115 - "Community 115"
Cohesion: 0.15
Nodes (13): build, createState, dispose, _error, file, folder, _hasPassword, _isLoading (+5 more)

### Community 116 - "Community 116"
Cohesion: 0.24
Nodes (6): Context, isConstraintError(), NewStore(), DB, ShareLink, Store

### Community 117 - "Community 117"
Cohesion: 0.15
Nodes (12): Animation, AnimationController, AeroDriveLogoSize, build, _controller, createState, dimension, dispose (+4 more)

### Community 118 - "Community 118"
Cohesion: 0.23
Nodes (12): AppError, AuthError, cause, CryptoError, FileOperationError, floodWaitSeconds, message, NetworkError (+4 more)

### Community 119 - "Community 119"
Cohesion: 0.15
Nodes (12): ctrIv, DecryptJobPayload, dedupFilePath, dekBytes, DownloadOrchestrator, ensureDownloadDirectory, _notifyMediaScanner, outputFilePath (+4 more)

### Community 120 - "Community 120"
Cohesion: 0.15
Nodes (12): AboutScreen, build, _buildAppHero, _buildCard, _buildDeveloperCard, _buildDivider, _buildLinkTile, _buildSignatureCredit (+4 more)

### Community 121 - "Community 121"
Cohesion: 0.17
Nodes (12): build, CompanionServerDialog, _CompanionServerDialogState, createState, initState, _isLoading, _keyController, _load (+4 more)

### Community 122 - "Community 122"
Cohesion: 0.17
Nodes (11): _, @DriftDatabase, AeroDriveDatabase, migration, _openConnection, schemaVersion, int get, MigrationStrategy get (+3 more)

### Community 123 - "Community 123"
Cohesion: 0.17
Nodes (10): EncryptionEngine, main, engine, main, tempDir, dart:math, Directory, package:aerodrive/core/utils/phone_validator.dart (+2 more)

### Community 124 - "Community 124"
Cohesion: 0.18
Nodes (11): _db, RecoveryScanner, _ref, runDisasterRecovery, telegram, _telegramService, ZeroDBRecoveryService, manifest_encoder.dart (+3 more)

### Community 125 - "Community 125"
Cohesion: 0.20
Nodes (11): build, ClearThumbnailCacheDialog, createState, initState, _load, _quality, _size, ThumbnailCacheSizeDialog (+3 more)

### Community 126 - "Community 126"
Cohesion: 0.18
Nodes (10): build, _buildAvatar, ProfileScreen, db, files, folders, _permanentlyDeleteFile, _permanentlyDeleteFolder (+2 more)

### Community 127 - "Community 127"
Cohesion: 0.24
Nodes (9): wWinMain(), string, wchar_t, CreateAndAttachConsole(), GetCommandLineArguments(), Utf8FromUtf16(), _In_, _In_opt_ (+1 more)

### Community 128 - "Community 128"
Cohesion: 0.23
Nodes (5): AuthorizationState, Login process.          Must be called before any other call.         It sends i, Verifies a telegram code and continues the authorization process          Args:, Verifies a telegram password and continues the authorization process          Ar, Finishes the new user registration process          Args:           first the us

### Community 129 - "Community 129"
Cohesion: 0.18
Nodes (10): FolderRepository, chunkRepo, db, fileRepo, folderRepo, main, package:aerodrive/data/db/database.dart, package:aerodrive/data/repositories/chunk_repository.dart (+2 more)

### Community 130 - "Community 130"
Cohesion: 0.18
Nodes (10): clearAllSettings, clearSetting, _db, getBoolSetting, getIntSetting, getSetting, setBoolSetting, setIntSetting (+2 more)

### Community 131 - "Community 131"
Cohesion: 0.18
Nodes (10): duration, generateSmartThumbnail, path, VideoThumbnailResult, VideoThumbnailService, videoThumbnailServiceProvider, Duration, package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart (+2 more)

### Community 132 - "Community 132"
Cohesion: 0.18
Nodes (10): AIQueueService, aiQueueServiceProvider, _battery, _isProcessing, _ref, triggerQueue, Battery, ml_service.dart (+2 more)

### Community 133 - "Community 133"
Cohesion: 0.20
Nodes (10): BackupFolderMapper, _BackupFolderMapperState, build, _controller, createState, dispose, initState, _isLoading (+2 more)

### Community 134 - "Community 134"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 135 - "Community 135"
Cohesion: 0.27
Nodes (3): _get_tdjson_lib_path(), Any, TDJson

### Community 136 - "Community 136"
Cohesion: 0.20
Nodes (9): clearKey, _instance, isUnlocked, _key, MasterKeyProvider, setKey, List, static final MasterKeyProvider (+1 more)

### Community 137 - "Community 137"
Cohesion: 0.20
Nodes (9): createFileEntry, _db, FileRepository, getFileByHash, getFilesInFolder, restoreFile, softDelete, trashFile (+1 more)

### Community 138 - "Community 138"
Cohesion: 0.24
Nodes (9): _showBackgroundTasksBottomSheet, aggregateTransferProgressProvider, build, db, GlobalProgressBar, select, ../core/providers.dart, package:go_router/go_router.dart (+1 more)

### Community 139 - "Community 139"
Cohesion: 0.22
Nodes (9): build, createState, initState, _isLoading, LoadBalancingScreen, _LoadBalancingScreenState, _loadSettings, _selectedStrategy (+1 more)

### Community 140 - "Community 140"
Cohesion: 0.20
Nodes (9): attachTagToFile, curatedColors, getOrCreateTag, getTagsForFile, _ref, removeTagFromFile, TagService, watchAllTags (+1 more)

### Community 141 - "Community 141"
Cohesion: 0.29
Nodes (4): Handler, Router, Request, ResponseWriter

### Community 142 - "Community 142"
Cohesion: 0.22
Nodes (8): ChannelDescriptionCodec, _cipher, decode, encode, readPurpose, ../../core/constants.dart, dart:convert, static final AesGcm

### Community 143 - "Community 143"
Cohesion: 0.39
Nodes (7): main(), generateNewConfig(), generateRandomString(), LoadOrGenerate(), safeLastN(), NewRouter(), Config

### Community 144 - "Community 144"
Cohesion: 0.25
Nodes (7): _db, _enforceLruCacheLimit, _getCacheDirectory, getThumbnail, maxCacheSizeBytes, saveThumbnail, ThumbnailCacheService

### Community 145 - "Community 145"
Cohesion: 0.43
Nodes (7): downloadQueueServiceProvider, uploadQueueServiceProvider, routerProvider, realtimeSyncServiceProvider, AeroDriveApp, _AeroDriveAppState, build

### Community 146 - "Community 146"
Cohesion: 0.29
Nodes (6): errorMessage, formattedNumber, isValid, PhoneValidationResult, PhoneValidator, validate

### Community 147 - "Community 147"
Cohesion: 0.33
Nodes (4): BootReceiver, Context, Intent, BroadcastReceiver

### Community 148 - "Community 148"
Cohesion: 0.33
Nodes (5): handle, PropfindHandler, package:shelf/shelf.dart, package:xml/xml.dart, XmlElement

### Community 149 - "Community 149"
Cohesion: 0.33
Nodes (5): db, fileTagsProvider, getTagsForFile, service, package:drift/drift.dart

### Community 150 - "Community 150"
Cohesion: 0.40
Nodes (3): FlutterEngine, MainActivity, FlutterFragmentActivity

### Community 151 - "Community 151"
Cohesion: 0.40
Nodes (5): streamingServerProvider, FullscreenVideoScreen, _FullscreenVideoScreenState, _initStream, _initStream

### Community 152 - "Community 152"
Cohesion: 0.40
Nodes (5): build, FacesScreen, _FacesScreenState, _mergeSelectedClusters, faceClustersProvider

### Community 153 - "Community 153"
Cohesion: 0.40
Nodes (3): Element, Parses text from 'HTML' and 'Markdown' (not MarkdownV2) into plain         text, Sends a message to a chat. The chat must be in the tdlib's database.         If

### Community 154 - "Community 154"
Cohesion: 0.40
Nodes (5): Caption Embedding (Zero-DB Recovery data), Manifest Versioning, RecoveryScanner, Zero-DB Recovery via Manifest Messages, Zero-DB Recovery (README)

### Community 155 - "Community 155"
Cohesion: 0.50
Nodes (4): config.json Configuration File, Docker Compose Configuration, aerodrive-server Service, links.db Database File

### Community 156 - "Community 156"
Cohesion: 0.50
Nodes (3): CreateShareRequest, rateLimiter, Mutex

### Community 157 - "Community 157"
Cohesion: 0.67
Nodes (3): @pragma, backgroundMain, callbackDispatcher

### Community 158 - "Community 158"
Cohesion: 0.67
Nodes (3): _DigestSink, _DigestSink, Sink

## Knowledge Gaps
- **1985 isolated node(s):** `message`, `cause`, `floodWaitSeconds`, `toString`, `AppConstants` (+1980 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **10 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AsyncResult` connect `Community 23` to `Community 128`, `Community 153`, `Community 74`, `Community 46`?**
  _High betweenness centrality (0.020) - this node is a cross-community bridge._
- **Why does `AeroDriveDatabase` connect `Community 122` to `Community 129`, `Community 130`, `Community 35`, `Upload Pipeline`, `Community 137`, `Community 74`, `Community 110`, `Community 16`, `Community 124`, `Community 144`, `Community 20`, `Community 92`?**
  _High betweenness centrality (0.010) - this node is a cross-community bridge._
- **Why does `_OtpInputState` connect `Community 36` to `Community 105`?**
  _High betweenness centrality (0.009) - this node is a cross-community bridge._
- **What connects `message`, `cause`, `floodWaitSeconds` to the rest of the system?**
  _1985 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Database & Schema` be split into smaller, more focused modules?**
  _Cohesion score 0.021052631578947368 - nodes in this community are weakly interconnected._
- **Should `Telegram Client Service` be split into smaller, more focused modules?**
  _Cohesion score 0.0273972602739726 - nodes in this community are weakly interconnected._
- **Should `Media UI Screens` be split into smaller, more focused modules?**
  _Cohesion score 0.03966155473294553 - nodes in this community are weakly interconnected._