// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import 'interaction_signal.dart';
import 'tracked_target.dart';

/// Disabled for now (Phase 3b): nothing inserts this widget, so no signals
/// are collected. Kept for a later phase.
///
/// Watches all pointer events below it without taking part in gestures and
/// reports taps and pinch attempts as [InteractionSignal]s.
class InteractionMonitor extends StatefulWidget {
  final Widget child;
  final SignalConfig config;
  final void Function(InteractionSignal signal) onSignal;

  /// Only for tests.
  final DateTime Function() clock;

  const InteractionMonitor({
    required this.child,
    required this.config,
    required this.onSignal,
    this.clock = DateTime.now,
    super.key,
  });

  @override
  State<InteractionMonitor> createState() => _InteractionMonitorState();
}

class _Pointer {
  final Offset downPosition;
  final DateTime downTime;
  Offset position;

  _Pointer(this.downPosition, this.downTime) : position = downPosition;
}

class _InteractionMonitorState extends State<InteractionMonitor> {
  /// Longest press that still counts as a tap.
  static const _maxTapDuration = Duration(milliseconds: 500);

  late TapClassifier _classifier = TapClassifier(widget.config);
  final Map<int, _Pointer> _pointers = {};
  List<TargetSnapshot> _targetsAtDown = const [];

  /// Set while more than one finger is down.
  bool _multiTouch = false;
  double? _pinchStartDistance;
  Offset? _pinchStartCenter;
  bool _pinchReported = false;

  @override
  void didUpdateWidget(InteractionMonitor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      _classifier = TapClassifier(widget.config);
    }
  }

  void _onDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch &&
        event.kind != PointerDeviceKind.mouse) {
      return;
    }
    _pointers[event.pointer] = _Pointer(event.position, widget.clock());
    if (_pointers.length == 1) {
      // Read the layout before the tap changes it, e.g. by opening a page.
      _targetsAtDown = TrackedTarget.snapshot();
    } else if (_pointers.length == 2) {
      _multiTouch = true;
      _pinchReported = false;
      final points = _pointers.values.map((p) => p.position).toList();
      _pinchStartDistance = (points[0] - points[1]).distance;
      _pinchStartCenter = (points[0] + points[1]) / 2;
    }
  }

  void _onMove(PointerMoveEvent event) {
    final pointer = _pointers[event.pointer];
    if (pointer == null) return;
    pointer.position = event.position;
    _checkPinch();
  }

  void _checkPinch() {
    final startDistance = _pinchStartDistance;
    final startCenter = _pinchStartCenter;
    if (_pinchReported ||
        _pointers.length != 2 ||
        startDistance == null ||
        startCenter == null ||
        startDistance == 0) {
      return;
    }
    final points = _pointers.values.map((p) => p.position).toList();
    final change = ((points[0] - points[1]).distance / startDistance - 1).abs();
    if (change < widget.config.pinchMinChange) return;
    // Only spreads count: the user tries to make something bigger.
    if ((points[0] - points[1]).distance < startDistance) return;
    final target = TrackedTarget.snapshot()
        .where((t) => t.kind == TargetKind.text && t.rect.contains(startCenter))
        .firstOrNull;
    if (target == null) return;
    _pinchReported = true;
    widget.onSignal(
      InteractionSignal(
        SignalType.pinch,
        widget.clock(),
        kind: target.kind,
        targetId: target.id,
      ),
    );
  }

  void _onUp(PointerUpEvent event) {
    final pointer = _pointers.remove(event.pointer);
    if (pointer != null && !_multiTouch) {
      final now = widget.clock();
      final isTap =
          now.difference(pointer.downTime) <= _maxTapDuration &&
          (event.position - pointer.downPosition).distance <= kTouchSlop;
      if (isTap) {
        for (final signal in _classifier.classify(
          pointer.downPosition,
          _targetsAtDown,
          now,
        )) {
          widget.onSignal(signal);
        }
      }
    }
    _endIfIdle();
  }

  void _onCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    _endIfIdle();
  }

  void _endIfIdle() {
    if (_pointers.isNotEmpty) return;
    _multiTouch = false;
    _pinchStartDistance = null;
    _pinchStartCenter = null;
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _onDown,
    onPointerMove: _onMove,
    onPointerUp: _onUp,
    onPointerCancel: _onCancel,
    child: widget.child,
  );
}
