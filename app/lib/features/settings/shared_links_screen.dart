import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../sharing/import_link_dialog.dart';
import '../sharing/share_service.dart';

class SharedLinksScreen extends ConsumerStatefulWidget {
  const SharedLinksScreen({super.key});

  @override
  ConsumerState<SharedLinksScreen> createState() => _SharedLinksScreenState();
}

class _SharedLinksScreenState extends ConsumerState<SharedLinksScreen> {
  bool _isLoading = true;
  List<ShareRegistryEntry> _shares = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadShares();
  }

  Future<void> _loadShares() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final registry = await ref.read(shareServiceProvider).getShareRegistry();
      final activeShares = registry.where((e) => !e.revoked).toList();
      activeShares.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (mounted) {
        setState(() {
          _shares = activeShares;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load active share links: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _revokeShare(ShareRegistryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Revoke Share Link',
          style: TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to revoke the share for "${entry.name}"? '
          'This will permanently delete the shared chunks from Telegram, and the link will stop working immediately.',
          style: TextStyle(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Row(
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  'Revoking link and purging Telegram chunks...',
                  style: TextStyle(color: AppColors.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      await ref.read(shareServiceProvider).revokeShare(entry.id);

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // dismiss loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully revoked share for "${entry.name}"'),
            backgroundColor: AppColors.primary,
          ),
        );
        _loadShares();
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text('Revocation Failed', style: TextStyle(color: AppColors.onSurface)),
            content: Text(e.toString(), style: TextStyle(color: AppColors.onSurfaceVariant)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  void _copyLink(ShareRegistryEntry entry) {
    final linkText = 'aerodrive://share?id=${entry.id}&channelId=${entry.channelId}&manifestId=${entry.manifestMessageId}';
    Clipboard.setData(ClipboardData(text: linkText));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Share link for "${entry.name}" copied to clipboard!'),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Shared Links',
          style: TextStyle(
            color: AppColors.onSurface,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        backgroundColor: AppColors.surface,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.add_link_rounded, color: AppColors.primary),
            tooltip: 'Import Shared Link',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => const ImportLinkDialog(),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: AppColors.onSurfaceVariant),
            tooltip: 'Refresh',
            onPressed: _loadShares,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
                          const SizedBox(height: 16),
                          Text(
                            _error!,
                            style: TextStyle(color: AppColors.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _loadShares,
                            child: const Text('Try Again'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _shares.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(22),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.link_off_rounded,
                                size: 54,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'No Active Shared Links',
                              style: TextStyle(
                                color: AppColors.onSurface,
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Links you generate will appear here for 1-click copy or revocation.',
                              style: TextStyle(
                                color: AppColors.onSurfaceVariant,
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => const ImportLinkDialog(),
                                );
                              },
                              icon: const Icon(Icons.download_rounded, size: 18),
                              label: const Text('Import Shared Link'),
                            ),
                          ],
                        ).animate().fadeIn(duration: 300.ms),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        physics: const BouncingScrollPhysics(),
                        itemCount: _shares.length,
                        itemBuilder: (context, index) {
                          final entry = _shares[index];
                          final dateString = DateFormat('MMM d, yyyy  h:mm a').format(entry.createdAt);
                          final isFolder = entry.isFolder;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white.withValues(alpha: 0.04)
                                    : AppColors.outline.withValues(alpha: 0.5),
                              ),
                              boxShadow: AppColors.cardShadow,
                            ),
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: (isFolder ? AppColors.secondary : AppColors.primary)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      isFolder ? Icons.folder_shared_rounded : Icons.link_rounded,
                                      color: isFolder ? AppColors.secondary : AppColors.primary,
                                      size: 22,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.name,
                                        style: TextStyle(
                                          color: AppColors.onSurface,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.categoryOfflineBg,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'Active • AES-256',
                                              style: TextStyle(
                                                color: AppColors.categoryOffline,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              dateString,
                                              style: TextStyle(
                                                color: AppColors.onSurfaceVariant,
                                                fontSize: 11,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // 1-Click Copy Link Pill Button
                                InkWell(
                                  onTap: () => _copyLink(entry),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.copy_rounded, size: 14, color: AppColors.primary),
                                        const SizedBox(width: 5),
                                        Text(
                                          'Copy',
                                          style: TextStyle(
                                            color: AppColors.primary,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Revoke Action
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Color(0xFFEF4444),
                                    size: 20,
                                  ),
                                  tooltip: 'Revoke and delete',
                                  onPressed: () => _revokeShare(entry),
                                ),
                              ],
                            ),
                          ).animate().fadeIn(duration: 250.ms);
                        },
                      ),
      ),
    );
  }
}
