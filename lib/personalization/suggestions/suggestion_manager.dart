// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../accessibility_controller.dart';
import '../accessibility_settings.dart';
import '../heuristics/heuristic.dart';
import '../heuristics/heuristics_engine.dart';
import '../signals/interaction_signal.dart';

/// A suggestion the user applied, with the settings it produced, so the card
/// can offer undo for a while.
class AppliedSuggestion {
  final Suggestion suggestion;
  final AccessibilitySettings settingsAfter;

  const AppliedSuggestion(this.suggestion, this.settingsAfter);
}

/// Decides which suggestion, if any, is shown, and enforces the rate limits:
/// one open suggestion at a time, a cooldown per heuristic after the user
/// declines it (not now or undo) and a permanent opt-out per heuristic.
/// Applying starts no cooldown, so if problems continue at the new size the
/// next step is suggested. Nothing is applied without [apply].
class SuggestionManager extends ChangeNotifier {
  static const optOutKey = 'personalization.suggestion_opt_outs';

  final AccessibilityController accessibility;
  final SharedPreferences _store;
  final DateTime Function() _clock;

  HeuristicsConfig _config;
  SignalWindow _window;
  HeuristicsEngine _engine;
  final Map<String, DateTime> _cooldownUntil = {};

  Suggestion? _current;
  AppliedSuggestion? _applied;
  Timer? _undoTimer;

  SuggestionManager({
    required this.accessibility,
    required SharedPreferences store,
    HeuristicsConfig config = HeuristicsConfig.empty,
    DateTime Function() clock = DateTime.now,
  }) : _store = store,
       _clock = clock,
       _config = config,
       _window = SignalWindow(config.signals),
       _engine = HeuristicsEngine(config.heuristics);

  HeuristicsConfig get config => _config;

  set config(HeuristicsConfig config) {
    _config = config;
    _window = SignalWindow(config.signals);
    _engine = HeuristicsEngine(config.heuristics);
  }

  /// The open suggestion, if any.
  Suggestion? get current => _current;

  /// The suggestion applied within the last undo period, if any.
  AppliedSuggestion? get applied => _applied;

  Set<String> get optedOut =>
      (_store.getStringList(optOutKey) ?? const []).toSet();

  void addSignal(InteractionSignal signal) {
    _window.add(signal);
    _evaluate();
  }

  void _evaluate() {
    if (_current != null || _applied != null) return;
    final now = _clock();
    final optedOut = this.optedOut;
    final candidates = _engine.evaluate(
      _window.recent(now),
      accessibility.settings,
      now,
    );
    for (final suggestion in candidates) {
      final id = suggestion.heuristic.id;
      if (optedOut.contains(id)) continue;
      final cooldownUntil = _cooldownUntil[id];
      if (cooldownUntil != null && now.isBefore(cooldownUntil)) continue;
      _current = suggestion;
      notifyListeners();
      return;
    }
  }

  Future<void> apply() async {
    final suggestion = _current;
    if (suggestion == null) return;
    _current = null;
    _resolve(suggestion, cooldown: false);
    await accessibility.apply(suggestion.category, suggestion.to);
    _applied = AppliedSuggestion(suggestion, accessibility.settings);
    _undoTimer?.cancel();
    _undoTimer = Timer(_config.undoDuration, dismissApplied);
    notifyListeners();
  }

  /// Reverts the applied suggestion, unless the user changed the settings
  /// again since, in which case undo would revert their own change.
  Future<void> undoApplied() async {
    final applied = _applied;
    if (applied == null) return;
    if (accessibility.settings == applied.settingsAfter &&
        accessibility.canUndo) {
      await accessibility.undo();
    }
    // Undo means the user declined the change, like "not now".
    _resolve(applied.suggestion);
    dismissApplied();
  }

  void dismissApplied() {
    _undoTimer?.cancel();
    _undoTimer = null;
    if (_applied == null) return;
    _applied = null;
    notifyListeners();
  }

  void notNow() {
    final suggestion = _current;
    if (suggestion == null) return;
    _current = null;
    _resolve(suggestion);
    notifyListeners();
  }

  Future<void> optOut() async {
    final suggestion = _current;
    if (suggestion == null) return;
    _current = null;
    _resolve(suggestion);
    notifyListeners();
    await _store.setStringList(optOutKey, [
      ...optedOut,
      suggestion.heuristic.id,
    ]);
  }

  void _resolve(Suggestion suggestion, {bool cooldown = true}) {
    if (cooldown) {
      _cooldownUntil[suggestion.heuristic.id] = _clock().add(
        suggestion.heuristic.cooldown,
      );
    }
    // The signals that led here were measured with the old sizes or were
    // already answered.
    _window.clear();
  }

  @override
  void dispose() {
    _undoTimer?.cancel();
    super.dispose();
  }
}
