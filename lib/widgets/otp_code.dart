import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OtpCode extends StatefulWidget {
  const OtpCode({
    super.key,
    this.length = 6,
    this.autofocus = true,
    this.boxWidth = 42,
    this.boxHeight = 74,
    this.fontSize = 34,
    this.fontFamily,
    required this.onChanged,
    required this.onCompleted,
  });

  final int length;
  final bool autofocus;
  final double boxWidth;
  final double boxHeight;
  final double fontSize;
  final String? fontFamily;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onCompleted; 

  @override
  State<OtpCode> createState() => _OtpCodeState();
}

class _OtpCodeState extends State<OtpCode> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
    _focus = FocusNode();

    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    }
    _ctrl.addListener(_handleChanged);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_handleChanged);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _handleChanged() {
    final digits = _ctrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    final clipped = digits.substring(0, digits.length.clamp(0, widget.length));
    if (clipped != _ctrl.text) {
      _ctrl.value = TextEditingValue(
        text: clipped,
        selection: TextSelection.collapsed(offset: clipped.length),
      );
    }

    widget.onChanged(clipped);
    if (clipped.length == widget.length) {
      widget.onCompleted(clipped);
      _focus.unfocus();
    }
    setState(() {}); // refresh boxes
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final value = _ctrl.text;
    final cursorIndex = value.length.clamp(0, widget.length);

    final totalWidth =
        widget.boxWidth * widget.length + 12 * (widget.length - 1);

    return GestureDetector(
      onTap: () => _focus.requestFocus(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // visible digit boxes
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.length, (i) {
              final hasChar = i < value.length;
              final isActive = i == cursorIndex && value.length < widget.length;
              final ch = hasChar ? value[i] : '';

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Container(
                  width: widget.boxWidth,
                  height: widget.boxHeight,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isActive ? cs.primary : cs.outline,
                      width: isActive ? 2 : 1,
                    ),
                  ),
                  child: Text(
                    ch,
                    style: TextStyle(
                      fontSize: widget.fontSize,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                      fontFamily: widget.fontFamily,
                    ),
                  ),
                ),
              );
            }),
          ),

          // OVERLAY INPUT — invisible but interactive
SizedBox(
  width: totalWidth,
  height: widget.boxHeight,
  child: Opacity(
    opacity: 0.0, // fully hide any paint from the field
    child: TextField(
      controller: _ctrl,
      focusNode: _focus,
      autofocus: widget.autofocus,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      maxLength: widget.length,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(widget.length),
      ],
      showCursor: false,
      enableInteractiveSelection: false,   // no selection handles or toolbar
      style: const TextStyle(              // keep glyphs invisible
        color: Colors.transparent,
        fontSize: 0.1,
        height: 0.01,
      ),
      textAlign: TextAlign.center,
      cursorColor: Colors.transparent,
      decoration: const InputDecoration(
        counterText: '',
        border: InputBorder.none,
        isCollapsed: true,
        contentPadding: EdgeInsets.zero,
      ),
      onTap: () {
        final len = _ctrl.text.length;
        _ctrl.selection = TextSelection.collapsed(offset: len);
      },
    ),
  ),
)



        ],
      ),
    );
  }
}
