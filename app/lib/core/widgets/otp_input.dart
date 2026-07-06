import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OtpInput extends StatefulWidget {

  const OtpInput({
    super.key,
    this.length = 6,
    required this.onCompleted,
    this.activeColor,
    this.inactiveColor,
    this.textColor,
  });
  final int length;
  final ValueChanged<String> onCompleted;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? textColor;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> with TickerProviderStateMixin {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  late final List<AnimationController> _glowControllers;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.length, (_) => TextEditingController());
    _focusNodes = List.generate(widget.length, (_) => FocusNode());
    _glowControllers = List.generate(
      widget.length,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 200),
      ),
    );

    for (var i = 0; i < widget.length; i++) {
      _focusNodes[i].addListener(() {
        if (_focusNodes[i].hasFocus) {
          _glowControllers[i].forward();
          // Select all text when focused so typing replaces it
          if (_controllers[i].text.isNotEmpty) {
            _controllers[i].selection = TextSelection(
              baseOffset: 0,
              extentOffset: _controllers[i].text.length,
            );
          }
        } else {
          _glowControllers[i].reverse();
        }
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    for (final g in _glowControllers) {
      g.dispose();
    }
    super.dispose();
  }

  void _onChanged(int index, String value) {
    if (_isUpdating) return;
    _isUpdating = true;

    // Handle paste: if multiple digits were entered, distribute them
    final cleaned = value.replaceAll(RegExp('[^0-9]'), '');
    if (cleaned.length > 1) {
      final chars = cleaned.split('');
      for (var i = 0; i < chars.length; i++) {
        final targetIndex = index + i;
        if (targetIndex < widget.length) {
          _controllers[targetIndex].text = chars[i];
          _controllers[targetIndex].selection = TextSelection.collapsed(offset: 1);
        }
      }
      final nextIndex = (index + chars.length).clamp(0, widget.length - 1);
      _focusNodes[nextIndex].requestFocus();
      _isUpdating = false;
      _checkCompleted();
      return;
    }

    // Single digit entered: keep only last char and move forward
    if (cleaned.isNotEmpty) {
      _controllers[index].text = cleaned.substring(cleaned.length - 1);
      _controllers[index].selection = TextSelection.collapsed(offset: 1);
      if (index < widget.length - 1) {
        _focusNodes[index + 1].requestFocus();
      }
    }

    _isUpdating = false;
    _checkCompleted();
  }

  void _onKeyEvent(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _controllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
    }
  }

  void _checkCompleted() {
    if (_isUpdating) return;
    final code = _controllers.map((c) => c.text).join();
    if (code.length == widget.length) {
      widget.onCompleted(code);
    }
  }

  void clear() {
    _isUpdating = true;
    for (final c in _controllers) {
      c.clear();
    }
    _isUpdating = false;
    _focusNodes[0].requestFocus();
  }

  @override
  Widget build(BuildContext context) => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.length, (index) => Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.length > 6 ? 4 : 6),
          child: _OtpBox(
            controller: _controllers[index],
            focusNode: _focusNodes[index],
            glowController: _glowControllers[index],
            activeColor: widget.activeColor,
            inactiveColor: widget.inactiveColor,
            textColor: widget.textColor,
            onChanged: (value) => _onChanged(index, value),
            onKeyEvent: (event) => _onKeyEvent(index, event),
          ),
        )),
    );
}

class _OtpBox extends StatefulWidget {

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.glowController,
    required this.onChanged,
    required this.onKeyEvent,
    this.activeColor,
    this.inactiveColor,
    this.textColor,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final AnimationController glowController;
  final ValueChanged<String> onChanged;
  final ValueChanged<KeyEvent> onKeyEvent;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? textColor;

  @override
  State<_OtpBox> createState() => _OtpBoxState();
}

class _OtpBoxState extends State<_OtpBox> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.onKeyEvent = _handleKeyEvent;
  }

  @override
  void dispose() {
    widget.focusNode.onKeyEvent = null;
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        widget.controller.text.isEmpty) {
      widget.onKeyEvent(event);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.activeColor ?? const Color(0xFFBB86FC);
    final inactive = widget.inactiveColor ?? Colors.white24;
    final text = widget.textColor ?? Colors.white;
    final focusNode = widget.focusNode;

    return AnimatedBuilder(
      animation: widget.glowController,
      builder: (context, child) {
        final glowValue = widget.glowController.value;
        return Container(
          width: 48,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: glowValue > 0
                ? [
                    BoxShadow(
                      color: active.withValues(alpha: 0.3 * glowValue),
                      blurRadius: 8 + (4 * glowValue),
                      spreadRadius: 2 * glowValue,
                    ),
                  ]
                : null,
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: focusNode,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2), // Allow 2 so we can detect input and trim
            ],
            onChanged: widget.onChanged,
            style: TextStyle(
              color: text,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              counterText: '',
              filled: true,
              fillColor: focusNode.hasFocus
                  ? active.withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.05),
              contentPadding: EdgeInsets.zero,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: focusNode.hasFocus ? active : inactive,
                  width: focusNode.hasFocus ? 2 : 1,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: inactive),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: active, width: 2),
              ),
            ),
          ),
        );
      },
    );
  }
}
