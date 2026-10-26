// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'accessibility_settings.dart';

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

  AccessibilityController(this._store)
    : _settings = AccessibilitySettings.load(_store) {
    // Stores the migrated old font size once, so it is not read again.
    if (!AccessibilitySettings.isStored(_store)) _settings.save(_store);
  }

  AccessibilitySettings get settings => _settings;

  bool get canUndo => _undo != null;

  /// Sets one value as a single undoable change.
  Future<void> apply(ScaleCategory category, double value) =>
      _commit(_settings, _settings.copyWith(category, value));

  /// Starts a continuous change, such as dragging a slider. Call [preview]
  /// while it runs and [endEdit] when it ends. The whole drag is one undo
  /// step.
  void beginEdit() => _editStart ??= _settings;

  void preview(ScaleCategory category, double value) {
    final next = _settings.copyWith(category, value);
    if (next == _settings) return;
    _settings = next;
    notifyListeners();
  }

  Future<void> endEdit() async {
    final start = _editStart;
    _editStart = null;
    if (start == null) return;
    await _commit(start, _settings);
  }

  Future<void> reset() => _commit(_settings, AccessibilitySettings.defaults);

  Future<void> undo() async {
    final previous = _undo;
    if (previous == null) return;
    _undo = null;
    _settings = previous;
    notifyListeners();
    await _settings.save(_store);
  }

  Future<void> _commit(
    AccessibilitySettings previous,
    AccessibilitySettings next,
  ) async {
    if (previous == next) return;
    _undo = previous;
    _settings = next;
    notifyListeners();
    await next.save(_store);
  }
}
