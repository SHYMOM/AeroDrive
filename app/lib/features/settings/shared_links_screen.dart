import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
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
      // Filter out already revoked ones just in case
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
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Revoke Share Link', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to revoke the share for "${entry.name}"? '
          'This will permanently delete the shared chunks from Telegram, and the link will stop working immediately.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show progress dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(
                child: Text(
                  'Revoking link and purging Telegram chunks...',
                  style: TextStyle(color: Colors.white),
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
          SnackBar(content: Text('Successfully revoked share for "${entry.name}"')),
        );
        _loadShares();
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // dismiss loading dialog
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Revocation Failed'),
            content: Text(e.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              )
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Shared Links', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadShares,
          )
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            radius: 1.5,
            colors: [
              Color(0xFF0D0E23), // deepSpace
              Color(0xFF1A0850), // dark edge
            ],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              style: const TextStyle(color: Colors.white70),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: _loadShares,
                              child: const Text('Try Again'),
                            )
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
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.02),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.link_off,
                                  size: 64,
                                  color: Colors.white.withValues(alpha: 0.2),
                                ),
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'No active share links',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Links you generate will appear here.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ).animate().fadeIn(duration: 400.ms),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          physics: const BouncingScrollPhysics(),
                          itemCount: _shares.length,
                          itemBuilder: (context, index) {
                            final entry = _shares[index];
                            final dateString = DateFormat('MM/dd/yyyy hh:mm a').format(entry.createdAt);
                            final isFolder = entry.isFolder;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: BackdropFilter(
                                  filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Icon(
                                            isFolder ? Icons.folder_shared : Icons.link,
                                            color: AppColors.primary,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                entry.name,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Shared on $dateString',
                                                style: TextStyle(
                                                  color: Colors.white.withValues(alpha: 0.4),
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                                          tooltip: 'Revoke and delete',
                                          onPressed: () => _revokeShare(entry),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0);
                          },
                        ),
        ),
      ),
    );
  }
}
