import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Remote keys that mean "press": D-pad centre, Enter, gamepad A.
bool isTvSelectKey(KeyEvent event) {
  final key = event.logicalKey;
  return key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.gameButtonA;
}

/// A D-pad focus stop that also works with touch and mouse.
///
/// [builder] gets the focus state so each caller draws its own highlight;
/// OK/Enter or a tap calls [onSelect]. With [repeat], holding OK keeps firing
/// (e.g. a delete key).
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.onSelect,
    required this.builder,
    this.focusNode,
    this.autofocus = false,
    this.repeat = false,
    this.onFocusChange,
  });

  final VoidCallback onSelect;
  final Widget Function(BuildContext context, bool focused) builder;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool repeat;
  final ValueChanged<bool>? onFocusChange;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (hasFocus) {
        setState(() => _focused = hasFocus);
        widget.onFocusChange?.call(hasFocus);
      },
      onKeyEvent: (node, event) {
        final pressed = event is KeyDownEvent ||
            (widget.repeat && event is KeyRepeatEvent);
        if (pressed && isTvSelectKey(event)) {
          widget.onSelect();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        child: widget.builder(context, _focused),
      ),
    );
  }
}
