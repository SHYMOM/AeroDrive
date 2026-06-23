import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/features/drive/media_player_screen.dart';

class PreviewRouter {
  /// Opens the correct viewer for a given file
  static void openPreview(BuildContext context, FileData file) {
    final mime = file.mimeType ?? '';

    if (mime.startsWith('video/')) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MediaPlayerScreen(file: file),
      ));
    } else if (mime.startsWith('audio/')) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MediaPlayerScreen(file: file),
      ));
    } else if (mime.startsWith('image/')) {
      // For images, we can fetch the decrypted bytes and use MemoryImage
      // TODO: Implement ImagePreviewScreen
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image viewer opening...')),
      );
    } else if (mime == 'application/pdf') {
      // TODO: Implement PdfViewerScreen using syncfusion_flutter_pdfviewer
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF viewer not yet implemented')),
      );
    } else {
      // Fallback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No viewer available for $mime')),
      );
    }
  }
}
