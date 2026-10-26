// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'accessibility_scope.dart';
import 'heuristics/heuristic.dart';
import 'model/function_gemma_model.dart';
import 'model/settings_intent_model.dart';
import 'signals/interaction_monitor.dart';
import 'suggestions/suggestion_card.dart';
import 'suggestions/suggestion_manager.dart';

/// Watches interactions and shows suggestions above the app, from heuristics
/// and from the user's own requests through the on-device model. Works without
/// the model. If the heuristics file is missing or broken, the app simply
/// shows no heuristic suggestions.
class PersonalizationLayer extends StatefulWidget {
  static const heuristicsAsset = 'assets/personalization_heuristics.json';

  final Widget child;

  const PersonalizationLayer({required this.child, super.key});

  /// The suggestion manager and the on-device model, or null outside the
  /// layer.
  static ({SuggestionManager manager, SettingsIntentModel model})? maybeOf(
    BuildContext context,
  ) {
    final inherited = context
        .getInheritedWidgetOfExactType<_PersonalizationInherited>();
    if (inherited == null) return null;
    return (manager: inherited.manager, model: inherited.model);
  }

  @override
  State<PersonalizationLayer> createState() => _PersonalizationLayerState();
}

class _PersonalizationLayerState extends State<PersonalizationLayer> {
  SuggestionManager? _manager;
  SettingsIntentModel? _model;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_manager != null) return;
    final accessibility = AccessibilityScope.maybeControllerOf(context);
    if (accessibility == null) return;
    _manager = SuggestionManager(
      accessibility: accessibility,
      store: AppSettings.store,
    );
    _model = FunctionGemmaModel();
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
      Logs().w('Unable to load heuristics, no suggestions will show', e, s);
    }
  }

  @override
  void dispose() {
    _manager?.dispose();
    _model?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = _manager;
    final model = _model;
    if (manager == null || model == null) return widget.child;
    return _PersonalizationInherited(
      manager: manager,
      model: model,
      child: InteractionMonitor(
        config: manager.config.signals,
        onSignal: manager.addSignal,
        child: Stack(
          fit: StackFit.expand,
          children: [widget.child, SuggestionCard(manager)],
        ),
      ),
    );
  }
}

class _PersonalizationInherited extends InheritedWidget {
  final SuggestionManager manager;
  final SettingsIntentModel model;

  const _PersonalizationInherited({
    required this.manager,
    required this.model,
    required super.child,
  });

  @override
  bool updateShouldNotify(_PersonalizationInherited oldWidget) =>
      manager != oldWidget.manager || model != oldWidget.model;
}
