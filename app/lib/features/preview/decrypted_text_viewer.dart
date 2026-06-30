import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:aerodrive/data/db/database.dart';
import 'package:aerodrive/features/preview/file_decryption_util.dart';

class DecryptedTextViewer extends ConsumerStatefulWidget {
  final FileData file;
  const DecryptedTextViewer({super.key, required this.file});

  @override
  ConsumerState<DecryptedTextViewer> createState() => _DecryptedTextViewerState();
}

class _DecryptedTextViewerState extends ConsumerState<DecryptedTextViewer> {
  Uint8List? _data;
  bool _isLoading = true;
  String? _error;
  double _fontSize = 13;

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
        setState(() { _error = 'Failed to load file'; _isLoading = false; });
        return;
      }
      if (mounted) {
        setState(() { _data = bytes; _isLoading = false; });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _error = e.toString(); _isLoading = false; });
      }
    }
  }

  bool get _isCode => switch (widget.file.mimeType ?? '') {
    'application/json' || 'application/xml' || 'application/javascript' ||
    'application/typescript' || 'text/html' || 'text/css' ||
    'text/x-dart' || 'text/x-python' || 'text/x-java' ||
    'text/x-c' || 'text/x-cpp' || 'text/x-rust' ||
    'text/x-yaml' || 'text/x-markdown' || 'text/x-sh' => true,
    _ when (widget.file.mimeType ?? '').endsWith('+xml') => true,
    _ when (widget.file.mimeType ?? '').endsWith('+json') => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Error: $_error'));
    if (_data == null) return const Center(child: Text('No data'));

    final text = utf8.decode(_data!, allowMalformed: true);
    final theme = Theme.of(context);
    final lines = text.split('\n');

    return Column(
      children: [
        if (_isCode)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
            ),
            child: Row(
              children: [
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.text_decrease, size: 18),
                  tooltip: 'Decrease font size',
                  onPressed: () => setState(() => _fontSize = (_fontSize - 1).clamp(8, 32)),
                ),
                Text('$_fontSize', style: const TextStyle(fontSize: 12)),
                IconButton(
                  icon: const Icon(Icons.text_increase, size: 18),
                  tooltip: 'Increase font size',
                  onPressed: () => setState(() => _fontSize = (_fontSize + 1).clamp(8, 32)),
                ),
              ],
            ),
          ),
        Expanded(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            constrained: false,
            child: SizedBox(
              width: _isCode ? _contentWidth(lines) : null,
              child: _buildContent(text, lines, theme),
            ),
          ),
        ),
      ],
    );
  }

  double _contentWidth(List<String> lines) {
    final longest = lines.fold(0, (int max, l) => l.length > max ? l.length : max);
    return longest * _fontSize * 0.65 + 60;
  }

  Widget _buildContent(String text, List<String> lines, ThemeData theme) {
    final codeStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: _fontSize,
      color: theme.colorScheme.onSurface,
      height: 1.5,
    );

    if (!_isCode) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: SelectableText.rich(
          TextSpan(children: _tokenize(text, codeStyle, theme)),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(lines.length, (i) {
                return Text(
                  '${i + 1}',
                  style: codeStyle.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    fontSize: _fontSize * 0.9,
                  ),
                  textAlign: TextAlign.right,
                );
              }),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: lines.map((line) {
                return SelectableText.rich(
                  TextSpan(children: _tokenize(line, codeStyle, theme)),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  List<TextSpan> _tokenize(String text, TextStyle base, ThemeData theme) {
    final spans = <TextSpan>[];
    final linkRegex = RegExp(r'(https?://[^\s)+<>,.!?;:"]+)');

    int pos = 0;
    while (pos < text.length) {
      final linkMatch = linkRegex.matchAsPrefix(text, pos);
      if (linkMatch != null) {
        spans.add(TextSpan(
          text: linkMatch.group(0),
          style: base.copyWith(color: Colors.blueAccent, decoration: TextDecoration.underline),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              final uri = Uri.tryParse(linkMatch.group(0)!);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
        ));
        pos = linkMatch.end;
        continue;
      }

      if (_isCode) {
        final codeMatch = _codePattern.matchAsPrefix(text, pos);
        if (codeMatch != null) {
          spans.add(_codeSpan(codeMatch, base));
          pos = codeMatch.end;
          continue;
        }
      }

      spans.add(TextSpan(text: text[pos]));
      pos++;
    }

    return spans;
  }

  static final _codePattern = RegExp(
    // strings: double, single, backtick (using non-raw for single-quote to avoid raw-string escape issues)
    '(?:'
    r'"(?:[^"\\]|\\.)*"'
    r"|'(?:[^'\\]|\\.)*'"
    r'|`(?:[^`\\]|\\.)*`'
    r')'
    r'|(#[^\n]*|//[^\n]*|/\*[\s\S]*?\*/)'
    r'|\b(\d+\.?\d*(?:[eE][+-]?\d+)?)\b'
    r'|\b(false|true|null|void|import|export|from|return|if|else|for|while|do|switch|case|break|continue|'
    r'class|interface|extends|implements|abstract|final|const|var|let|function|async|await|new|throw|try|catch|'
    r'def|lambda|yield|with|as|in|is|not|and|or|static|public|private|protected|override|super|this|'
    r'print|debugPrint|require|module|package|library|typedef|enum|mixin|part|of)\b'
    r'|\b(int|double|num|String|bool|List|Map|Set|Object|dynamic|void|Never|Future|Stream|'
    r'Uint8List|Uint16List|Uint32List|Uint64List|Int8List|Int16List|Int32List|Int64List|'
    r'Float32List|Float64List|DateTime|Duration|Uri|RegExp|Symbol)\b',
  );

  TextSpan _codeSpan(Match match, TextStyle base) {
    if (match.group(1) != null) {
      return TextSpan(text: match.group(1), style: base.copyWith(color: const Color(0xFFC3E88D)));
    }
    if (match.group(2) != null) {
      return TextSpan(
        text: match.group(2),
        style: base.copyWith(color: const Color(0xFF546E7A), fontStyle: FontStyle.italic),
      );
    }
    if (match.group(3) != null) {
      return TextSpan(text: match.group(3), style: base.copyWith(color: const Color(0xFFF78C6C)));
    }
    if (match.group(4) != null) {
      return TextSpan(
        text: match.group(4),
        style: base.copyWith(color: const Color(0xFF82AAFF), fontWeight: FontWeight.w600),
      );
    }
    if (match.group(5) != null) {
      return TextSpan(text: match.group(5), style: base.copyWith(color: const Color(0xFFFF5370)));
    }
    return TextSpan(text: match.group(0));
  }
}
