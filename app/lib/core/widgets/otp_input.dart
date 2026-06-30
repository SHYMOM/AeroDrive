import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OtpInput extends StatefulWidget {
  final int length;
  final ValueChanged<String> onCompleted;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? textColor;

  const OtpInput({
    super.key,
    this.length = 6,
    required this.onCompleted,
    this.activeColor,
    this.inactiveColor,
    this.textColor,
  });

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
        } else {
          _glowControllers[i].reverse();
        }
      });
      _controllers[i].addListener(() => _onControllerChanged(i));
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

  void _onControllerChanged(int index) {
    if (_isUpdating) return;
    final text = _controllers[index].text;

    if (text.length > 1) {
      _isUpdating = true;
      final cleaned = text.replaceAll(RegExp(r'[^0-9]'), '');
      final chars = cleaned.split('').take(widget.length).toList();

      for (var i = 0; i < widget.length; i++) {
        _controllers[i].text = i < chars.length ? chars[i] : '';
      }

      _isUpdating = false;

      final nextIndex = chars.length < widget.length ? chars.length : widget.length - 1;
      _focusNodes[nextIndex].requestFocus();
      _checkCompleted();
      return;
    }

    if (text.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    } else if (text.isNotEmpty && index < widget.length - 1) {
      _focusNodes[index + 1].requestFocus();
    }

    _checkCompleted();
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
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.length, (index) {
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.length > 6 ? 4 : 6),
          child: _OtpBox(
            controller: _controllers[index],
            focusNode: _focusNodes[index],
            glowController: _glowControllers[index],
            activeColor: widget.activeColor,
            inactiveColor: widget.inactiveColor,
            textColor: widget.textColor,
          ),
        );
      }),
    );
  }
}

class _OtpBox extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final AnimationController glowController;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? textColor;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.glowController,
    this.activeColor,
    this.inactiveColor,
    this.textColor,
  });

  @override
  State<_OtpBox> createState() => _OtpBoxState();
}

class _OtpBoxState extends State<_OtpBox> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.onKeyEvent = _onKeyEvent;
  }

  @override
  void dispose() {
    widget.focusNode.onKeyEvent = null;
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        widget.controller.text.isEmpty) {
      final focusScope = FocusScope.of(context);
      focusScope.previousFocus();
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
                      color: active.withOpacity(0.3 * glowValue),
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
            ],
            style: TextStyle(
              color: text,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: focusNode.hasFocus
                  ? active.withOpacity(0.1)
                  : Colors.white.withOpacity(0.05),
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
                borderSide: BorderSide(color: inactive, width: 1),
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
