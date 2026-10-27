// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'accessibility_settings.dart';

enum SettingsChangeKind {
  /// A continuous change, such as dragging a slider.
  edit,

  /// One value set at once, such as an applied suggestion.
  apply,
  reset,
  undo,
}

/// A change to the settings that was kept, from [from] to [to].
class SettingsCommit {
  final SettingsChangeKind kind;
  final AccessibilitySettings from;
  final AccessibilitySettings to;

  const SettingsCommit(this.kind, this.from, this.to);
}

/// Holds the current [AccessibilitySettings], stores them locally and keeps
/// the last change in memory so it can be undone.
///
/// Settings are only ever written to SharedPreferences on this device, never
/// to Matrix account data.
class AccessibilityController extends ChangeNotifier {
  final SharedPreferences _store;
  AccessibilitySettings _settings;
  AccessibilitySettings? _undo;
  AccessibilitySettings? _editStart;
  final StreamController<SettingsCommit> _commits =
      StreamController.broadcast();

  AccessibilityController(this._store)
    : _settings = AccessibilitySettings.load(_store) {
    // Stores the migrated old font size once, so it is not read again.
    if (!AccessibilitySettings.isStored(_store)) _settings.save(_store);
  }

  AccessibilitySettings get settings => _settings;

  bool get canUndo => _undo != null;

  /// Every kept change, for the study log. A slider drag is one change; the
  /// previews while it runs are not.
  Stream<SettingsCommit> get commits => _commits.stream;

  /// Sets one value as a single undoable change.
  Future<void> apply(ScaleCategory category, double value) => _commit(
    SettingsChangeKind.apply,
    _settings,
    _settings.change(category, value),
  );

  /// Starts a continuous change, such as dragging a slider. Call [preview]
  /// while it runs and [endEdit] when it ends. The whole drag is one undo
  /// step.
  void beginEdit() => _editStart ??= _settings;

  void preview(ScaleCategory category, double value) {
    final next = _settings.change(category, value);
    if (next == _settings) return;
    _settings = next;
    notifyListeners();
  }

  Future<void> endEdit() async {
    final start = _editStart;
    _editStart = null;
    if (start == null) return;
    await _commit(SettingsChangeKind.edit, start, _settings);
  }

  Future<void> reset() => _commit(
    SettingsChangeKind.reset,
    _settings,
    AccessibilitySettings.defaults,
  );

  Future<void> undo() async {
    final previous = _undo;
    if (previous == null) return;
    final undone = _settings;
    _undo = null;
    _settings = previous;
    notifyListeners();
    _commits.add(SettingsCommit(SettingsChangeKind.undo, undone, previous));
    await _settings.save(_store);
  }

  Future<void> _commit(
    SettingsChangeKind kind,
    AccessibilitySettings previous,
    AccessibilitySettings next,
  ) async {
    if (previous == next) return;
    _undo = previous;
    _settings = next;
    notifyListeners();
    _commits.add(SettingsCommit(kind, previous, next));
    await next.save(_store);
  }

  @override
  void dispose() {
    _commits.close();
    super.dispose();
  }
}
