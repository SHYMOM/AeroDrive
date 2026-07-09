import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:pdfx/pdfx.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart' as xml;

import '../../data/db/database.dart';
import 'file_decryption_util.dart';

/// Returns icon data for a given MIME type or file extension
IconData fileTypeIcon(String? mime, String fileName) {
  final ext = fileName.split('.').last.toLowerCase();
  final m = mime ?? '';

  if (m.startsWith('image/')) return Icons.image_outlined;
  if (m.startsWith('video/')) return Icons.videocam_outlined;
  if (m.startsWith('audio/')) return Icons.audiotrack_outlined;
  if (m == 'application/pdf') return Icons.picture_as_pdf_outlined;
  if (m == 'text/html' || ext == 'html' || ext == 'htm') return Icons.html_outlined;
  if (m == 'text/x-markdown' || ext == 'md' || ext == 'markdown') return Icons.article_outlined;
  if (['doc', 'docx'].contains(ext)) return Icons.description_outlined;
  if (['xls', 'xlsx', 'csv'].contains(ext)) return Icons.table_chart_outlined;
  if (['ppt', 'pptx'].contains(ext)) return Icons.slideshow_outlined;
  if (['zip', 'rar', 'tar', '7z', 'gz'].any((e) => m.contains(e) || ext == e)) return Icons.folder_zip_outlined;
  if (m.startsWith('text/') || ['java', 'py', 'dart', 'js', 'ts', 'c', 'cpp', 'cs', 'go', 'kt', 'swift', 'rs', 'rb', 'php', 'sh', 'bat', 'json', 'xml', 'yaml', 'yml', 'toml', 'ini', 'conf'].contains(ext)) {
    return Icons.code_outlined;
  }
  return Icons.insert_drive_file_outlined;
}

/// Returns a color for a given file type
Color fileTypeColor(String? mime, String fileName) {
  final ext = fileName.split('.').last.toLowerCase();
  final m = mime ?? '';

  if (m.startsWith('image/')) return const Color(0xFF4CAF50);
  if (m.startsWith('video/')) return const Color(0xFF2196F3);
  if (m.startsWith('audio/')) return const Color(0xFF9C27B0);
  if (m == 'application/pdf') return const Color(0xFFE53935);
  if (m == 'text/html' || ext == 'html' || ext == 'htm') return const Color(0xFFFF9800);
  if (m == 'text/x-markdown' || ext == 'md' || ext == 'markdown') return const Color(0xFF607D8B);
  if (['doc', 'docx'].contains(ext)) return const Color(0xFF1565C0);
  if (['xls', 'xlsx', 'csv'].contains(ext)) return const Color(0xFF2E7D32);
  if (['ppt', 'pptx'].contains(ext)) return const Color(0xFFBF360C);
  if (['zip', 'rar', 'tar', '7z', 'gz'].any((e) => m.contains(e) || ext == e)) return const Color(0xFF795548);
  if (m.startsWith('text/') || ['java', 'py', 'dart', 'js', 'ts', 'c', 'cpp', 'cs', 'go', 'kt', 'swift', 'rs', 'rb', 'php', 'sh', 'bat', 'json', 'xml', 'yaml', 'yml', 'toml', 'ini', 'conf'].contains(ext)) {
    return const Color(0xFF00BCD4);
  }
  return const Color(0xFF9E9E9E);
}

/// Determines what kind of viewer to use
enum _ViewerType {
  text,
  html,
  markdown,
  pdf,
  docx,
  unsupported;
}

_ViewerType _getViewerType(FileData file) {
  final mime = file.mimeType ?? '';
  final ext = file.name.split('.').last.toLowerCase();

  if (mime == 'application/pdf') return _ViewerType.pdf;
  if (mime == 'text/html' || ext == 'html' || ext == 'htm') return _ViewerType.html;
  if (mime == 'text/x-markdown' || ext == 'md' || ext == 'markdown') return _ViewerType.markdown;
  if (ext == 'docx' || ext == 'doc') return _ViewerType.docx;
  if (mime.startsWith('text/') ||
      mime == 'application/json' ||
      mime == 'application/xml' ||
      mime == 'application/javascript' ||
      mime.endsWith('+xml') ||
      mime.endsWith('+json') ||
      ['java', 'py', 'dart', 'js', 'ts', 'c', 'cpp', 'cs', 'go', 'kt', 'swift', 'rs', 'rb', 'php', 'sh', 'bat', 'json', 'xml', 'yaml', 'yml', 'toml', 'ini', 'conf', 'gradle', 'cmake', 'makefile', 'dockerfile', 'properties'].contains(ext)) {
    return _ViewerType.text;
  }
  return _ViewerType.unsupported;
}

