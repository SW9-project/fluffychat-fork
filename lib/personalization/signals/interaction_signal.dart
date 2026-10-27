// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';
import 'dart:ui';

/// What kind of UI element a tracked target is.
enum TargetKind {
  button,
  listItem,

  /// Text the user may try to zoom, such as the chat timeline.
  text,

  /// An area whose taps are never recorded, such as the suggestion card.
  excluded,
}

enum SignalType { hit, nearMiss, repeatedTap, pinch }

/// One interaction observation. Holds no message content, only what kind of
/// element was involved and when.
class InteractionSignal {
  final SignalType type;
  final TargetKind? kind;
  final String? targetId;
  final DateTime time;

  const InteractionSignal(this.type, this.time, {this.kind, this.targetId});

  @override
  String toString() =>
      'InteractionSignal(${type.name}, ${kind?.name}, $targetId)';
}

/// A tracked target's id, kind and on-screen rectangle at one moment.
class TargetSnapshot {
  final String id;
  final TargetKind kind;
  final Rect rect;

  const TargetSnapshot(this.id, this.kind, this.rect);
}

/// Thresholds for turning raw pointer events into signals. All of them come
/// from the heuristics file so the team can tune them without code changes.
class SignalConfig {
  /// How far outside a target, in logical pixels, a tap still counts as a
  /// near miss.
  final double nearMissDistance;

  /// A tap counts as repeated when it lands within [repeatedTapDistance] of
  /// the previous tap and within [repeatedTapWindow] of it.
  final Duration repeatedTapWindow;
  final double repeatedTapDistance;

  /// Relative change in finger distance that counts as a pinch, e.g. 0.15.
  final double pinchMinChange;

  /// Signals older than this are dropped from the rolling window.
  final Duration window;
  final int maxEvents;

  const SignalConfig({
    this.nearMissDistance = 16,
    this.repeatedTapWindow = const Duration(milliseconds: 600),
    this.repeatedTapDistance = 24,
    this.pinchMinChange = 0.15,
    this.window = const Duration(minutes: 10),
    this.maxEvents = 500,
  });

  factory SignalConfig.fromJson(Map<String, Object?> json) {
    double number(String key, double fallback) =>
        (json[key] as num?)?.toDouble() ?? fallback;
    const d = SignalConfig();
    return SignalConfig(
      nearMissDistance: number('nearMissDistance', d.nearMissDistance),
      repeatedTapWindow: Duration(
        milliseconds: number(
          'repeatedTapWindowMs',
          d.repeatedTapWindow.inMilliseconds.toDouble(),
        ).round(),
      ),
      repeatedTapDistance: number('repeatedTapDistance', d.repeatedTapDistance),
      pinchMinChange: number('pinchMinChange', d.pinchMinChange),
      window: Duration(
        minutes: number('windowMinutes', d.window.inMinutes.toDouble()).round(),
      ),
      maxEvents: number('maxEvents', d.maxEvents.toDouble()).round(),
    );
  }
}

/// Distance from [point] to the closest point of [rect]; 0 when inside.
double distanceToRect(Offset point, Rect rect) {
  final dx = max(max(rect.left - point.dx, 0.0), point.dx - rect.right);
  final dy = max(max(rect.top - point.dy, 0.0), point.dy - rect.bottom);
  return sqrt(dx * dx + dy * dy);
}

/// Turns a tap position into signals. Pure, so it can be unit tested.
class TapClassifier {
  final SignalConfig config;
  Offset? _lastTapPosition;
  DateTime? _lastTapTime;

  TapClassifier(this.config);

  List<InteractionSignal> classify(
    Offset position,
    List<TargetSnapshot> targets,
    DateTime now,
  ) {
    if (targets.any(
      (t) => t.kind == TargetKind.excluded && t.rect.contains(position),
    )) {
      return const [];
    }

    final tappable = targets.where(
      (t) => t.kind == TargetKind.button || t.kind == TargetKind.listItem,
    );
    final signals = <InteractionSignal>[];

    // The smallest target containing the tap is the one that was hit, so a
    // button inside a list item counts as the button.
    final hits = tappable.where((t) => t.rect.contains(position)).toList()
      ..sort((a, b) => _area(a.rect).compareTo(_area(b.rect)));
    TargetSnapshot? target;
    if (hits.isNotEmpty) {
      target = hits.first;
      signals.add(
        InteractionSignal(
          SignalType.hit,
          now,
          kind: target.kind,
          targetId: target.id,
        ),
      );
    } else {
      TargetSnapshot? nearest;
      var nearestDistance = double.infinity;
      for (final t in tappable) {
        final distance = distanceToRect(position, t.rect);
        if (distance < nearestDistance) {
          nearest = t;
          nearestDistance = distance;
        }
      }
      if (nearest != null && nearestDistance <= config.nearMissDistance) {
        target = nearest;
        signals.add(
          InteractionSignal(
            SignalType.nearMiss,
            now,
            kind: nearest.kind,
            targetId: nearest.id,
          ),
        );
      }
    }

    final lastPosition = _lastTapPosition;
    final lastTime = _lastTapTime;
    if (lastPosition != null &&
        lastTime != null &&
        now.difference(lastTime) <= config.repeatedTapWindow &&
        (position - lastPosition).distance <= config.repeatedTapDistance) {
      signals.add(
        InteractionSignal(
          SignalType.repeatedTap,
          now,
          kind: target?.kind,
          targetId: target?.id,
        ),
      );
    }
    _lastTapPosition = position;
    _lastTapTime = now;

    return signals;
  }

  static double _area(Rect rect) => rect.width * rect.height;
}

/// The in-memory rolling window of recent signals. Never persisted.
class SignalWindow {
  final SignalConfig config;
  final List<InteractionSignal> _signals = [];

  SignalWindow(this.config);

  void add(InteractionSignal signal) {
    _signals.add(signal);
    if (_signals.length > config.maxEvents) {
      _signals.removeRange(0, _signals.length - config.maxEvents);
    }
  }

  List<InteractionSignal> recent(DateTime now) {
    _signals.removeWhere((s) => now.difference(s.time) > config.window);
    return List.unmodifiable(_signals);
  }

  void clear() => _signals.clear();
}
