import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/db/database.dart';
import '../../../domain/drive_operations_service.dart';

Future<bool?> showAeroDriveRenameDialog({
  required BuildContext context,
  required WidgetRef ref,
  FolderData? folder,
  FileData? file,
}) {
  assert(folder != null || file != null, 'Either folder or file must be provided');
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _RenameItemDialog(folder: folder, file: file),
  );
}

class _RenameItemDialog extends ConsumerStatefulWidget {
  const _RenameItemDialog({this.folder, this.file});

  final FolderData? folder;
  final FileData? file;

  @override
  ConsumerState<_RenameItemDialog> createState() => _RenameItemDialogState();
}

class _RenameItemDialogState extends ConsumerState<_RenameItemDialog> {
  late final TextEditingController _controller;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final initialName = widget.folder?.name ?? widget.file?.name ?? '';
    _controller = TextEditingController(text: initialName);

    // Auto-select basename before extension for files, or full name for folders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.file != null) {
        final name = widget.file!.name;
        final dotIndex = name.lastIndexOf('.');
        if (dotIndex > 0) {
          _controller.selection = TextSelection(baseOffset: 0, extentOffset: dotIndex);
        } else {
          _controller.selection = TextSelection(baseOffset: 0, extentOffset: name.length);
        }
      } else if (widget.folder != null) {
        _controller.selection = TextSelection(baseOffset: 0, extentOffset: widget.folder!.name.length);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final newName = _controller.text.trim();
    if (newName.isEmpty || _isSubmitting) return;

    final currentName = widget.folder?.name ?? widget.file?.name ?? '';
    if (newName == currentName) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final driveOps = ref.read(driveOperationsServiceProvider);
      bool success = false;
      if (widget.folder != null) {
        success = await driveOps.renameFolder(widget.folder!.id, newName);
      } else if (widget.file != null) {
        success = await driveOps.renameFile(widget.file!.id, newName);
      }

      if (mounted) {
        Navigator.of(context).pop(success);
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Renamed to "$newName"'),
              duration: const Duration(seconds: 2),
              backgroundColor: AppColors.primary,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rename failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFolder = widget.folder != null;
    final title = isFolder ? 'Rename Folder' : 'Rename File';

    return AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            isFolder ? Icons.folder_outlined : Icons.edit_note_rounded,
            color: AppColors.primary,
            size: 22,
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        style: TextStyle(color: theme.colorScheme.onSurface),
        decoration: InputDecoration(
          hintText: isFolder ? 'Folder Name' : 'File Name',
          hintStyle: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.outline.withValues(alpha: 0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: _isSubmitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }
}

