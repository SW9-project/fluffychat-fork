// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SimpleQuickAccess { frequent, chosen, none }

@immutable
class SimpleViewPreferences {
  final SimpleQuickAccess quickAccess;
  final bool cleanHome;
  final bool quietChat;

  const SimpleViewPreferences({
    this.quickAccess = SimpleQuickAccess.chosen,
    this.cleanHome = true,
    this.quietChat = true,
  });

  SimpleViewPreferences copyWith({
    SimpleQuickAccess? quickAccess,
    bool? cleanHome,
    bool? quietChat,
  }) => SimpleViewPreferences(
    quickAccess: quickAccess ?? this.quickAccess,
    cleanHome: cleanHome ?? this.cleanHome,
    quietChat: quietChat ?? this.quietChat,
  );

  Map<String, Object> toJson() => {
    'quickAccess': quickAccess.name,
    'cleanHome': cleanHome,
    'quietChat': quietChat,
  };

  static SimpleViewPreferences fromJson(String? source) {
    try {
      final json = jsonDecode(source ?? '{}');
      if (json is! Map) return const SimpleViewPreferences();
      return SimpleViewPreferences(
        quickAccess:
            SimpleQuickAccess.values
                .where((value) => value.name == json['quickAccess'])
                .firstOrNull ??
            SimpleQuickAccess.chosen,
        cleanHome: json['cleanHome'] != false,
        quietChat: true,
      );
    } on FormatException {
      return const SimpleViewPreferences();
    }
  }
}

/// Enabling this mode preserves stored sizes, filters, wallpaper preferences,
/// and notification settings.
/// The calmer chat is presented temporarily while this mode is enabled.
class SimplifiedInterfaceController extends ChangeNotifier {
  static const enabledKey = 'personalization.simplified_interface.enabled';
  static const quickAccessKey =
      'personalization.simplified_interface.quick_access';
  static const maxQuickAccess = 3;
  static const preferencesKey =
      'personalization.simplified_interface.preferences';
  static const skipPreviewKey =
      'personalization.simplified_interface.skip_preview';
  static const usageKey = 'personalization.simplified_interface.opens';

  final SharedPreferences _store;
  final bool _previewOnly;
  late bool _enabled = _store.getBool(enabledKey) ?? false;
  late final Map<String, List<String>> _quickAccess = _readQuickAccess();
  int _revision = 0;
  late Future<void> _writes = Future.value();
  late SimpleViewPreferences _preferences = SimpleViewPreferences.fromJson(
    _store.getString(preferencesKey),
  );
  late bool _configured = _store.containsKey(preferencesKey);
  late bool _skipPreview = _store.getBool(skipPreviewKey) ?? false;
  late final Map<String, Map<String, int>> _opens = _readOpens();

  SimplifiedInterfaceController(this._store) : _previewOnly = false;

  /// A detached view of settings. Rendering a preview must never save them.
  SimplifiedInterfaceController.preview(
    SimplifiedInterfaceController original, {
    required bool enabled,
    required SimpleViewPreferences preferences,
    String? account,
    List<String>? selectedIds,
  }) : _store = original._store,
       _previewOnly = true {
    _enabled = enabled;
    _preferences = preferences;
    _configured = original.configured;
    _skipPreview = original.skipPreview;
    _quickAccess
      ..clear()
      ..addAll({
        for (final entry in original._quickAccess.entries)
          entry.key: [...entry.value],
      });
    _opens
      ..clear()
      ..addAll({
        for (final entry in original._opens.entries)
          entry.key: {...entry.value},
      });
    if (account != null && selectedIds != null) {
      _quickAccess[account] = _cleanIds(selectedIds);
    }
  }

  bool get enabled => _enabled;
  SimpleViewPreferences get preferences => _preferences;
  bool get configured => _configured;
  bool get skipPreview => _skipPreview;

  Map<String, Map<String, int>> _readOpens() {
    try {
      final raw = jsonDecode(_store.getString(usageKey) ?? '{}');
      if (raw is! Map) return {};
      return {
        for (final account in raw.entries)
          if (account.key is String && account.value is Map)
            account.key as String: {
              for (final entry in (account.value as Map).entries)
                if (entry.key is String &&
                    entry.value is int &&
                    (entry.value as int) > 0)
                  entry.key as String: entry.value as int,
            },
      };
    } on FormatException {
      return {};
    }
  }

  /// Counts openings only after the user opts into frequent shortcuts.
  /// No message content, server history, or contact book is read.
  Future<void> recordConversationOpened(String account, String roomId) {
    if (!enabled || preferences.quickAccess != SimpleQuickAccess.frequent) {
      return Future.value();
    }
    final counts = _opens.putIfAbsent(account, () => {});
    counts[roomId] = ((counts[roomId] ?? 0) + 1).clamp(1, 1000000);
    final snapshot = jsonEncode(_opens);
    notifyListeners();
    return _save(() => _store.setString(usageKey, snapshot));
  }

