// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'accessibility_controller.dart';
import 'accessibility_scope.dart';
import 'heuristics/heuristic.dart';
import 'study/study_events.dart';
import 'study/study_log.dart';
import 'suggestions/suggestion_manager.dart';

/// Holds the app-wide [SuggestionManager] and the heuristics file, and
/// starts the study log (Phase 5), which records nothing until the researcher
/// turns it on.
///
/// Since Phase 3b nothing here suggests a change on its own: interaction
/// signals and automatic heuristic evaluation are disconnected, and changes
/// are only proposed in the Assist tab after the user asks. The on-device
/// model lives in the Assist tab too, not here.
class PersonalizationLayer extends StatefulWidget {
  static const heuristicsAsset = 'assets/personalization_heuristics.json';

  final Widget child;

  const PersonalizationLayer({required this.child, super.key});

  /// The suggestion manager, or null outside the layer.
  static SuggestionManager? maybeManagerOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<_PersonalizationInherited>()
      ?.manager;

  @override
  State<PersonalizationLayer> createState() => _PersonalizationLayerState();
}

class _PersonalizationLayerState extends State<PersonalizationLayer> {
  SuggestionManager? _manager;
  StreamSubscription<SettingsCommit>? _commits;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_manager != null) return;
    final accessibility = AccessibilityScope.maybeControllerOf(context);
    if (accessibility == null) return;
    StudyLog.start();
    _commits = accessibility.commits.listen(
      (commit) => StudyLog.instance.record(SettingsChanged(commit)),
    );
    _manager = SuggestionManager(
      accessibility: accessibility,
      store: AppSettings.store,
    );
    _loadHeuristics();
  }

  Future<void> _loadHeuristics() async {
    try {
      final json = jsonDecode(
        await rootBundle.loadString(PersonalizationLayer.heuristicsAsset),
      );
      final config = HeuristicsConfig.fromJson(
        json as Map<String, Object?>,
        onError: (e) => Logs().w('Skipping invalid heuristic', e),
      );
      if (!mounted) return;
      setState(() => _manager!.config = config);
    } catch (e, s) {
      Logs().w('Unable to load heuristics, the assistant has none', e, s);
    }
  }

  @override
  void dispose() {
    _commits?.cancel();
    _manager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = _manager;
    if (manager == null) return widget.child;
    return _PersonalizationInherited(manager: manager, child: widget.child);
  }
}

class _PersonalizationInherited extends InheritedWidget {
  final SuggestionManager manager;

  const _PersonalizationInherited({
    required this.manager,
    required super.child,
  });

  @override
  bool updateShouldNotify(_PersonalizationInherited oldWidget) =>
      manager != oldWidget.manager;
}
