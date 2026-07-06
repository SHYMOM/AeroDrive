import 'dart:async';
import 'package:flutter/material.dart';

class MarqueeText extends StatefulWidget {
  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.alignment = Alignment.center,
    this.scrollDuration = const Duration(seconds: 4),
    this.pauseDuration = const Duration(seconds: 1),
  });

  final String text;
  final TextStyle style;
  final AlignmentGeometry alignment;
  final Duration scrollDuration;
  final Duration pauseDuration;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  late ScrollController _scrollController;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkScroll());
  }

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _timer?.cancel();
      _timer = null;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkScroll());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _checkScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll > 0) {
      if (_timer == null) {
        _startScrolling();
      }
    } else {
      _timer?.cancel();
      _timer = null;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
    }
  }

  void _startScrolling() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.scrollDuration + widget.pauseDuration * 2, (timer) async {
      if (!_scrollController.hasClients) return;
      final maxScroll = _scrollController.position.maxScrollExtent;
      if (maxScroll <= 0) {
        _timer?.cancel();
        _timer = null;
        return;
      }

      await Future.delayed(widget.pauseDuration);
      if (!_scrollController.hasClients) return;
      await _scrollController.animateTo(
        maxScroll,
        duration: widget.scrollDuration,
        curve: Curves.linear,
      );
      await Future.delayed(widget.pauseDuration);
      if (!_scrollController.hasClients) return;
      await _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout(minWidth: 0, maxWidth: double.infinity);

        final textWidth = textPainter.width;
        final parentWidth = constraints.maxWidth;

        if (textWidth <= parentWidth) {
          return Align(
            alignment: widget.alignment,
            child: Text(
              widget.text,
              style: widget.style,
              maxLines: 1,
            ),
          );
        } else {
          // Re-check scroll on layout builder update, in case layout constraints changed
          WidgetsBinding.instance.addPostFrameCallback((_) => _checkScroll());

          return SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Text(
              widget.text,
              style: widget.style,
              maxLines: 1,
            ),
          );
        }
      },
    );
  }
}
