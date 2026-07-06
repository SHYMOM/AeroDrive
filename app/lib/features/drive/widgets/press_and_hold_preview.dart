import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:typed_data';
import 'dart:io';

import '../../../core/theme/app_colors.dart';
import '../../../data/db/database.dart';
import '../../gallery/thumbnail_service.dart';
import '../../preview/file_decryption_util.dart';
import 'file_type_icon.dart';

class PressAndHoldPreview extends StatefulWidget {
  const PressAndHoldPreview({
    super.key,
    required this.child,
    required this.file,
  });

  final Widget child;
  final FileData file;

  @override
  State<PressAndHoldPreview> createState() => _PressAndHoldPreviewState();
}

class _PressAndHoldPreviewState extends State<PressAndHoldPreview> {
  OverlayEntry? _overlayEntry;
  bool _isMenuShowing = false;

  void _showPreview(BuildContext context) {
    if (_overlayEntry != null || _isMenuShowing) return;

    _overlayEntry = OverlayEntry(
      builder: (context) => _PreviewOverlay(
        file: widget.file,
        onDismiss: _dismissPreview,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _dismissPreview() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _dismissPreview();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => _showPreview(context),
      onLongPressEnd: (_) => _dismissPreview(),
      onLongPressCancel: () => _dismissPreview(),
      child: widget.child,
    );
  }
}

class _PreviewOverlay extends ConsumerStatefulWidget {
  const _PreviewOverlay({
    required this.file,
    required this.onDismiss,
  });

  final FileData file;
  final VoidCallback onDismiss;

  @override
  ConsumerState<_PreviewOverlay> createState() => _PreviewOverlayState();
}

class _PreviewOverlayState extends ConsumerState<_PreviewOverlay> {
  File? _thumbnailFile;
  Uint8List? _decryptedBytes;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final thumb = await ref.read(thumbnailServiceProvider).getThumbnail(widget.file);
      if (mounted) {
        setState(() {
          _thumbnailFile = thumb;
        });
      }
    } catch (_) {}

    final mime = widget.file.mimeType ?? '';
    if (mime.startsWith('image/')) {
      try {
        final container = ProviderScope.containerOf(context);
        final bytes = await loadDecryptedFile(container, widget.file);
        if (mounted) {
          setState(() {
            _decryptedBytes = bytes;
          });
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final sizeStr = _formatBytes(widget.file.size ?? 0);
    final isVideo = widget.file.mimeType?.startsWith('video/') == true;
    final isImage = widget.file.mimeType?.startsWith('image/') == true;
    final isPdf = widget.file.mimeType?.contains('pdf') == true;

    return Material(
      color: Colors.black54,
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              height: MediaQuery.of(context).size.height * 0.6,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A), // Dark slate premium theme
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 30,
                    spreadRadius: 10,
                  )
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      color: Colors.white.withValues(alpha: 0.02),
                      child: Row(
                        children: [
                          FileTypeIcon(
                            mimeType: widget.file.mimeType,
                            fileName: widget.file.name,
                            size: 32,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.file.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Main Preview Area
                    Expanded(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (_decryptedBytes != null)
                            Image.memory(
                              _decryptedBytes!,
                              fit: BoxFit.contain,
                              width: double.infinity,
                              height: double.infinity,
                            )
                          else if (_thumbnailFile != null)
                            Image.file(
                              _thumbnailFile!,
                              fit: BoxFit.contain,
                              width: double.infinity,
                              height: double.infinity,
                            )
                          else
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isVideo
                                      ? Icons.video_library_outlined
                                      : isPdf
                                          ? Icons.picture_as_pdf_outlined
                                          : Icons.insert_drive_file_outlined,
                                  color: Colors.white24,
                                  size: 72,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Preview not available',
                                  style: TextStyle(color: Colors.white54, fontSize: 13),
                                ),
                              ],
                            ),
                            
                          if (isVideo && _thumbnailFile != null)
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.black,
                                  size: 32,
                                ),
                              ),
                            ),

                          if (_isLoading)
                            Container(
                              color: Colors.black38,
                              child: const Center(
                                child: CircularProgressIndicator(color: AppColors.primary),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Footer Info
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      color: Colors.white.withValues(alpha: 0.02),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            sizeStr,
                            style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            widget.file.mimeType ?? 'Unknown type',
                            style: const TextStyle(color: Colors.white30, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
