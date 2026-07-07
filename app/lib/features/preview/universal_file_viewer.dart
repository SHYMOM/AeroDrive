import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

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
  unsupported,
}

_ViewerType _getViewerType(FileData file) {
  final mime = file.mimeType ?? '';
  final ext = file.name.split('.').last.toLowerCase();

  if (mime == 'application/pdf') return _ViewerType.pdf;
  if (mime == 'text/html' || ext == 'html' || ext == 'htm') return _ViewerType.html;
  if (mime == 'text/x-markdown' || ext == 'md' || ext == 'markdown') return _ViewerType.markdown;
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

    return Column(
      children: [
        // Header bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: const Color(0xFF1A1A2E),
          child: Row(
            children: [
              const Icon(Icons.article_outlined, color: Color(0xFF607D8B), size: 18),
              const SizedBox(width: 8),
              const Text('Markdown', style: TextStyle(color: Color(0xFF607D8B), fontSize: 12, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('${text.split('\n').length} lines', style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: const Color(0xFF0D1117),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _MarkdownRenderer(text: text),
            ),
          ),
        ),
      ],
    );
  }
}

class _MarkdownRenderer extends StatelessWidget {
  const _MarkdownRenderer({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    final widgets = <Widget>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      widgets.add(_buildLine(context, line));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildLine(BuildContext context, String line) {
    // H1
    if (line.startsWith('# ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(
          line.substring(2),
          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, height: 1.3),
        ),
      );
    }
    // H2
    if (line.startsWith('## ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(line.substring(3), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const Divider(color: Color(0xFF2D3748)),
          ],
        ),
      );
    }
    // H3
    if (line.startsWith('### ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(line.substring(4), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      );
    }
    // H4-H6
    if (line.startsWith('#### ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Text(line.substring(5), style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.bold)),
      );
    }
    // Horizontal rule
    if (line == '---' || line == '***' || line == '___') {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Divider(color: Color(0xFF2D3748)),
      );
    }
    // Blockquote
    if (line.startsWith('> ')) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: Color(0xFF4A5568), width: 4)),
          color: Color(0xFF1A2030),
        ),
        child: Text(line.substring(2), style: const TextStyle(color: Colors.white54, fontStyle: FontStyle.italic)),
      );
    }
    // Code block
    if (line.startsWith('```') || line.startsWith('    ')) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF2D3748)),
        ),
        child: SelectableText(
          line.startsWith('    ') ? line.substring(4) : line.replaceAll('```', ''),
          style: const TextStyle(fontFamily: 'monospace', color: Color(0xFFE2E8F0), fontSize: 13),
        ),
      );
    }
    // Bullet list
    if (line.startsWith('- ') || line.startsWith('* ') || line.startsWith('+ ')) {
      return Padding(
        padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 6, right: 8),
              child: CircleAvatar(radius: 3, backgroundColor: Color(0xFF4A90E2)),
            ),
            Expanded(child: _buildInlineText(line.substring(2))),
          ],
        ),
      );
    }
    // Numbered list
    final numListMatch = RegExp(r'^\d+\. (.+)').firstMatch(line);
    if (numListMatch != null) {
      final num = line.split('.').first;
      return Padding(
        padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text('$num.', style: const TextStyle(color: Color(0xFF4A90E2), fontWeight: FontWeight.bold)),
            ),
            Expanded(child: _buildInlineText(numListMatch.group(1)!)),
          ],
        ),
      );
    }
    // Empty line = spacing
    if (line.trim().isEmpty) {
      return const SizedBox(height: 8);
    }
    // Normal paragraph text
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: _buildInlineText(line),
    );
  }

  Widget _buildInlineText(String text) {
    // Handle bold/italic/code inline
    final spans = _parseInline(text);
    return SelectableText.rich(TextSpan(children: spans));
  }

  List<TextSpan> _parseInline(String text) {
    final spans = <TextSpan>[];
    var pos = 0;
    final base = const TextStyle(color: Color(0xFFCBD5E0), height: 1.6, fontSize: 14);

    while (pos < text.length) {
      // Bold **text**
      if (text.startsWith('**', pos)) {
        final end = text.indexOf('**', pos + 2);
        if (end != -1) {
          spans.add(TextSpan(
            text: text.substring(pos + 2, end),
            style: base.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
          ));
          pos = end + 2;
          continue;
        }
      }
      // Italic *text*
      if (text[pos] == '*' && (pos == 0 || text[pos - 1] != '*') && pos + 1 < text.length && text[pos + 1] != '*') {
        final end = text.indexOf('*', pos + 1);
        if (end != -1) {
          spans.add(TextSpan(
            text: text.substring(pos + 1, end),
            style: base.copyWith(fontStyle: FontStyle.italic),
          ));
          pos = end + 1;
          continue;
        }
      }
      // Inline code `code`
      if (text[pos] == '`') {
        final end = text.indexOf('`', pos + 1);
        if (end != -1) {
          spans.add(TextSpan(
            text: text.substring(pos + 1, end),
            style: base.copyWith(
              fontFamily: 'monospace',
              color: const Color(0xFF98C379),
              backgroundColor: const Color(0xFF161B22),
            ),
          ));
          pos = end + 1;
          continue;
        }
      }

      spans.add(TextSpan(text: text[pos], style: base));
      pos++;
    }

    return spans.isEmpty ? [TextSpan(text: text, style: base)] : spans;
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
    // Strip HTML tags for readable plain text preview
    final plainText = html
        .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '')
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return Column(
      children: [
        // HTML header bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(color: Color(0xFF1A1A2E)),
          child: Row(
            children: [
              const Icon(Icons.html_outlined, color: Color(0xFFFF9800), size: 18),
              const SizedBox(width: 8),
              const Text('HTML Preview', style: TextStyle(color: Color(0xFFFF9800), fontSize: 12, fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('Text mode', style: TextStyle(color: Color(0xFFFF9800), fontSize: 10)),
              ),
            ],
          ),
        ),
        // Tabs: Source / Preview
        DefaultTabController(
          length: 2,
          child: Expanded(
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: 'Rendered Text'),
                    Tab(text: 'HTML Source'),
                  ],
                  indicatorColor: Color(0xFFFF9800),
                  labelColor: Color(0xFFFF9800),
                  unselectedLabelColor: Colors.white54,
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      // Plain text view
                      Container(
                        color: const Color(0xFF0D1117),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: SelectableText(
                            plainText,
                            style: const TextStyle(color: Color(0xFFCBD5E0), height: 1.6, fontSize: 14),
                          ),
                        ),
                      ),
                      // HTML source view
                      Container(
                        color: const Color(0xFF0D1117),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(
                            html,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              color: Color(0xFFE2E8F0),
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── PDF Viewer ─────────────────────────────────────────────────────────────
class _PdfViewer extends StatelessWidget {
  const _PdfViewer({required this.file, required this.data});
  final FileData file;
  final Uint8List data;

  @override
  Widget build(BuildContext context) {
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
                color: const Color(0xFFE53935).withValues(alpha: 0.15),
                border: Border.all(color: const Color(0xFFE53935).withValues(alpha: 0.4), width: 2),
              ),
              child: const Icon(Icons.picture_as_pdf_outlined, size: 48, color: Color(0xFFE53935)),
            ),
            const SizedBox(height: 24),
            Text(
              file.name,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '${(data.length / 1024 / 1024).toStringAsFixed(2)} MB',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 24),
            const Text(
              'PDF files require an external viewer.\nThe file has been downloaded and is ready to open.',
              style: TextStyle(color: Colors.white54, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE53935).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE53935).withValues(alpha: 0.2)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline, color: Color(0xFF4CAF50), size: 16),
                  SizedBox(width: 8),
                  Text('PDF loaded in memory', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
