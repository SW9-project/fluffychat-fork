// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

import '../heuristics/heuristic.dart';
import '../model/heuristic_functions.dart';
import '../model/settings_intent_model.dart';
import 'assist_backend.dart';

/// The on-device model (FunctionGemma through LiteRT-LM) as an Assist
/// backend. It is offered the pilot's `heuristic_*` functions unchanged,
/// because the pilot model was fine-tuned on exactly those words, and it gets
/// only the prompt: never the earlier exchange or the settings.
class LocalGemmaBackend extends AssistBackend {
  final SettingsIntentModel model;
  final List<Heuristic> Function() heuristics;

  LocalGemmaBackend(this.model, {required this.heuristics});

  @override
  ValueListenable<ModelStatus> get status => model.status;

  @override
  Future<void> prepare() => model.prepare();

  @override
  Future<AssistOutcome> ask(AssistRequest request) async {
    final list = heuristics();
    final functions = HeuristicFunctions.declarationsFor(list);
    ProposedCall? call;
    ModelTiming? timing;
    if (functions.isNotEmpty) {
      call = await model.propose(request.prompt, functions);
      timing = model.lastTiming;
    }
    return AssistOutcome(
      HeuristicFunctions.interpret(call, list, request.settings),
      AssistSource.local,
      timing: timing,
    );
  }

  @override
  void dispose() => model.dispose();
}
