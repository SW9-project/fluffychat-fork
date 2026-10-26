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
import 'signals/interaction_monitor.dart';
import 'suggestions/suggestion_card.dart';
import 'suggestions/suggestion_manager.dart';

/// Watches interactions and shows heuristic suggestions above the app. Works
/// without any model. If the heuristics file is missing or broken, the app
/// simply shows no suggestions.
class PersonalizationLayer extends StatefulWidget {
  static const heuristicsAsset = 'assets/personalization_heuristics.json';

  final Widget child;

  const PersonalizationLayer({required this.child, super.key});

  @override
  State<PersonalizationLayer> createState() => _PersonalizationLayerState();
}

class _PersonalizationLayerState extends State<PersonalizationLayer> {
  SuggestionManager? _manager;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = _manager;
    if (manager == null) return widget.child;
    return InteractionMonitor(
      config: manager.config.signals,
      onSignal: manager.addSignal,
      child: Stack(
        fit: StackFit.expand,
        children: [widget.child, SuggestionCard(manager)],
      ),
    );
  }
}
