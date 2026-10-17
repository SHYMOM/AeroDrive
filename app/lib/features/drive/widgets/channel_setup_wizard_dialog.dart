import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/logger.dart';
import '../../../core/providers/infrastructure_providers.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/providers/security_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/infrastructure/infrastructure_provisioning_service.dart';
import '../../telegram/telegram_manager.dart';
import '../../telegram/telegram_service.dart';

/// Modal dialog that prompts the user to set up the minimum required 4 channels
/// for AeroDrive:
/// 1. AeroDrive Storage 1
/// 2. AeroDrive Storage 2
/// 3. AeroDrive Config
/// 4. AeroDrive Shared
///
/// Features:
/// - Explicit warnings not to add any person to the channels and not to remove descriptions.
/// - Option to auto-create all 4 channels with live progress.
/// - Option to pick and configure 4 existing channels (renames them, updates photos, and writes descriptions).
class ChannelSetupWizardDialog extends ConsumerStatefulWidget {
  const ChannelSetupWizardDialog({
    super.key,
    this.onSetupCompleted,
  });

  final VoidCallback? onSetupCompleted;

  static Future<bool?> show(BuildContext context, {VoidCallback? onSetupCompleted}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: ChannelSetupWizardDialog(onSetupCompleted: onSetupCompleted),
      ),
    );
  }

  @override
  ConsumerState<ChannelSetupWizardDialog> createState() => _ChannelSetupWizardDialogState();
}

class _ChannelSetupWizardDialogState extends ConsumerState<ChannelSetupWizardDialog> {
  bool _isProcessing = false;
  String _statusMessage = '';
  double _progress = 0.0;
  String? _errorMessage;

  bool _isSelectingExisting = false;
  bool _isLoadingChannels = false;
  List<Map<String, dynamic>> _adminChannels = [];

  int? _selectedStorage1;
  int? _selectedStorage2;
  int? _selectedConfig;
  int? _selectedShared;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _loadAdminChannels() async {
    setState(() {
      _isLoadingChannels = true;
      _errorMessage = null;
    });

    try {
      final accounts = ref.read(telegramManagerProvider);
      final primary = accounts.firstWhere(
        (c) => c.authState == TelegramAuthState.ready,
        orElse: () => accounts.first,
      );
      final channels = await primary.getAdminChannels();
      if (mounted) {
        setState(() {
          _adminChannels = channels;
          _isLoadingChannels = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load Telegram channels: $e';
          _isLoadingChannels = false;
        });
      }
    }
  }

