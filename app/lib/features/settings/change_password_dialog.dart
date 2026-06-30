import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/domain/crypto/dek_migration_service.dart';

/// Dialog that walks the user through changing their master password.
///
/// On confirm it calls [DekMigrationService.changeMasterPassword] which:
///   - Verifies the old password
///   - Re-wraps ALL file DEKs with the new master key in a single DB transaction
///   - Updates the in-memory masterKeyProvider
///   - Zeroses the old master key bytes from memory
class ChangeMasterPasswordDialog extends ConsumerStatefulWidget {
  const ChangeMasterPasswordDialog({super.key});

  @override
  ConsumerState<ChangeMasterPasswordDialog> createState() =>
      _ChangeMasterPasswordDialogState();
}

class _ChangeMasterPasswordDialogState
    extends ConsumerState<ChangeMasterPasswordDialog> {
  final _oldCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _isLoading = false;
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final oldPw = _oldCtrl.text;
    final newPw = _newCtrl.text;
    final confirmPw = _confirmCtrl.text;

    if (oldPw.isEmpty || newPw.isEmpty || confirmPw.isEmpty) {
      setState(() => _error = 'All fields are required.');
      return;
    }
    if (newPw.length < 8) {
      setState(() => _error = 'New password must be at least 8 characters.');
      return;
    }
    if (newPw != confirmPw) {
      setState(() => _error = 'New passwords do not match.');
      return;
    }
    if (oldPw == newPw) {
      setState(() => _error = 'New password must differ from the old one.');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      final service = ref.read(dekMigrationServiceProvider);
      final result = await service.changeMasterPassword(
        oldPassword: oldPw,
        newPassword: newPw,
      );

      if (!mounted) return;

      if (result.isSuccess) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Password changed. ${result.migratedCount} file encryption keys migrated.'
              '${result.skippedCount > 0 ? ' (${result.skippedCount} skipped — no key)' : ''}',
            ),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 6),
          ),
        );
      } else {
        setState(() => _error = result.errorMessage ?? 'Unknown error.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change Master Password'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Changing your password will instantly re-encrypt all file keys '
                'in the local database. Your actual files on Telegram are never '
                're-uploaded. This operation is safe and reversible.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _oldCtrl,
              obscureText: _obscureOld,
              decoration: InputDecoration(
                labelText: 'Current Password',
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscureOld ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscureOld = !_obscureOld),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newCtrl,
              obscureText: _obscureNew,
              decoration: InputDecoration(
                labelText: 'New Password',
                prefixIcon: const Icon(Icons.lock),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscureNew ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscureNew = !_obscureNew),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmCtrl,
              obscureText: _obscureConfirm,
              decoration: InputDecoration(
                labelText: 'Confirm New Password',
                prefixIcon: const Icon(Icons.lock),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirm ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        _isLoading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.key, size: 18),
                label: const Text('Change & Migrate'),
              ),
      ],
    );
  }
}
