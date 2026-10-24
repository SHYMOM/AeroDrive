import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' as drift;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/logger.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/db/database.dart';
import '../../domain/scanner/document_scanner_service.dart';
import '../drive/providers/drive_providers.dart';

class DocumentScannerScreen extends ConsumerStatefulWidget {
  const DocumentScannerScreen({super.key, this.targetFolderId});
  final String? targetFolderId;

  @override
  ConsumerState<DocumentScannerScreen> createState() => _DocumentScannerScreenState();
}

class _DocumentScannerScreenState extends ConsumerState<DocumentScannerScreen> {
  final DocumentScannerService _scannerService = DocumentScannerService();
  final List<Uint8List> _originalPages = [];
  final List<Uint8List> _processedPages = [];
  DocumentColorFilter _currentFilter = DocumentColorFilter.blackAndWhite;
  int _activePageIndex = 0;
  bool _isProcessing = false;
  final TextEditingController _titleController = TextEditingController(text: 'Scanned_Doc_${DateTime.now().millisecondsSinceEpoch ~/ 1000}');

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickPage() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() => _isProcessing = true);
        for (final pf in result.files) {
          if (pf.path != null) {
            final bytes = await File(pf.path!).readAsBytes();
            _originalPages.add(bytes);
            final processed = _scannerService.processImagePage(bytes, _currentFilter);
            _processedPages.add(processed);
          }
        }
        setState(() {
          _activePageIndex = _processedPages.length - 1;
          _isProcessing = false;
        });
      }
    } catch (e) {
      AppLogger.error('Failed to pick document pages', e);
      setState(() => _isProcessing = false);
    }
  }

  void _applyFilter(DocumentColorFilter filter) {
    setState(() {
      _currentFilter = filter;
      _processedPages.clear();
      for (final raw in _originalPages) {
        _processedPages.add(_scannerService.processImagePage(raw, filter));
      }
    });
  }

  Future<void> _saveAndUpload() async {
    if (_processedPages.isEmpty) return;

    var name = _titleController.text.trim();
    if (!name.toLowerCase().endsWith('.pdf')) {
      name = '$name.pdf';
    }

    setState(() => _isProcessing = true);
    try {
      final pdfFile = await _scannerService.compileImagesToPdf(
        jpegPages: _processedPages,
        filename: name,
      );

      final db = ref.read(databaseProvider);
      final fileSize = await pdfFile.length();
      await db.into(db.transferQueue).insert(
        TransferQueueCompanion.insert(
          id: const Uuid().v4(),
          type: const drift.Value('UPLOAD_FILE'),
          status: const drift.Value('PENDING'),
          priority: const drift.Value(1),
          totalBytes: drift.Value(fileSize),
          fileId: drift.Value('${pdfFile.path}|${widget.targetFolderId ?? ''}'),
          createdAt: drift.Value(DateTime.now()),
        ),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Document "$name" saved and queued for encrypted upload!'),
            backgroundColor: AppColors.success,
          ),
        );
        ref.invalidate(folderContentsProvider);
        Navigator.pop(context);
      }
    } catch (e) {
      AppLogger.error('Failed to compile or upload document', e);
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save document: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Document Scanner', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_processedPages.isNotEmpty)
            TextButton.icon(
              onPressed: _isProcessing ? null : _saveAndUpload,
              icon: const Icon(Icons.check, color: AppColors.primary),
              label: const Text('Save PDF', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: _originalPages.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withValues(alpha: 0.15),
                    ),
                    child: const Icon(Icons.document_scanner_outlined, size: 40, color: AppColors.primary),
                  ),
                  const SizedBox(height: 20),
                  const Text('No Document Pages Added', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Scan contracts, receipts, or notes into a multi-page PDF', style: TextStyle(color: Colors.white60, fontSize: 13)),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _pickPage,
                    icon: const Icon(Icons.add_photo_alternate),
                    label: const Text('Add Document Pages'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    controller: _titleController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Document Name',
                      labelStyle: const TextStyle(color: Colors.white70),
                      suffixText: '.pdf',
                      suffixStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildFilterChip('B&W Document', DocumentColorFilter.blackAndWhite),
                      const SizedBox(width: 8),
                      _buildFilterChip('Enhanced Color', DocumentColorFilter.enhancedContrast),
                      const SizedBox(width: 8),
                      _buildFilterChip('Original', DocumentColorFilter.original),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          _processedPages[_activePageIndex.clamp(0, _processedPages.length - 1)],
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  height: 90,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  color: AppColors.surfaceElevated.withValues(alpha: 0.5),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _processedPages.length + 1,
                    itemBuilder: (context, idx) {
                      if (idx == _processedPages.length) {
                        return Center(
                          child: IconButton.filledTonal(
                            onPressed: _pickPage,
                            icon: const Icon(Icons.add),
                            tooltip: 'Add Page',
                          ),
                        );
                      }
                      final isSelected = _activePageIndex == idx;
                      return GestureDetector(
                        onTap: () => setState(() => _activePageIndex = idx),
                        child: Container(
                          width: 60,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: isSelected ? AppColors.primary : Colors.white24,
                              width: isSelected ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(_processedPages[idx], fit: BoxFit.cover),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(4)),
                                  child: Text('${idx + 1}', style: const TextStyle(fontSize: 10, color: Colors.white)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilterChip(String label, DocumentColorFilter filter) {
    final isSelected = _currentFilter == filter;
    return ChoiceChip(
      label: Text(label, style: TextStyle(color: isSelected ? Colors.black : Colors.white70, fontSize: 12)),
      selected: isSelected,
      selectedColor: AppColors.primary,
      backgroundColor: Colors.white10,
      onSelected: (_) => _applyFilter(filter),
    );
  }
}
