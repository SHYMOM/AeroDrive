import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/repository_providers.dart';
import '../telegram/telegram_service.dart';

class TelegramApiCredentialsDialog extends ConsumerStatefulWidget {
  const TelegramApiCredentialsDialog({super.key});

  @override
  ConsumerState<TelegramApiCredentialsDialog> createState() => _TelegramApiCredentialsDialogState();
}

class _TelegramApiCredentialsDialogState extends ConsumerState<TelegramApiCredentialsDialog> {
  final _apiIdController = TextEditingController();
  final _apiHashController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _showHash = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCurrentCredentials();
  }

  @override
  void dispose() {
    _apiIdController.dispose();
    _apiHashController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentCredentials() async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final savedId = await settingsRepo.getInt('telegram_api_id');
    final savedHash = await settingsRepo.getString('telegram_api_hash');

    if (mounted) {
      setState(() {
        if (savedId != null && savedId > 0) {
          _apiIdController.text = savedId.toString();
        }
        if (savedHash != null && savedHash.isNotEmpty) {
          _apiHashController.text = savedHash;
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _pasteToController(TextEditingController controller) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      setState(() {
        controller.text = data.text!.trim();
        _error = null;
      });
    }
  }

  Future<void> _openTelegramDevPortal() async {
    final uri = Uri.parse('https://my.telegram.org');
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      debugPrint('Error launching my.telegram.org: $e');
      try {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (e2) {
        debugPrint('Fallback launch error: $e2');
        if (mounted) {
          await Clipboard.setData(const ClipboardData(text: 'https://my.telegram.org'));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open browser. Link copied to clipboard: https://my.telegram.org'),
            ),
          );
        }
      }
    }
  }

  Future<void> _saveCredentials() async {
    final rawId = _apiIdController.text.trim();
    final hash = _apiHashController.text.trim();

    if (rawId.isEmpty || hash.isEmpty) {
      setState(() => _error = 'Both API ID and API Hash are required.');
      return;
    }

    final apiId = int.tryParse(rawId);
    if (apiId == null || apiId <= 0) {
      setState(() => _error = 'API ID must be a valid positive integer.');
      return;
    }

    if (hash.length < 16) {
      setState(() => _error = 'API Hash must be a valid 32-character string.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final service = ref.read(telegramServiceProvider.notifier);
      await service.setApiCredentials(apiId, hash);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Telegram API credentials updated successfully.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to update credentials: $e';
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.key_rounded, color: cs.primary, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Telegram API Keys',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: _isLoading
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your personal API credentials connect your app directly to Telegram servers via TDLib.',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 14),

                    // Guide container
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline_rounded, size: 15, color: cs.primary),
                              const SizedBox(width: 6),
                              Text(
                                'How to get yours (Free & Instant):',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: cs.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _buildStep('1', 'Sign in at my.telegram.org with your phone.', cs),
                          _buildStep('2', 'Select "API development tools".', cs),
                          _buildStep('3', 'Create an application (e.g. AeroDrive).', cs),
                          _buildStep('4', 'Copy your api_id and api_hash below.', cs),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: _openTelegramDevPortal,
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Open my.telegram.org',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: cs.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.open_in_new_rounded, size: 12, color: cs.primary),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // API ID field
                    TextField(
                      controller: _apiIdController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'API ID (api_id)',
                        hintText: 'e.g. 12345678',
                        prefixIcon: const Icon(Icons.tag_rounded, size: 18),
                        suffixIcon: IconButton(
                          tooltip: 'Paste',
                          icon: const Icon(Icons.content_paste_rounded, size: 18),
                          onPressed: () => _pasteToController(_apiIdController),
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // API Hash field
                    TextField(
                      controller: _apiHashController,
                      obscureText: !_showHash,
                      decoration: InputDecoration(
                        labelText: 'API Hash (api_hash)',
                        hintText: '32-character hex hash',
                        prefixIcon: const Icon(Icons.password_rounded, size: 18),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: _showHash ? 'Hide' : 'Show',
                              icon: Icon(_showHash ? Icons.visibility : Icons.visibility_off, size: 18),
                              onPressed: () => setState(() => _showHash = !_showHash),
                            ),
                            IconButton(
                              tooltip: 'Paste',
                              icon: const Icon(Icons.content_paste_rounded, size: 18),
                              onPressed: () => _pasteToController(_apiHashController),
                            ),
                          ],
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: TextStyle(color: cs.error, fontSize: 12),
                      ),
                    ],

                    const SizedBox(height: 12),
                    Text(
                      'Note: Updating credentials will reinitialize the Telegram client.',
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_isLoading || _isSaving) ? null : _saveCredentials,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildStep(String num, String text, ColorScheme cs) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 15,
              height: 15,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Text(
                num,
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: cs.primary),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
}
