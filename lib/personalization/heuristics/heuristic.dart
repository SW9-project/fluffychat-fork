// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';

import '../accessibility_settings.dart';
import '../signals/interaction_signal.dart';

/// When a heuristic fires. Heuristics are data: see
/// `assets/personalization_heuristics.json`.
sealed class HeuristicCondition {
  const HeuristicCondition();

  bool isMetBy(List<InteractionSignal> signals, DateTime now);

  static HeuristicCondition fromJson(Map<String, Object?> json) {
    final kind = _targetKind(json['targetKind']);
    return switch (json['type']) {
      'share' => ShareCondition(
        signal: _signalType(json['signal']),
        of: (json['of'] as List).map(_signalType).toSet(),
        targetKind: kind,
        minShare: (json['minShare'] as num).toDouble(),
        minEvents: (json['minEvents'] as num).toInt(),
      ),
      'count' => CountCondition(
        signal: _signalType(json['signal']),
        targetKind: kind,
        minCount: (json['minCount'] as num).toInt(),
        within: Duration(minutes: (json['withinMinutes'] as num).toInt()),
      ),
      final type => throw FormatException('Unknown condition type: $type'),
    };
  }

  static SignalType _signalType(Object? name) =>
      SignalType.values.firstWhere((t) => t.name == name);

  static TargetKind? _targetKind(Object? name) =>
      name == null ? null : TargetKind.values.firstWhere((k) => k.name == name);
}

/// Fires when [signal] makes up at least [minShare] of all signals in [of],
/// counted over at least [minEvents] events. Example: near misses on buttons
/// divided by all taps on buttons.
class ShareCondition extends HeuristicCondition {
  final SignalType signal;
  final Set<SignalType> of;
  final TargetKind? targetKind;
  final double minShare;
  final int minEvents;

  const ShareCondition({
    required this.signal,
    required this.of,
    required this.targetKind,
    required this.minShare,
    required this.minEvents,
  });

  @override
  bool isMetBy(List<InteractionSignal> signals, DateTime now) {
    final relevant = signals.where(
      (s) => targetKind == null || s.kind == targetKind,
    );
    final total = relevant.where((s) => of.contains(s.type)).length;
    if (total < minEvents || total == 0) return false;
    final matching = relevant.where((s) => s.type == signal).length;
    return matching / total >= minShare;
  }
}

/// Fires when [signal] happened at least [minCount] times within [within].
class CountCondition extends HeuristicCondition {
  final SignalType signal;
  final TargetKind? targetKind;
  final int minCount;
  final Duration within;

  const CountCondition({
    required this.signal,
    required this.targetKind,
    required this.minCount,
    required this.within,
  });

  @override
  bool isMetBy(List<InteractionSignal> signals, DateTime now) =>
      signals
          .where(
            (s) =>
                s.type == signal &&
                (targetKind == null || s.kind == targetKind) &&
                now.difference(s.time) <= within,
          )
          .length >=
      minCount;
}

class Heuristic {
  final String id;
  final String source;

  /// When the disabled Phase 2 engine would suggest it. Since Phase 3b only
  /// the model proposes heuristics, so files exported from the heuristics
  /// catalog have none.
  final HeuristicCondition? condition;
  final ScaleCategory category;
  final int steps;
  final Duration cooldown;

  /// Premade description per language code, e.g. `en` and `da`.
  final Map<String, String> descriptions;

  /// One plain English sentence the on-device model reads: which problem the
  /// heuristic addresses and which change helps. Without it the heuristic is
  /// not offered to the model.
  final String? rule;

  const Heuristic({
    required this.id,
    required this.source,
    this.condition,
    required this.category,
    required this.steps,
    required this.cooldown,
    required this.descriptions,
    this.rule,
  });

  String description(String languageCode) =>
      descriptions[languageCode] ?? descriptions['en'] ?? '';

  factory Heuristic.fromJson(Map<String, Object?> json) {
    final change = json['change'] as Map<String, Object?>;
    final condition = json['condition'] as Map<String, Object?>?;
    final categoryName = change['category'];
    final category = ScaleCategory.values.firstWhereOrNull(
      (c) => c.name == categoryName,
    );
    if (category == null) {
      throw FormatException('Unknown category: $categoryName');
    }
    return Heuristic(
      id: json['id'] as String,
      source: json['source'] as String? ?? '',
      condition: condition == null
          ? null
          : HeuristicCondition.fromJson(condition),
      category: category,
      steps: (change['steps'] as num?)?.toInt() ?? 1,
      cooldown: Duration(
        minutes: (json['cooldownMinutes'] as num?)?.toInt() ?? 30,
      ),
      descriptions: (json['description'] as Map<String, Object?>).map(
        (key, value) => MapEntry(key, value as String),
      ),
      rule: json['rule'] as String?,
    );
  }
}

/// The whole heuristics file.
class HeuristicsConfig {
  final SignalConfig signals;
  final Duration undoDuration;
  final List<Heuristic> heuristics;

  const HeuristicsConfig({
    required this.signals,
    required this.undoDuration,
    required this.heuristics,
  });

  static const empty = HeuristicsConfig(
    signals: SignalConfig(),
    undoDuration: Duration(seconds: 10),
    heuristics: [],
  );

  /// Parses the file. A broken heuristic is skipped and reported through
  /// [onError] so one typo does not disable the others.
  factory HeuristicsConfig.fromJson(
    Map<String, Object?> json, {
    void Function(Object error)? onError,
  }) {
    final heuristics = <Heuristic>[];
    for (final entry in (json['heuristics'] as List? ?? const [])) {
      try {
        heuristics.add(Heuristic.fromJson(entry as Map<String, Object?>));
      } catch (e) {
        onError?.call(e);
      }
    }
    final suggestions = json['suggestions'] as Map<String, Object?>? ?? {};
    return HeuristicsConfig(
      signals: SignalConfig.fromJson(
        json['signals'] as Map<String, Object?>? ?? {},
      ),
      undoDuration: Duration(
        seconds: (suggestions['undoSeconds'] as num?)?.toInt() ?? 10,
      ),
      heuristics: heuristics,
    );
  }
}
