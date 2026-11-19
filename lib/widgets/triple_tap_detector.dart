// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Calls [onTripleTap] after three quick taps on [child], and [onDoubleTap]
/// after two quick taps that no third one follows.
///
/// Listens to raw pointer events instead of joining the gesture arena, so the
/// taps, double taps and long presses of [child] keep working.
class TripleTapDetector extends StatefulWidget {
  final VoidCallback? onTripleTap;

  /// Use this instead of the double tap of [child], which also fires on the
  /// first two taps of a triple tap.
  final VoidCallback? onDoubleTap;
  final Widget child;

  const TripleTapDetector({
    super.key,
    this.onTripleTap,
    this.onDoubleTap,
    required this.child,
  });

  @override
  State<TripleTapDetector> createState() => _TripleTapDetectorState();
}

class _TripleTapDetectorState extends State<TripleTapDetector> {
  int _count = 0;
  PointerDownEvent? _down;

  /// Ends the series when the next tap does not come in time.
  Timer? _seriesTimer;

  /// Turns a held pointer into a long press, which is not a tap.
  Timer? _longPressTimer;

  void _onDown(PointerDownEvent down) {
    _seriesTimer?.cancel();
    _longPressTimer?.cancel();
    _down = down;
    _longPressTimer = Timer(kLongPressTimeout, () => _down = null);
  }

  void _onUp(PointerUpEvent up) {
    _longPressTimer?.cancel();
    final down = _down;
    _down = null;
    if (down == null ||
        down.pointer != up.pointer ||
        (up.position - down.position).distance > kTouchSlop) {
      _count = 0;
      return;
    }
    _count++;
    if (_count == 3) {
      _count = 0;
      widget.onTripleTap?.call();
      return;
    }
    final count = _count;
    _seriesTimer = Timer(kDoubleTapTimeout, () {
      _count = 0;
      if (count == 2) widget.onDoubleTap?.call();
    });
  }

  void _onCancel(PointerCancelEvent _) {
    _longPressTimer?.cancel();
    _down = null;
    _count = 0;
  }

  @override
  void dispose() {
    _seriesTimer?.cancel();
    _longPressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTripleTap == null && widget.onDoubleTap == null) {
      return widget.child;
    }
    return Listener(
      onPointerDown: _onDown,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: widget.child,
    );
  }
}