/// ── Main Universal File Viewer ────────────────────────────────────────────
class UniversalFileViewer extends ConsumerStatefulWidget {
  const UniversalFileViewer({super.key, required this.file});
  final FileData file;

  @override
  ConsumerState<UniversalFileViewer> createState() => _UniversalFileViewerState();
}

class _UniversalFileViewerState extends ConsumerState<UniversalFileViewer> {
  Uint8List? _data;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      final bytes = await loadDecryptedFile(container, widget.file);
      if (bytes == null || bytes.isEmpty) {
        if (mounted) setState(() { _error = 'Failed to load file content'; _isLoading = false; });
        return;
      }
      if (mounted) setState(() { _data = bytes; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading file...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    if (_error != null) {
      return _ErrorView(error: _error!, file: widget.file);
    }

    if (_data == null) {
      return _UnsupportedView(file: widget.file);
    }

    final viewerType = _getViewerType(widget.file);

    return switch (viewerType) {
      _ViewerType.text => _CodeTextViewer(file: widget.file, data: _data!),
      _ViewerType.markdown => _MarkdownViewer(file: widget.file, data: _data!),
      _ViewerType.html => _HtmlViewer(file: widget.file, data: _data!),
      _ViewerType.pdf => _PdfViewer(file: widget.file, data: _data!),
      _ViewerType.docx => _DocxViewer(file: widget.file, data: _data!),
      _ViewerType.unsupported => _UnsupportedView(file: widget.file),
    };
  }
}

// ── Error View ────────────────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.file});
  final String error;
  final FileData file;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(
              'Failed to load ${file.name}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(error, style: const TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ── Unsupported View ──────────────────────────────────────────────────────
class _UnsupportedView extends StatelessWidget {
  const _UnsupportedView({required this.file});
  final FileData file;

  String _formatSize(int? size) {
    if (size == null || size <= 0) return 'Unknown size';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final ext = file.name.split('.').last.toUpperCase();
    final color = fileTypeColor(file.mimeType, file.name);
    final icon = fileTypeIcon(file.mimeType, file.name);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.15),
                border: Border.all(color: color.withValues(alpha: 0.4), width: 2),
              ),
              child: Icon(icon, size: 48, color: color),
            ),
            const SizedBox(height: 24),
            Text(
              file.name,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '.$ext',
                style: TextStyle(color: color, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              file.mimeType ?? 'Unknown type',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            Text(
              _formatSize(file.size),
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 32),
            const Text(
              'This file type cannot be previewed in the app.',
              style: TextStyle(color: Colors.white54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                final url = Uri.parse('https://www.google.com/search?q=${Uri.encodeComponent(file.mimeType ?? file.name)}');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Download to Open'),
              style: FilledButton.styleFrom(backgroundColor: color),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Code/Text Viewer ──────────────────────────────────────────────────────
class _CodeTextViewer extends StatefulWidget {
  const _CodeTextViewer({required this.file, required this.data});
  final FileData file;
  final Uint8List data;

  @override
  State<_CodeTextViewer> createState() => _CodeTextViewerState();
}

class _CodeTextViewerState extends State<_CodeTextViewer> {
  double _fontSize = 13;
  bool _wordWrap = false;
  bool _showLineNumbers = true;

  bool get _isCode {
    final mime = widget.file.mimeType ?? '';
    final ext = widget.file.name.split('.').last.toLowerCase();
    return mime == 'application/json' ||
        mime == 'application/xml' ||
        mime == 'application/javascript' ||
        mime.endsWith('+xml') ||
        mime.endsWith('+json') ||
        ['java', 'py', 'dart', 'js', 'ts', 'c', 'cpp', 'cs', 'go', 'kt', 'swift', 'rs', 'rb', 'php', 'sh', 'bat', 'json', 'xml', 'yaml', 'yml', 'toml', 'ini', 'conf', 'gradle', 'cmake', 'properties'].contains(ext);
  }

  String get _language {
    final ext = widget.file.name.split('.').last.toLowerCase();
    final mime = widget.file.mimeType ?? '';
    final langs = {
      'dart': 'Dart', 'py': 'Python', 'java': 'Java', 'kt': 'Kotlin',
      'js': 'JavaScript', 'ts': 'TypeScript', 'json': 'JSON', 'xml': 'XML',
      'html': 'HTML', 'css': 'CSS', 'cpp': 'C++', 'c': 'C',
      'cs': 'C#', 'go': 'Go', 'rs': 'Rust', 'rb': 'Ruby',
      'php': 'PHP', 'sh': 'Shell', 'bat': 'Batch', 'swift': 'Swift',
      'yaml': 'YAML', 'yml': 'YAML', 'toml': 'TOML', 'ini': 'INI',
      'gradle': 'Gradle', 'md': 'Markdown',
    };
    if (langs.containsKey(ext)) return langs[ext]!;
    if (mime == 'application/json') return 'JSON';
    if (mime == 'application/xml') return 'XML';
    if (mime == 'application/javascript') return 'JavaScript';
    return 'Text';
  }

  Color get _langColor {
    final ext = widget.file.name.split('.').last.toLowerCase();
    final colors = {
      'dart': const Color(0xFF00B4D8), 'py': const Color(0xFF3776AB), 'java': const Color(0xFFE76F51),
      'kt': const Color(0xFF7F52FF), 'js': const Color(0xFFF7DF1E), 'ts': const Color(0xFF3178C6),
      'json': const Color(0xFF83C5BE), 'xml': const Color(0xFFE07A5F), 'html': const Color(0xFFE34C26),
      'css': const Color(0xFF264DE4), 'cpp': const Color(0xFF00599C), 'c': const Color(0xFF00599C),
      'cs': const Color(0xFF512BD4), 'go': const Color(0xFF00ADD8), 'rs': const Color(0xFFCE422B),
      'py': const Color(0xFF3776AB), 'rb': const Color(0xFFCC342D), 'php': const Color(0xFF777BB4),
      'sh': const Color(0xFF89E051), 'swift': const Color(0xFFFA7343),
    };
    return colors[ext] ?? const Color(0xFF9E9E9E);
  }

  @override
  Widget build(BuildContext context) {
    final text = utf8.decode(widget.data, allowMalformed: true);
    final lines = text.split('\n');

    return Column(
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: const Color(0xFF1A1A2E),
          child: Row(
            children: [
              // Language badge
              if (_isCode) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _langColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _langColor.withValues(alpha: 0.5)),
                  ),
                  child: Text(_language, style: TextStyle(color: _langColor, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                '${lines.length} lines',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const Spacer(),
              // Line numbers toggle
              if (_isCode) IconButton(
                icon: Icon(Icons.format_list_numbered, size: 18,
                    color: _showLineNumbers ? Colors.white70 : Colors.white30),
                tooltip: 'Toggle line numbers',
                onPressed: () => setState(() => _showLineNumbers = !_showLineNumbers),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
              // Word wrap toggle
              IconButton(
                icon: Icon(Icons.wrap_text, size: 18,
                    color: _wordWrap ? Colors.white70 : Colors.white30),
                tooltip: 'Toggle word wrap',
                onPressed: () => setState(() => _wordWrap = !_wordWrap),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
              // Font size controls
              IconButton(
                icon: const Icon(Icons.text_decrease, size: 16),
                tooltip: 'Decrease font size',
                onPressed: () => setState(() => _fontSize = (_fontSize - 1).clamp(8, 32)),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                color: Colors.white54,
              ),
              Text('${_fontSize.toInt()}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
              IconButton(
                icon: const Icon(Icons.text_increase, size: 16),
                tooltip: 'Increase font size',
                onPressed: () => setState(() => _fontSize = (_fontSize + 1).clamp(8, 32)),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                color: Colors.white54,
              ),
            ],
          ),
        ),
        // Code content
        Expanded(
          child: Container(
            color: const Color(0xFF0D1117),
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: _wordWrap ? Axis.vertical : Axis.horizontal,
                child: _buildCodeContent(text, lines),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCodeContent(String text, List<String> lines) {
    final codeStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: _fontSize,
      color: const Color(0xFFE2E8F0),
      height: 1.6,
    );

    if (!_isCode || !_showLineNumbers) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          text,
          style: codeStyle,
          maxLines: _wordWrap ? null : lines.length,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line numbers column
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(lines.length, (i) => Text(
              '${i + 1}',
              style: codeStyle.copyWith(
                color: const Color(0xFF4A5568),
                fontSize: _fontSize * 0.9,
              ),
              textAlign: TextAlign.right,
            )),
          ),
          // Vertical divider
          Container(
            width: 1,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: const Color(0xFF2D3748),
          ),
          // Code lines
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: lines.map((line) => _buildHighlightedLine(line, codeStyle)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHighlightedLine(String line, TextStyle base) {
    // Simple syntax highlighting
    final spans = _tokenizeLine(line, base);
    return SelectableText.rich(TextSpan(children: spans));
  }

  // Very basic tokenizer for common constructs
  List<TextSpan> _tokenizeLine(String line, TextStyle base) {
    if (!_isCode) return [TextSpan(text: line, style: base)];

    // Keywords
    final keywords = RegExp(
      r'\b(import|export|from|class|interface|extends|implements|abstract|final|const|var|let|function|async|await|'
      r'new|return|if|else|for|while|do|switch|case|break|continue|throw|try|catch|finally|'
      r'def|lambda|yield|with|as|in|is|not|and|or|static|public|private|protected|override|super|this|'
      r'void|null|true|false|undefined|nil|None|True|False|package|namespace|using|include|require|'
      r'val|fun|object|companion|data|sealed|enum|mixin|typedef|library|part|of)\b',
    );

    final types = RegExp(
      r'\b(int|double|num|String|bool|List|Map|Set|Object|dynamic|Future|Stream|'
      r'Widget|BuildContext|State|Color|Icon|Text|Column|Row|Container|Padding|'
      r'Integer|Double|Long|Float|char|byte|short|boolean|string|array|dict|tuple|Any|'
      r'void|Never|DateTime|Duration|Uri|RegExp|Symbol|Uint8List)\b',
    );

    final strings = RegExp(r'''("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`)''');
    final comments = RegExp(r'(#[^\n]*)|(\/\/[^\n]*)|(\/\*[\s\S]*?\*\/)');
    final numbers = RegExp(r'\b\d+\.?\d*\b');

    final spans = <TextSpan>[];
    var pos = 0;

    while (pos < line.length) {
      // Comments
      final commentMatch = comments.matchAsPrefix(line, pos);
      if (commentMatch != null) {
        spans.add(TextSpan(text: commentMatch.group(0), style: base.copyWith(color: const Color(0xFF6B737C), fontStyle: FontStyle.italic)));
        pos = commentMatch.end;
        continue;
      }
      // Strings
      final strMatch = strings.matchAsPrefix(line, pos);
      if (strMatch != null) {
        spans.add(TextSpan(text: strMatch.group(0), style: base.copyWith(color: const Color(0xFF98C379))));
        pos = strMatch.end;
        continue;
      }
      // Keywords
      final kwMatch = keywords.matchAsPrefix(line, pos);
      if (kwMatch != null) {
        spans.add(TextSpan(text: kwMatch.group(0), style: base.copyWith(color: const Color(0xFF82AAFF), fontWeight: FontWeight.w600)));
        pos = kwMatch.end;
        continue;
      }
      // Types
      final typeMatch = types.matchAsPrefix(line, pos);
      if (typeMatch != null) {
        spans.add(TextSpan(text: typeMatch.group(0), style: base.copyWith(color: const Color(0xFFFF5370))));
        pos = typeMatch.end;
        continue;
      }
      // Numbers
      final numMatch = numbers.matchAsPrefix(line, pos);
      if (numMatch != null) {
        spans.add(TextSpan(text: numMatch.group(0), style: base.copyWith(color: const Color(0xFFF78C6C))));
        pos = numMatch.end;
        continue;
      }

      spans.add(TextSpan(text: line[pos], style: base));
      pos++;
    }

    return spans.isEmpty ? [TextSpan(text: line, style: base)] : spans;
  }
}

// ── Markdown Viewer ────────────────────────────────────────────────────────
class _MarkdownViewer extends StatelessWidget {
  const _MarkdownViewer({required this.file, required this.data});
  final FileData file;
  final Uint8List data;

  @override
  Widget build(BuildContext context) {
    final text = utf8.decode(data, allowMalformed: true);

    return Scaffold(
      appBar: AppBar(
        title: Text(file.name, style: const TextStyle(fontSize: 14)),
        backgroundColor: const Color(0xFF1A1A2E),
      ),
      body: Markdown(
        data: text,
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          p: const TextStyle(color: Colors.white70),
          h1: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          h2: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          code: const TextStyle(backgroundColor: Colors.black26),
        ),
      ),
    );
  }
}

// ── HTML Viewer ────────────────────────────────────────────────────────────
class _HtmlViewer extends StatelessWidget {
  const _HtmlViewer({required this.file, required this.data});
  final FileData file;
  final Uint8List data;

  @override
  Widget build(BuildContext context) {
    final html = utf8.decode(data, allowMalformed: true);

    return Scaffold(
      appBar: AppBar(
        title: Text(file.name, style: const TextStyle(fontSize: 14)),
        backgroundColor: const Color(0xFF1A1A2E),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: HtmlWidget(
          html,
          textStyle: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}

// ── PDF Viewer ─────────────────────────────────────────────────────────────
class _PdfViewer extends StatefulWidget {
  const _PdfViewer({required this.file, required this.data});
  final FileData file;
  final Uint8List data;

  @override
  State<_PdfViewer> createState() => _PdfViewerState();
}

class _PdfViewerState extends State<_PdfViewer> {
  PdfController? _pdfController;

  @override
  void initState() {
    super.initState();
    _pdfController = PdfController(
      document: PdfDocument.openData(widget.data),
    );
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_pdfController == null) return const Center(child: CircularProgressIndicator());
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.file.name, style: const TextStyle(fontSize: 14)),
        backgroundColor: const Color(0xFF1A1A2E),
        actions: [
          PdfPageNumber(
            controller: _pdfController!,
            builder: (_, loadingState, page, pagesCount) => Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '$page/${pagesCount ?? 0}',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      ),
      body: PdfView(
        controller: _pdfController!,
        scrollDirection: Axis.vertical,
      ),
    );
  }
}

// ── Word/Docx Viewer ───────────────────────────────────────────────────────
class _DocxViewer extends StatelessWidget {
  const _DocxViewer({required this.file, required this.data});
  final FileData file;
  final Uint8List data;

  String _parseDocx(Uint8List docxBytes) {
    try {
      final archive = ZipDecoder().decodeBytes(docxBytes);
      final documentFile = archive.findFile('word/document.xml');
      if (documentFile == null) return 'Invalid docx file (word/document.xml not found).';

      final xmlString = utf8.decode(documentFile.content as List<int>);
      final document = xml.XmlDocument.parse(xmlString);
      
      final buffer = StringBuffer();
      final paragraphs = document.findAllElements('w:p');
      for (final p in paragraphs) {
        var prefix = '';
        final pPr = p.getElement('w:pPr');
        if (pPr != null) {
          final pStyle = pPr.getElement('w:pStyle');
          if (pStyle != null) {
            final styleVal = pStyle.getAttribute('w:val');
            if (styleVal == 'Heading1') {
              prefix = '# ';
            } else if (styleVal == 'Heading2') {
              prefix = '## ';
            } else if (styleVal == 'Heading3') {
              prefix = '### ';
            }
          }
        }
        
        buffer.write(prefix);
        
        final runs = p.findAllElements('w:r');
        for (final r in runs) {
          final rPr = r.getElement('w:rPr');
          final isBold = rPr?.getElement('w:b') != null;
          final isItalic = rPr?.getElement('w:i') != null;
          
          final texts = r.findAllElements('w:t');
          for (final t in texts) {
            var runText = t.innerText;
            if (isBold) runText = '**$runText**';
            if (isItalic) runText = '*$runText*';
            buffer.write(runText);
          }
        }
        buffer.writeln();
        buffer.writeln();
      }
      return buffer.toString();
    } catch (e) {
      return 'Error parsing docx file: $e';
    }
  }

  @override
  Widget build(BuildContext context) {
    final markdownText = _parseDocx(data);

    return Scaffold(
      appBar: AppBar(
        title: Text(file.name, style: const TextStyle(fontSize: 14)),
        backgroundColor: const Color(0xFF1A1A2E),
      ),
      body: Markdown(
        data: markdownText,
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          p: const TextStyle(color: Colors.white70),
          h1: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          h2: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          code: const TextStyle(backgroundColor: Colors.black26),
        ),
      ),
    );
  }
}