  Future<void> _handleAutoCreate() async {
    final accounts = ref.read(telegramManagerProvider);
    final primary = accounts.firstWhere(
      (c) => c.authState == TelegramAuthState.ready,
      orElse: () => accounts.first,
    );
    final allAccounts = accounts.where((c) => c.authState == TelegramAuthState.ready).toList();

    final masterKeyBytes = ref.read(masterKeyProvider);
    if (masterKeyBytes == null) {
      setState(() => _errorMessage = 'Vault is locked. Please unlock before setup.');
      return;
    }

    final settingsRepo = ref.read(settingsRepositoryProvider);
    final keySalt = await settingsRepo.getSetting('master_password_salt') ?? 'AeroDrive_Salt_2026';
    final masterKey = SecretKey(masterKeyBytes);

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _progress = 0.05;
      _statusMessage = 'Initializing infrastructure...';
    });

    final provisioning = ref.read(infrastructureProvisioningServiceProvider);
    final result = await provisioning.provisionInitialInfrastructure(
      telegramService: primary,
      masterKey: masterKey,
      masterKeySalt: keySalt,
      allAccounts: allAccounts,
      onProgress: (msg, frac) {
        if (mounted) {
          setState(() {
            _statusMessage = msg;
            _progress = frac;
          });
        }
      },
    );

    if (result.success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All 4 AeroDrive channels created and configured successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        widget.onSetupCompleted?.call();
        Navigator.of(context).pop(true);
      }
    } else {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = result.errorMessage ?? 'Channel creation failed. Please retry.';
        });
      }
    }
  }

  Future<void> _handleConfirmExisting() async {
    if (_selectedStorage1 == null ||
        _selectedStorage2 == null ||
        _selectedConfig == null ||
        _selectedShared == null) {
      setState(() => _errorMessage = 'Please assign all 4 channels to proceed.');
      return;
    }

    final selectedSet = {
      _selectedStorage1!,
      _selectedStorage2!,
      _selectedConfig!,
      _selectedShared!,
    };
    if (selectedSet.length != 4) {
      setState(() => _errorMessage = 'Each role must be assigned to a distinct Telegram channel.');
      return;
    }

    final accounts = ref.read(telegramManagerProvider);
    final primary = accounts.firstWhere(
      (c) => c.authState == TelegramAuthState.ready,
      orElse: () => accounts.first,
    );
    final allAccounts = accounts.where((c) => c.authState == TelegramAuthState.ready).toList();

    final masterKeyBytes = ref.read(masterKeyProvider);
    if (masterKeyBytes == null) {
      setState(() => _errorMessage = 'Vault is locked. Please unlock before setup.');
      return;
    }

    final settingsRepo = ref.read(settingsRepositoryProvider);
    final keySalt = await settingsRepo.getSetting('master_password_salt') ?? 'AeroDrive_Salt_2026';
    final masterKey = SecretKey(masterKeyBytes);

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _progress = 0.05;
      _statusMessage = 'Binding existing channels...';
    });

    final provisioning = ref.read(infrastructureProvisioningServiceProvider);
    final result = await provisioning.configureExistingChannelsAsInfrastructure(
      telegramService: primary,
      storageChannel1Id: _selectedStorage1!,
      storageChannel2Id: _selectedStorage2!,
      configChannelId: _selectedConfig!,
      sharedChannelId: _selectedShared!,
      masterKey: masterKey,
      masterKeySalt: keySalt,
      allAccounts: allAccounts,
      onProgress: (msg, frac) {
        if (mounted) {
          setState(() {
            _statusMessage = msg;
            _progress = frac;
          });
        }
      },
    );

    if (result.success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Channels successfully linked, renamed, and configured for AeroDrive!'),
            backgroundColor: AppColors.success,
          ),
        );
        widget.onSetupCompleted?.call();
        Navigator.of(context).pop(true);
      }
    } else {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = result.errorMessage ?? 'Failed to configure existing channels.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: _isProcessing ? _buildProgressView() : (_isSelectingExisting ? _buildExistingSelectionView() : _buildOverviewView()),
        ),
      ),
    );
  }

  Widget _buildProgressView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 32),
        const SizedBox(
          width: 60,
          height: 60,
          child: CircularProgressIndicator(strokeWidth: 4),
        ),
        const SizedBox(height: 32),
        Text(
          'Setting Up AeroDrive Infrastructure',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.onSurface,
                fontWeight: FontWeight.bold,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          _statusMessage,
          style: TextStyle(color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.w500),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        LinearProgressIndicator(
          value: _progress > 0 ? _progress : null,
          backgroundColor: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          minHeight: 8,
        ),
        const SizedBox(height: 12),
        Text(
          '${(_progress * 100).toInt()}% completed',
          style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.onSurfaceVariant, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Renaming channels, applying AeroDrive icons, encrypting descriptions, and syncing vault...',
                  style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildOverviewView() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.cloud_sync, color: AppColors.primary, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome to AeroDrive',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AppColors.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Initial Infrastructure Setup',
                      style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'To enable decentralized zero-knowledge storage, AeroDrive requires 4 dedicated Telegram channels on your account:',
            style: TextStyle(color: AppColors.onSurface, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),

          // 4 Channels breakdown
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.outline.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                _buildChannelItem(
                  icon: Icons.inventory_2_outlined,
                  name: 'AeroDrive Storage 1',
                  desc: 'Primary encrypted file payload storage',
                  tag: 'REQUIRED',
                ),
                const Divider(height: 16, color: Colors.white12),
                _buildChannelItem(
                  icon: Icons.inventory_2_outlined,
                  name: 'AeroDrive Storage 2',
                  desc: 'Load-balanced redundant storage (multi-channel)',
                  tag: 'REQUIRED',
                ),
                const Divider(height: 16, color: Colors.white12),
                _buildChannelItem(
                  icon: Icons.settings_suggest_outlined,
                  name: 'AeroDrive Config',
                  desc: 'Encrypted device sync & master registry',
                  tag: 'REQUIRED',
                ),
                const Divider(height: 16, color: Colors.white12),
                _buildChannelItem(
                  icon: Icons.share_outlined,
                  name: 'AeroDrive Shared',
                  desc: 'Public and password-protected share link relay',
                  tag: 'REQUIRED',
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '💡 You can add more storage channels anytime later in Settings.',
            style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 16),

          // CRITICAL WARNING NOTICE BOX
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 22),
                    SizedBox(width: 8),
                    Text(
                      'CRITICAL PRIVACY & SECURITY RULES',
                      style: TextStyle(
                        color: Color(0xFFF59E0B),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildRuleItem('1. Do NOT add any person or bot to these channels.',
                    'These channels are strictly for your private encrypted cloud storage. Adding members exposes raw data.'),
                const SizedBox(height: 6),
                _buildRuleItem('2. Do NOT edit, delete, or remove the descriptions of these channels.',
                    'Channel descriptions store cryptographic discovery tokens required for multi-device sync and disaster recovery.'),
                const SizedBox(height: 6),
                _buildRuleItem('3. Channels will be renamed and given the AeroDrive app icon automatically.',
                    'Titles and channel photos are branded so TDLib easily recognizes your drive infrastructure.'),
              ],
            ),
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.error),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Action buttons
          FilledButton.icon(
            onPressed: _handleAutoCreate,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Auto-Create All 4 Channels (Recommended)'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () {
              setState(() => _isSelectingExisting = true);
              _loadAdminChannels();
            },
            icon: const Icon(Icons.link),
            label: const Text('Link Existing Telegram Channels'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              foregroundColor: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Remind Me Later', style: TextStyle(color: AppColors.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  Widget _buildExistingSelectionView() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _isSelectingExisting = false),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Link 4 Existing Channels',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AppColors.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      'Designate 4 existing Telegram channels where you are an admin.',
                      style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '⚠️ Note: AeroDrive will rename each chosen channel to its standard name ("AeroDrive Storage 1", etc.) and set its profile photo to the AeroDrive app logo.',
            style: TextStyle(color: const Color(0xFFF59E0B), fontSize: 12, height: 1.3),
          ),
          const SizedBox(height: 16),

          if (_isLoadingChannels)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_adminChannels.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Text(
                'No admin channels found on your Telegram account. Please choose "Auto-Create" to create them automatically.',
                style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            )
          else ...[
            _buildChannelDropdown(
              label: '1. Storage Channel 1 (Primary Payload)',
              value: _selectedStorage1,
              onChanged: (id) => setState(() => _selectedStorage1 = id),
            ),
            const SizedBox(height: 12),
            _buildChannelDropdown(
              label: '2. Storage Channel 2 (Redundant Storage)',
              value: _selectedStorage2,
              onChanged: (id) => setState(() => _selectedStorage2 = id),
            ),
            const SizedBox(height: 12),
            _buildChannelDropdown(
              label: '3. Config Channel (Sync & Registry)',
              value: _selectedConfig,
              onChanged: (id) => setState(() => _selectedConfig = id),
            ),
            const SizedBox(height: 12),
            _buildChannelDropdown(
              label: '4. Shared Channel (Share Link Relay)',
              value: _selectedShared,
              onChanged: (id) => setState(() => _selectedShared = id),
            ),
          ],

          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: const TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ],

          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _adminChannels.isNotEmpty ? _handleConfirmExisting : null,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Confirm & Configure 4 Channels'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _isSelectingExisting = false),
            child: Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelItem({
    required IconData icon,
    required String name,
    required String desc,
    required String tag,
  }) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              Text(
                desc,
                style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 11),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            tag,
            style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildRuleItem(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          ),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelDropdown({
    required String label,
    required int? value,
    required ValueChanged<int?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.outline.withValues(alpha: 0.3)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: value,
              isExpanded: true,
              dropdownColor: AppColors.surfaceElevated,
              hint: Text('Select a Telegram channel', style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13)),
              items: _adminChannels.map((c) {
                final id = c['id'] as int;
                final title = c['title'] as String? ?? 'Channel $id';
                return DropdownMenuItem<int>(
                  value: id,
                  child: Text(title, style: TextStyle(color: AppColors.onSurface, fontSize: 13)),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