  List<String> frequentFor(String account, List<String> recentIds) {
    final order = {for (var i = 0; i < recentIds.length; i++) recentIds[i]: i};
    final result = [...recentIds]
      ..sort((a, b) {
        final byCount = (_opens[account]?[b] ?? 0).compareTo(
          _opens[account]?[a] ?? 0,
        );
        return byCount != 0 ? byCount : order[a]!.compareTo(order[b]!);
      });
    return result.take(maxQuickAccess).toList();
  }

  /// Onboarding is transactional: answers are persisted only on Apply.
  Future<void> applyPreferences(
    SimpleViewPreferences value, {
    required bool enabled,
    required bool skipPreview,
    String? accountId,
    List<String>? quickAccessIds,
  }) {
    value = value.copyWith(quietChat: true);
    if (accountId != null && quickAccessIds != null) {
      _quickAccess[accountId] = _cleanIds(quickAccessIds);
    }
    final shortcutsSnapshot = jsonEncode(_quickAccess);
    _preferences = value;
    _configured = true;
    _enabled = enabled;
    _skipPreview = skipPreview;
    _revision++;
    final snapshot = jsonEncode(value.toJson());
    notifyListeners();
    return _save(() async {
      final profileSaved = await _store.setString(preferencesKey, snapshot);
      final enabledSaved = await _store.setBool(enabledKey, enabled);
      final previewSaved = await _store.setBool(skipPreviewKey, skipPreview);
      final shortcutsSaved =
          accountId == null ||
          quickAccessIds == null ||
          await _store.setString(quickAccessKey, shortcutsSnapshot);
      return profileSaved && enabledSaved && previewSaved && shortcutsSaved;
    });
  }

  /// Mode and profile changes increment this. Used to reject stale AI proposals
  /// and prevent Undo from overwriting a newer manual choice.
  int get revision => _revision;

  List<String> quickAccessFor(String accountId) =>
      List.unmodifiable(_quickAccess[accountId] ?? const <String>[]);

  Map<String, List<String>> _readQuickAccess() {
    try {
      final raw = jsonDecode(_store.getString(quickAccessKey) ?? '{}');
      if (raw is! Map) return {};
      return {
        for (final entry in raw.entries)
          if (entry.key is String && entry.value is List)
            entry.key as String: _cleanIds(
              (entry.value as List).whereType<String>(),
            ),
      };
    } on FormatException {
      return {};
    }
  }

  static List<String> _cleanIds(Iterable<String> ids) => ids
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet()
      .take(maxQuickAccess)
      .toList(growable: false);

  Future<void> _save(Future<bool> Function() write) {
    if (_previewOnly) throw StateError('Preview settings cannot be saved');
    // Serialize snapshots so rapid taps cannot persist an older state last.
    _writes = _writes.catchError((Object _) {}).then((_) async {
      if (!await write()) throw StateError('Unable to save simple view');
    });
    return _writes;
  }

  Future<void> setEnabled(bool value) {
    if (_enabled == value) return _writes;
    _enabled = value;
    _revision++;
    notifyListeners();
    return _save(() => _store.setBool(enabledKey, value));
  }

  Future<void> setSkipPreview(bool value) {
    _skipPreview = value;
    notifyListeners();
    return _save(() => _store.setBool(skipPreviewKey, value));
  }

  Future<void> setQuickAccess(String accountId, Iterable<String> ids) {
    if (accountId.isEmpty) throw ArgumentError.value(accountId, 'accountId');
    _quickAccess[accountId] = _cleanIds(ids);
    final snapshot = jsonEncode(_quickAccess);
    notifyListeners();
    return _save(() => _store.setString(quickAccessKey, snapshot));
  }
}

class SimplifiedInterfaceScope extends StatefulWidget {
  final SharedPreferences? store;
  final SimplifiedInterfaceController? controller;
  final Widget child;

  const SimplifiedInterfaceScope({
    super.key,
    this.store,
    this.controller,
    required this.child,
  }) : assert(store != null || controller != null);

  /// Registers a dependency so the switch, preview, home, and chat agree.
  static SimplifiedInterfaceController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_SimplifiedInherited>()
      ?.notifier;

  static bool enabledOf(BuildContext context) =>
      maybeOf(context)?.enabled ?? false;

  static bool quietChatOf(BuildContext context) {
    final controller = maybeOf(context);
    return controller != null && controller.enabled;
  }

  @override
  State<SimplifiedInterfaceScope> createState() =>
      _SimplifiedInterfaceScopeState();
}

class _SimplifiedInterfaceScopeState extends State<SimplifiedInterfaceScope> {
  late final controller =
      widget.controller ?? SimplifiedInterfaceController(widget.store!);

  @override
  Widget build(BuildContext context) =>
      _SimplifiedInherited(notifier: controller, child: widget.child);

  @override
  void dispose() {
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }
}

class _SimplifiedInherited
    extends InheritedNotifier<SimplifiedInterfaceController> {
  const _SimplifiedInherited({required super.notifier, required super.child});
}
