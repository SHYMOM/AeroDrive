import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/windows_network_drive_service.dart';
import '../../core/utils/windows_startup_service.dart';
import '../../core/utils/tray_service.dart';
import '../../domain/webdav/webdav_config.dart';
import '../../domain/webdav/webdav_server.dart';

class WebDavSettingsDialog extends ConsumerStatefulWidget {
  const WebDavSettingsDialog({super.key});

  @override
  ConsumerState<WebDavSettingsDialog> createState() => _WebDavSettingsDialogState();
}

class _WebDavSettingsDialogState extends ConsumerState<WebDavSettingsDialog> {
  final WebDavConfigService _configService = WebDavConfigService();
  WebDavCredentials? _creds;
  bool _isRunning = false;
  bool _isLoading = true;
  String? _error;

  // Platform states
  bool _isWindows = false;
  bool _isLinux = false;
  bool _isMacOS = false;
  bool _startupEnabled = false;
  bool _isFileSizeLimit4GB = true;
  String? _mountedDriveLetter;
  bool _isMountingDrive = false;
  bool _isFixingLimit = false;
  List<String> _availableLetters = ['Z:', 'Y:', 'X:', 'W:', 'V:'];
  String _selectedDriveLetter = 'Z:';

  late TextEditingController _portController;

  @override
  void initState() {
    super.initState();
    _portController = TextEditingController();
    _isWindows = !kIsWeb && Platform.isWindows;
    _isLinux = !kIsWeb && Platform.isLinux;
    _isMacOS = !kIsWeb && Platform.isMacOS;
    _isRunning = WebDavServer.isRunning;
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final creds = await _configService.getCredentials();
    bool startup = false;
    bool limit4GB = true;
    String? drive;

    if (_isWindows) {
      startup = await WindowsStartupService.isStartupEnabled();
      limit4GB = await WindowsNetworkDriveService.isFileSizeLimit4GB();
      if (_isRunning) {
        drive = await WindowsNetworkDriveService.getMountedDrive(creds.port);
      }
      final available = await WindowsNetworkDriveService.getAvailableDriveLetters();
      if (mounted) {
        setState(() {
          _availableLetters = available;
          if (!available.contains(_selectedDriveLetter) && available.isNotEmpty) {
            _selectedDriveLetter = available.first;
          }
        });
      }
    }

    setState(() {
      _creds = creds;
      _portController.text = creds.port.toString();
      _startupEnabled = startup;
      _isFileSizeLimit4GB = limit4GB;
      _mountedDriveLetter = drive;
      _isLoading = false;
    });
  }

  Future<void> _regenerate() async {
    setState(() => _isLoading = true);
    if (_isRunning) _stopServer();

    final newCreds = await _configService.regenerateCredentials();
    setState(() {
      _creds = newCreds;
      _isLoading = false;
    });
  }

