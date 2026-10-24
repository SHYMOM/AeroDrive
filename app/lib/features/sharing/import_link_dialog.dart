import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../drive/providers/drive_providers.dart';
import '../drive/widgets/folder_picker_dialog.dart';
import 'share_service.dart';

enum _ImportStep {
  input,
  passwordPrompt,
  fetchingMetadata,
  confirm,
  importing,
  error,
}

class ImportLinkDialog extends ConsumerStatefulWidget {
  const ImportLinkDialog({super.key, this.initialUrl});
  final String? initialUrl;

  @override
  ConsumerState<ImportLinkDialog> createState() => _ImportLinkDialogState();
}

class _ImportLinkDialogState extends ConsumerState<ImportLinkDialog> {
  final _urlController = TextEditingController();
  final _passwordController = TextEditingController();

  _ImportStep _currentStep = _ImportStep.input;
  String? _targetFolderId;
  String _targetFolderName = 'My Drive';
  String? _errorMessage;

  int _totalSize = 0;
  double _speedBytesPerSec = 0.0;
  Completer<bool>? _confirmCompleter;
  bool _isCancelled = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null && widget.initialUrl!.isNotEmpty) {
      _urlController.text = widget.initialUrl!;
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _passwordController.dispose();
    if (_confirmCompleter != null && !_confirmCompleter!.isCompleted) {
      _confirmCompleter!.complete(false);
    }
    super.dispose();
  }

  Future<void> _resolveFolderName(String folderId) async {
    final db = ref.read(databaseProvider);
    final folder = await (db.select(db.folders)..where((f) => f.id.equals(folderId))).getSingleOrNull();
    if (folder != null && mounted) {
      setState(() {
        _targetFolderName = folder.name;
      });
    }
  }

  Future<void> _startImportFlow() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    final uri = Uri.tryParse(url);
    if (uri == null || (!url.startsWith('aerodrive://share') && uri.scheme != 'aerodrive')) {
      setState(() {
        _errorMessage = 'Invalid link format. Please provide a valid aerodrive://share link.';
        _currentStep = _ImportStep.error;
      });
      return;
    }

    final hasPassword = uri.queryParameters['hasPassword'] == '1';
    if (hasPassword && _passwordController.text.trim().isEmpty) {
      setState(() {
        _currentStep = _ImportStep.passwordPrompt;
      });
      return;
    }

    await _executeImport(url);
  }

  Future<void> _executeImport(String url) async {
    setState(() {
      _currentStep = _ImportStep.fetchingMetadata;
      _errorMessage = null;
      _isCancelled = false;
    });

    final password = _passwordController.text.trim().isNotEmpty ? _passwordController.text.trim() : null;

    try {
      await ref.read(shareServiceProvider).importShareLink(
        url,
        password: password,
        targetFolderId: _targetFolderId,
        onConfirm: (totalSize, speedBytesPerSec) async {
          if (_isCancelled || !mounted) return false;

          _confirmCompleter = Completer<bool>();
          setState(() {
            _totalSize = totalSize;
            _speedBytesPerSec = speedBytesPerSec;
            _currentStep = _ImportStep.confirm;
          });

          final confirmed = await _confirmCompleter!.future;
          if (confirmed && mounted) {
            setState(() {
              _currentStep = _ImportStep.importing;
            });
          }
          return confirmed;
        },
      );

      if (mounted) {
        Navigator.of(context).pop();
        ref.invalidate(folderContentsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Successfully imported shared items to your drive.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted && !_isCancelled) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _currentStep = _ImportStep.error;
        });
      }
    }
  }

  void _onProceedConfirmed() {
    if (_confirmCompleter != null && !_confirmCompleter!.isCompleted) {
      _confirmCompleter!.complete(true);
    }
  }

  void _onCancelImport() {
    _isCancelled = true;
    if (_confirmCompleter != null && !_confirmCompleter!.isCompleted) {
      _confirmCompleter!.complete(false);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: _buildTitle(),
      content: _buildContent(),
      actions: _buildActions(),
    );
  }

  Widget _buildTitle() {
    switch (_currentStep) {
      case _ImportStep.input:
        return Text('Import Shared Link', style: TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.bold));
      case _ImportStep.passwordPrompt:
        return const Row(
          children: [
            Icon(Icons.lock_outline, color: Colors.amberAccent, size: 22),
            SizedBox(width: 8),
            Text('Password Protected', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        );
      case _ImportStep.fetchingMetadata:
        return const Text('Fetching Metadata', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold));
      case _ImportStep.confirm:
        return const Text('Confirm Import', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold));
      case _ImportStep.importing:
        return const Text('Importing Data', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold));
      case _ImportStep.error:
        return const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.redAccent, size: 22),
            SizedBox(width: 8),
            Text('Import Failed', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ],
        );
    }
  }

  Widget _buildContent() {
    switch (_currentStep) {
      case _ImportStep.input:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _urlController,
              style: TextStyle(color: AppColors.onSurface),
              decoration: InputDecoration(
                hintText: 'aerodrive://share?...',
                hintStyle: TextStyle(color: AppColors.onSurfaceVariant),
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Import to:',
                  style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13),
                ),
                TextButton.icon(
                  icon: Icon(Icons.folder_open, size: 16, color: AppColors.primary),
                  label: Text(
                    _targetFolderName,
                    style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () async {
                    final pickedId = await showDialog<String>(
                      context: context,
                      builder: (ctx) => const FolderPickerDialog(
                        title: 'Select Destination Folder',
                      ),
                    );
                    if (pickedId != null) {
                      setState(() {
                        if (pickedId == '__root__') {
                          _targetFolderId = null;
                          _targetFolderName = 'My Drive';
                        } else {
                          _targetFolderId = pickedId;
                          _resolveFolderName(pickedId);
                        }
                      });
                    }
                  },
                ),
              ],
            ),
          ],
        );

      case _ImportStep.passwordPrompt:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This link is password-protected. Enter the password set by the sender to decrypt the metadata.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter password',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],
        );

      case _ImportStep.fetchingMetadata:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Measuring internet speed and fetching metadata...',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
        );

      case _ImportStep.confirm:
        final sizeStr = _formatBytes(_totalSize);
        final double speedMb = _speedBytesPerSec / (1024 * 1024);
        final speedStr = '${speedMb.toStringAsFixed(1)} MB/s';
        final double totalTransferred = _totalSize.toDouble() * 2;
        final double durationSec = _speedBytesPerSec > 0 ? totalTransferred / _speedBytesPerSec : 0;
        final int durationMin = (durationSec / 60).ceil();
        final durationStr = '$durationMin minute${durationMin == 1 ? "" : "s"}';

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Importing this shared item will download and re-encrypt the data to your storage channel.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 14),
            _buildDetailRow('Total Size:', sizeStr),
            _buildDetailRow('Internet Data Cost:', '${_formatBytes(_totalSize * 2)} (Download + Upload)'),
            _buildDetailRow('Measured Speed:', speedStr),
            _buildDetailRow('Estimated Time:', durationStr),
          ],
        );

      case _ImportStep.importing:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Importing share and re-encrypting chunks to your storage...',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
        );

      case _ImportStep.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _errorMessage ?? 'An unexpected error occurred during import.',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        );
    }
  }

  List<Widget> _buildActions() {
    switch (_currentStep) {
      case _ImportStep.input:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _startImportFlow,
            child: const Text('Import', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ];

      case _ImportStep.passwordPrompt:
        return [
          TextButton(
            onPressed: () {
              setState(() {
                _currentStep = _ImportStep.input;
              });
            },
            child: const Text('Back', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => _executeImport(_urlController.text.trim()),
            child: const Text('Decrypt & Import', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ];

      case _ImportStep.fetchingMetadata:
        return [
          TextButton(
            onPressed: _onCancelImport,
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
        ];

      case _ImportStep.confirm:
        return [
          TextButton(
            onPressed: _onCancelImport,
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _onProceedConfirmed,
            child: const Text('Proceed', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ];

      case _ImportStep.importing:
        return []; // Non-cancellable once transfer loop starts to avoid corrupted chunk states

      case _ImportStep.error:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              setState(() {
                _currentStep = _ImportStep.input;
                _errorMessage = null;
              });
            },
            child: const Text('Try Again', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ];
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }
}
