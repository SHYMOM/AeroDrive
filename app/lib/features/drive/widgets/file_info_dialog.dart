import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers.dart';
import '../../../data/db/database.dart';

class FileInfoDialog extends ConsumerStatefulWidget {
  const FileInfoDialog({super.key, required this.file});

  final FileData file;

  @override
  ConsumerState<FileInfoDialog> createState() => _FileInfoDialogState();
}

class _FileInfoDialogState extends ConsumerState<FileInfoDialog> {
  List<ChunkData>? _chunks;
  bool _loadingChunks = true;
  String? _copiedKey;

  @override
  void initState() {
    super.initState();
    _loadChunks();
  }

  Future<void> _loadChunks() async {
    try {
      final db = ref.read(databaseProvider);
      final chunks = await (db.select(db.chunks)
            ..where((c) => c.fileId.equals(widget.file.id))
            ..orderBy([(c) => OrderingTerm.asc(c.chunkIndex)]))
          .get();
      if (mounted) {
        setState(() {
          _chunks = chunks;
          _loadingChunks = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingChunks = false);
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return '00:00';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    final hStr = h > 0 ? '${h.toString().padLeft(2, '0')}:' : '';
    return '$hStr${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _determineCipherMode() {
    if (widget.file.encryptionAlgo != null && widget.file.encryptionAlgo!.isNotEmpty) {
      return widget.file.encryptionAlgo!;
    }
    if (!widget.file.isEncrypted) {
      return 'Plaintext (Unencrypted)';
    }
    final mime = widget.file.mimeType?.toLowerCase() ?? '';
    if (mime.startsWith('video/') || mime.startsWith('audio/')) {
      return 'AES-256-CTR';
    }
    return 'AES-256-GCM';
  }

  void _copyToClipboard(String text, String key, String label) {
    Clipboard.setData(ClipboardData(text: text));
    setState(() => _copiedKey = key);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _copiedKey == key) {
        setState(() => _copiedKey = null);
      }
    });

    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final file = widget.file;

    final createdStr = file.createdAt != null
        ? DateFormat('MMM dd, yyyy • hh:mm a').format(file.createdAt!)
        : 'Unknown';
    final photoTakenStr = file.photoTakenAt != null
        ? DateFormat('MMM dd, yyyy • hh:mm a').format(file.photoTakenAt!)
        : null;

    final cipherMode = _determineCipherMode();
    final totalChunkCount = _chunks != null && _chunks!.isNotEmpty ? _chunks!.length : file.totalChunks;

    return AlertDialog(
      backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.95),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.shield_outlined, color: colorScheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'File Info',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: colorScheme.onSurfaceVariant, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 480,
          maxHeight: 520,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── General Properties ─────────────────────────────────────
              _buildSectionHeader(context, 'GENERAL PROPERTIES'),
              _buildMetaRow(context, 'Name:', file.name),
              _buildMetaRow(context, 'Type:', file.mimeType ?? 'Unknown'),
              _buildMetaRow(
                context,
                'Size:',
                '${_formatBytes(file.size ?? 0)} (${NumberFormat('#,###').format(file.size ?? 0)} bytes)',
              ),
              _buildMetaRow(context, 'Uploaded:', createdStr),
              if (file.duration != null && file.duration! > 0)
                _buildMetaRow(context, 'Duration:', _formatDuration(file.duration)),
              if (photoTakenStr != null)
                _buildMetaRow(context, 'Photo Taken:', photoTakenStr),

              const SizedBox(height: 16),

              // ── Cryptographic Inspector ────────────────────────────────
              _buildSectionHeader(context, 'CRYPTOGRAPHIC INSPECTOR'),
              _buildMetaRow(
                context,
                'Cipher Mode:',
                cipherMode,
                leadingIcon: file.isEncrypted ? Icons.lock : Icons.lock_open,
                iconColor: file.isEncrypted ? Colors.tealAccent : colorScheme.onSurfaceVariant,
              ),
              _buildMetaRow(context, 'Total Chunks:', '$totalChunkCount ${totalChunkCount == 1 ? "chunk" : "chunks"}'),

              // SHA-256 Hash with Copy
              _buildHashRow(
                context: context,
                label: 'SHA-256 Hash',
                hash: file.sha256Hash ?? 'Not available',
                keyName: 'sha256',
              ),

              if (file.encryptionNonce != null && file.encryptionNonce!.isNotEmpty)
                _buildHashRow(
                  context: context,
                  label: 'Nonce / IV',
                  hash: file.encryptionNonce!,
                  keyName: 'nonce',
                ),

              const SizedBox(height: 16),

              // ── Storage Chunks Breakdown ───────────────────────────────
              _buildSectionHeader(context, 'STORAGE CHUNKS (TELEGRAM MTPROTO)'),
              if (_loadingChunks)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: CircularProgressIndicator(color: colorScheme.primary, strokeWidth: 2),
                  ),
                )
              else if (_chunks == null || _chunks!.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No chunk records stored locally.',
                    style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                  ),
                )
              else
                ..._chunks!.map((c) => _buildChunkCard(context, c)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Close', style: TextStyle(color: colorScheme.primary)),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Text(
        title,
        style: TextStyle(
          color: colorScheme.primary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildMetaRow(
    BuildContext context,
    String label,
    String value, {
    IconData? leadingIcon,
    Color? iconColor,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (leadingIcon != null) ...[
            Icon(leadingIcon, size: 14, color: iconColor),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHashRow({
    required BuildContext context,
    required String label,
    required String hash,
    required String keyName,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCopied = _copiedKey == keyName;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                InkWell(
                  onTap: () => _copyToClipboard(hash, keyName, label),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isCopied ? Icons.check_rounded : Icons.copy_rounded,
                          size: 13,
                          color: isCopied ? Colors.greenAccent : colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isCopied ? 'Copied' : 'Copy',
                          style: TextStyle(
                            color: isCopied ? Colors.greenAccent : colorScheme.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SelectableText(
              hash,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChunkCard(BuildContext context, ChunkData chunk) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chunkKey = 'chunk_${chunk.chunkIndex}';
    final isCopied = _copiedKey == chunkKey;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Chunk #${(chunk.chunkIndex ?? 0) + 1} (${_formatBytes(chunk.size ?? 0)})',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (chunk.hash != null && chunk.hash!.isNotEmpty)
                InkWell(
                  onTap: () => _copyToClipboard(chunk.hash!, chunkKey, 'Chunk #${(chunk.chunkIndex ?? 0) + 1} hash'),
                  borderRadius: BorderRadius.circular(4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isCopied ? Icons.check_rounded : Icons.copy_rounded,
                        size: 12,
                        color: isCopied ? Colors.greenAccent : colorScheme.primary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        isCopied ? 'Copied' : 'Copy Hash',
                        style: TextStyle(
                          color: isCopied ? Colors.greenAccent : colorScheme.primary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'Message: #${chunk.messageId ?? "N/A"}',
                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11),
              ),
              const SizedBox(width: 12),
              Text(
                'Channel: ${chunk.channelId ?? "N/A"}',
                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
