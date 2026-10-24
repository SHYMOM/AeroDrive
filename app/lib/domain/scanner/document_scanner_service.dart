import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

enum DocumentColorFilter {
  original,
  blackAndWhite,
  enhancedContrast,
}

class DocumentScannerService {
  final Uuid _uuid = const Uuid();

  /// Applies document enhancement filters (e.g. B&W, contrast enhancement)
  Uint8List processImagePage(Uint8List imageBytes, DocumentColorFilter filter) {
    if (filter == DocumentColorFilter.original) return imageBytes;

    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return imageBytes;

    img.Image processed = decoded;
    if (filter == DocumentColorFilter.blackAndWhite) {
      processed = img.grayscale(processed);
      processed = img.contrast(processed, contrast: 150);
    } else if (filter == DocumentColorFilter.enhancedContrast) {
      processed = img.contrast(processed, contrast: 125);
      processed = img.adjustColor(processed, saturation: 1.1);
    }

    return Uint8List.fromList(img.encodeJpg(processed, quality: 85));
  }

  /// Compiles a list of JPEG image pages into a valid standard multi-page PDF
  Future<File> compileImagesToPdf({
    required List<Uint8List> jpegPages,
    required String filename,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final pdfFile = File('${tempDir.path}/${_uuid.v4()}_$filename');

    final buffer = BytesBuilder();
    final List<int> xrefOffsets = [];

    void writeString(String s) {
      final bytes = Uint8List.fromList(s.codeUnits);
      buffer.add(bytes);
    }

    int currentOffset() => buffer.length;

    // 1. Header
    writeString('%PDF-1.4\n');

    // 2. Catalog (Obj 1)
    xrefOffsets.add(currentOffset());
    writeString('1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n');

    final numPages = jpegPages.length;
    final List<int> pageObjNums = [];
    // Page objects start at obj 3
    var nextObj = 3;
    for (int i = 0; i < numPages; i++) {
      pageObjNums.add(nextObj);
      nextObj += 3; // Page, Content stream, Image XObject
    }

    // 3. Pages dictionary (Obj 2)
    xrefOffsets.add(currentOffset());
    final kidsStr = pageObjNums.map((n) => '$n 0 R').join(' ');
    writeString('2 0 obj\n<< /Type /Pages /Kids [$kidsStr] /Count $numPages >>\nendobj\n');

    // 4. Generate Page, Content, and Image XObjects
    for (int i = 0; i < numPages; i++) {
      final pageBytes = jpegPages[i];
      final decoded = img.decodeJpg(pageBytes);
      final double width = decoded?.width.toDouble() ?? 595.0;
      final double height = decoded?.height.toDouble() ?? 842.0;

      final pageObj = pageObjNums[i];
      final contentObj = pageObj + 1;
      final imageObj = pageObj + 2;

      // Page obj
      xrefOffsets.add(currentOffset());
      writeString(
        '$pageObj 0 obj\n<< /Type /Page /Parent 2 0 R '
        '/MediaBox [0 0 $width $height] '
        '/Contents $contentObj 0 R '
        '/Resources << /XObject << /Im$i $imageObj 0 R >> >> >>\nendobj\n',
      );

      // Content stream obj (Draws image to fit the MediaBox)
      final contentStream = 'q $width 0 0 $height 0 0 cm /Im$i Do Q\n';
      xrefOffsets.add(currentOffset());
      writeString(
        '$contentObj 0 obj\n<< /Length ${contentStream.length} >>\nstream\n$contentStream\nendstream\nendobj\n',
      );

      // Image XObject obj
      xrefOffsets.add(currentOffset());
      writeString(
        '$imageObj 0 obj\n<< /Type /XObject /Subtype /Image '
        '/Width ${decoded?.width ?? 595} /Height ${decoded?.height ?? 842} '
        '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode '
        '/Length ${pageBytes.length} >>\nstream\n',
      );
      buffer.add(pageBytes);
      writeString('\nendstream\nendobj\n');
    }

    // 5. Cross-Reference Table
    final startXref = currentOffset();
    final totalObjects = 1 + xrefOffsets.length; // 0 is free entry
    writeString('xref\n0 $totalObjects\n');
    writeString('0000000000 65535 f \n');
    for (final offset in xrefOffsets) {
      final offsetStr = offset.toString().padLeft(10, '0');
      writeString('$offsetStr 00000 n \n');
    }

    // 6. Trailer
    writeString(
      'trailer\n<< /Size $totalObjects /Root 1 0 R >>\n'
      'startxref\n$startXref\n%%EOF\n',
    );

    await pdfFile.writeAsBytes(buffer.toBytes());
    return pdfFile;
  }
}