  Future<void> _promptWindowsStartupIfNeeded() async {
    if (!_isWindows) return;
    final isAlreadyStartup = await WindowsStartupService.isStartupEnabled();
    if (isAlreadyStartup || !mounted) return;

    final shouldEnable = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.power_settings_new, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('Auto-Start & Background'),
          ],
        ),
        content: const Text(
          'To ensure your WebDAV network drive stays connected and reconnects '
          'automatically whenever you start your PC, AeroDrive can run in the '
          'background and launch at Windows startup.\n\n'
          'This works with both portable and installed builds.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Skip'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('Enable Startup & Background'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (shouldEnable == true) {
      await WindowsStartupService.setStartupEnabled(true, background: true);
      setState(() => _startupEnabled = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AeroDrive registered for Windows startup & background operation.')),
        );
      }
    }
  }

  Future<void> _toggleServer(bool start) async {
    setState(() {
      _error = null;
      _isLoading = true;
    });

    try {
      if (start) {
        // Save new port if changed
        final newPort = int.tryParse(_portController.text) ?? WebDavConfigService.defaultPort;
        if (newPort != _creds!.port) {
          await _configService.setPort(newPort);
          _creds = await _configService.getCredentials();
        }

        // Prompt Windows user for background & startup
        if (_isWindows) {
          await _promptWindowsStartupIfNeeded();
        }

        await _configService.setServerAutoStartEnabled(true);
        await WebDavServer.start(widgetRef: ref, creds: _creds!);

        String? drive;
        if (_isWindows) {
          drive = await WindowsNetworkDriveService.getMountedDrive(_creds!.port);
          await TrayService.instance.updateContextMenu();
        }

        if (!mounted) return;
        setState(() {
          _isRunning = true;
          _mountedDriveLetter = drive;
        });
      } else {
        await _configService.setServerAutoStartEnabled(false);
        _stopServer();
        if (_isWindows) {
          await TrayService.instance.updateContextMenu();
        }
      }
    } on SocketException catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "Port ${_portController.text} is already in use. Please select a different port.";
        _isRunning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Failed to start server: $e";
        _isRunning = false;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _stopServer() {
    WebDavServer.stop();
    if (!mounted) return;
    setState(() {
      _isRunning = false;
    });
  }

  Future<void> _mountWindowsDrive() async {
    if (_creds == null) return;
    setState(() => _isMountingDrive = true);
    try {
      final driveLetter = await WindowsNetworkDriveService.mountDrive(_creds!.port, preferredLetter: _selectedDriveLetter);
      await TrayService.instance.updateContextMenu();
      if (!mounted) return;
      setState(() {
        _mountedDriveLetter = driveLetter;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade800,
          content: Text('Mounted as $driveLetter in File Explorer!'),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: Text('Failed to mount drive: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isMountingDrive = false);
      }
    }
  }

  Future<void> _mountLinuxDrive() async {
    if (_creds == null) return;
    setState(() => _isMountingDrive = true);
    try {
      await WindowsNetworkDriveService.mountLinux(_creds!.port);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text('Launched GIO / File Manager mount for AeroDrive!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Mount error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isMountingDrive = false);
    }
  }

  Future<void> _mountMacOSDrive() async {
    if (_creds == null) return;
    setState(() => _isMountingDrive = true);
    try {
      await WindowsNetworkDriveService.mountMacOS(_creds!.port);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text('Opening Finder Connect to Server...'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Mount error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isMountingDrive = false);
    }
  }

  Future<void> _unmountWindowsDrive() async {
    if (_mountedDriveLetter == null) return;
    setState(() => _isMountingDrive = true);
    try {
      final ok = await WindowsNetworkDriveService.unmountDrive(_mountedDriveLetter!);
      await TrayService.instance.updateContextMenu();
      if (!mounted) return;
      if (ok) {
        setState(() => _mountedDriveLetter = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Drive successfully unmounted.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isMountingDrive = false);
      }
    }
  }

  @override
  void dispose() {
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.folder_shared, color: Colors.blueAccent),
            const SizedBox(width: 8),
            const Text('WebDAV Network Drive'),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _isRunning ? Colors.green.withAlpha(40) : Colors.grey.withAlpha(40),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isRunning ? Colors.green : Colors.grey,
                  width: 1,
                ),
              ),
              child: Text(
                _isRunning ? 'RUNNING' : 'STOPPED',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _isRunning ? Colors.green : Colors.grey,
                ),
              ),
            ),
          ],
        ),
        content: _isLoading
            ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
            : SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Mount your encrypted AeroDrive storage directly as a native Windows drive letter (Z:) '
                        'or network folder in Windows Explorer and macOS Finder.',
                        style: TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                      const SizedBox(height: 16),

                      // Server Switch Tile
                      Card(
                        elevation: 0,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(80),
                        child: SwitchListTile(
                          title: const Text('Enable WebDAV Server', style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            _isRunning
                                ? 'Listening on port ${_creds?.port}'
                                : 'Server is stopped',
                            style: const TextStyle(fontSize: 12),
                          ),
                          value: _isRunning,
                          onChanged: _toggleServer,
                        ),
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                      ],

                      // Windows Native 1-Click Mount Section
                      if (_isWindows && _isRunning) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent.withAlpha(25),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blueAccent.withAlpha(80)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.computer, size: 20, color: Colors.blueAccent),
                                  const SizedBox(width: 8),
                                  const Text('Windows File Explorer Mount', style: TextStyle(fontWeight: FontWeight.bold)),
                                  const Spacer(),
                                  if (_mountedDriveLetter != null)
                                    Chip(
                                      visualDensity: VisualDensity.compact,
                                      avatar: const Icon(Icons.check_circle, size: 16, color: Colors.greenAccent),
                                      label: Text('Drive $_mountedDriveLetter', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (_mountedDriveLetter == null) ...[
                                const Text(
                                  'Mount AeroDrive as an actual drive letter in Windows File Explorer with a single click.',
                                  style: TextStyle(fontSize: 12, color: Colors.white70),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.surface,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                                      ),
                                      child: DropdownButton<String>(
                                        value: _selectedDriveLetter,
                                        underline: const SizedBox(),
                                        isDense: true,
                                        items: _availableLetters.map((letter) => DropdownMenuItem(
                                          value: letter,
                                          child: Text('Drive $letter', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                        )).toList(),
                                        onChanged: (val) {
                                          if (val != null) {
                                            setState(() => _selectedDriveLetter = val);
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: FilledButton.icon(
                                        icon: _isMountingDrive
                                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                            : const Icon(Icons.drive_file_move),
                                        label: Text('Mount as Windows Drive ($_selectedDriveLetter)'),
                                        onPressed: _isMountingDrive ? null : _mountWindowsDrive,
                                      ),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        icon: const Icon(Icons.folder_open),
                                        label: const Text('Open in Explorer'),
                                        onPressed: () {
                                          Process.run('explorer.exe', [_mountedDriveLetter!]);
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        icon: const Icon(Icons.eject, color: Colors.redAccent),
                                        label: const Text('Unmount', style: TextStyle(color: Colors.redAccent)),
                                        onPressed: _isMountingDrive ? null : _unmountWindowsDrive,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Windows 50MB Registry Limit Warning & 1-Click Fix
                        if (!_isFileSizeLimit4GB) ...[
                          Container(
                            margin: const EdgeInsets.only(top: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.amber.withAlpha(25),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber.withAlpha(120)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded, size: 20, color: Colors.amber),
                                    SizedBox(width: 8),
                                    Text('Windows 50MB Limit Detected', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Windows limits WebDAV transfers to 50MB by default. Files larger than 50MB (like videos) fail with error 0x800700DF.',
                                  style: TextStyle(fontSize: 12, color: Colors.white70),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    icon: _isFixingLimit
                                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber))
                                        : const Icon(Icons.flash_on, color: Colors.amber),
                                    label: Text(
                                      _isFixingLimit ? 'Requesting UAC Permission...' : 'Increase Limit to 4GB (Fix 0x800700DF)',
                                      style: const TextStyle(color: Colors.amber),
                                    ),
                                    onPressed: _isFixingLimit
                                        ? null
                                        : () async {
                                            setState(() => _isFixingLimit = true);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('Please accept the Windows UAC elevation prompt...'),
                                                duration: Duration(seconds: 4),
                                              ),
                                            );
                                            try {
                                              final success = await WindowsNetworkDriveService.fixFileSizeLimit();
                                              if (mounted) {
                                                setState(() => _isFileSizeLimit4GB = success);
                                                if (success) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(
                                                      backgroundColor: Colors.green,
                                                      content: Text('Windows WebClient limit successfully increased to 4 GB!'),
                                                    ),
                                                  );
                                                } else {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(
                                                      backgroundColor: Colors.redAccent,
                                                      content: Text('Registry update did not take effect. Please run fix_webdav_file_size_limit.bat as Admin.'),
                                                    ),
                                                  );
                                                }
                                              }
                                            } catch (e) {
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    backgroundColor: Colors.redAccent,
                                                    content: Text('Failed to elevate UAC: $e'),
                                                  ),
                                                );
                                              }
                                            } finally {
                                              if (mounted) setState(() => _isFixingLimit = false);
                                            }
                                          },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Native Windows 4GB Limitation & >4GB Client Guide
                        Container(
                          margin: const EdgeInsets.only(top: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(60),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.info_outline, size: 18, color: Theme.of(context).colorScheme.primary),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Native Windows 4 GB Limit Notice',
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'The native Windows WebDAV client (WebClient / mapped drive via File Explorer) has a hard 32-bit architectural cap of 4 GB (2³² - 1 bytes). '
                                'If you need to transfer files larger than 4 GB over WebDAV (such as large 4K movies or full disk images), the native Windows Explorer WebDAV client will fail regardless of registry settings.\n\n'
                                'For files >4 GB, use a dedicated client that mounts WebDAV via WinFsp / Dokan:\n'
                                '• Rclone (via rclone mount)\n'
                                '• Cyberduck / Mountain Duck\n'
                                '• WinSCP',
                                style: TextStyle(fontSize: 11.5, color: Colors.white70, height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Linux Native Mount Section
                      if (_isLinux && _isRunning) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.deepOrangeAccent.withAlpha(25),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.deepOrangeAccent.withAlpha(80)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.desktop_windows_outlined, size: 20, color: Colors.deepOrangeAccent),
                                  SizedBox(width: 8),
                                  Text('Linux Desktop Mount (GVFS / GIO)', style: TextStyle(fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Mount directly into Nautilus / Dolphin / Thunar via native GNOME/KDE WebDAV integration.',
                                style: TextStyle(fontSize: 12, color: Colors.white70),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  icon: _isMountingDrive
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.folder_shared_rounded),
                                  label: const Text('Mount in File Manager (GIO)'),
                                  onPressed: _isMountingDrive ? null : _mountLinuxDrive,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // macOS Native Mount Section
                      if (_isMacOS && _isRunning) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.cyanAccent.withAlpha(25),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.cyanAccent.withAlpha(80)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.apple_rounded, size: 20, color: Colors.cyanAccent),
                                  SizedBox(width: 8),
                                  Text('macOS Finder Mount', style: TextStyle(fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Connect directly via native macOS WebDAV client in Finder.',
                                style: TextStyle(fontSize: 12, color: Colors.white70),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  icon: _isMountingDrive
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.folder_open_rounded),
                                  label: const Text('Connect to Finder (cmd+K)'),
                                  onPressed: _isMountingDrive ? null : _mountMacOSDrive,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Windows Auto-Startup & Background Option
                      if (_isWindows) ...[
                        const SizedBox(height: 12),
                        SwitchListTile(
                          dense: true,
                          title: const Text('Run in Background & Windows Startup'),
                          subtitle: const Text(
                            'Keeps network drive connected automatically across restarts (supports portable builds).',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: _startupEnabled,
                          onChanged: (val) async {
                            final success = await WindowsStartupService.setStartupEnabled(val, background: true);
                            if (success) {
                              setState(() => _startupEnabled = val);
                            }
                          },
                        ),
                      ],

                      const Divider(height: 24),

                      // Require Authentication Toggle
                      SwitchListTile(
                        dense: true,
                        title: const Text('Require Password Authentication'),
                        subtitle: const Text(
                          'Recommended: OFF for seamless localhost mounting in Windows File Explorer.',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _creds?.requireAuth ?? false,
                        onChanged: _isRunning
                            ? null
                            : (val) async {
                                await _configService.setRequireAuth(val);
                                final updated = await _configService.getCredentials();
                                setState(() => _creds = updated);
                              },
                      ),

                      if (_creds?.requireAuth == true) ...[
                        const SizedBox(height: 8),
                        _buildCopyRow('Username', _creds?.username ?? ''),
                        const SizedBox(height: 4),
                        _buildCopyRow('Password', _creds?.password ?? ''),
                      ],

                      const SizedBox(height: 12),

                      // Connection details
                      const Text('Connection URLs & Commands:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      _buildCopyRow('Mount URL', 'http://127.0.0.1:${_creds?.port}/'),
                      const SizedBox(height: 4),
                      _buildCopyRow('UNC Path', r'\\127.0.0.1@' '${_creds?.port}' r'\DavWWWRoot'),
                      const SizedBox(height: 4),
                      _buildCopyRow('CMD Mount', 'net use * http://127.0.0.1:${_creds?.port}/'),

                      const SizedBox(height: 16),
                      TextField(
                        controller: _portController,
                        decoration: const InputDecoration(
                          labelText: 'WebDAV Port (Default: 49188)',
                          helperText: 'Uncommon high port avoids conflicts with dev tools',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                        enabled: !_isRunning,
                      ),

                      // Live Activity & Diagnostics Bar
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(90),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _isRunning 
                                ? Colors.greenAccent.withAlpha(80) 
                                : Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isRunning ? Colors.greenAccent : Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isRunning
                                        ? '127.0.0.1:${_creds?.port ?? 49188} — Localhost Isolated 🔒'
                                        : 'Server Stopped',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                  ),
                                  Text(
                                    _isRunning
                                        ? 'Strict loopback binding. Inaccessible from external LAN.'
                                        : 'Not listening for filesystem or WebDAV requests.',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _isRunning 
                                    ? Colors.green.withAlpha(40) 
                                    : Colors.grey.withAlpha(40),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _isRunning ? 'ACTIVE' : 'OFFLINE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _isRunning ? Colors.greenAccent : Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        actions: [
          if (!_isLoading)
            TextButton(
              onPressed: _isRunning ? null : _regenerate,
              child: const Text('Regenerate Credentials'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );

  Widget _buildCopyRow(String label, String value) => Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(50),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 85,
              child: Text(
                '$label:',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.white70),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 16),
              tooltip: 'Copy $label',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    duration: const Duration(seconds: 2),
                    content: Text('$label copied to clipboard'),
                  ),
                );
              },
            ),
          ],
        ),
      );
}
