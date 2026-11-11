// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/personalization/accessibility_scope.dart';
import 'package:fluffychat/personalization/assist/assist_backend.dart';
import 'package:fluffychat/personalization/assist/assist_view.dart';
import 'package:fluffychat/personalization/assist/groq_assist_backend.dart';
import 'package:fluffychat/personalization/assist/hybrid_assist_backend.dart';
import 'package:fluffychat/personalization/assist/local_gemma_backend.dart';
import 'package:fluffychat/personalization/assist/prompt_redactor.dart';
import 'package:fluffychat/personalization/heuristics/heuristic.dart';
import 'package:fluffychat/personalization/model/function_gemma_model.dart';
import 'package:fluffychat/personalization/personalization_layer.dart';
import 'package:fluffychat/personalization/study/study_events.dart';
import 'package:fluffychat/personalization/study/study_log.dart';
import 'package:fluffychat/personalization/study/study_settings.dart';
import 'package:fluffychat/widgets/layouts/main_navigation_bar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key});

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  /// The assistant exists only while this tab is open, and only in the
  /// Assist study condition. This page is its only owner, so no other part
  /// of the app can reach a model.
  AssistBackend? _backend;

  /// Why the online assistant is off in this build, for developers. Shown
  /// only in debug builds.
  String? _devWarning;

  List<Heuristic> _heuristics() =>
      PersonalizationLayer.maybeManagerOf(context)?.config.heuristics ??
      const [];

  @override
  void initState() {
    super.initState();
    final condition = StudySettings.instance.value.condition;
    StudyLog.instance.record(AssistOpened(condition));
    if (condition == StudyCondition.assist) _backend = _createBackend();
  }

  AssistBackend _createBackend() {
    final local = LocalGemmaBackend(
      FunctionGemmaModel(),
      heuristics: _heuristics,
    );
    final (:config, :missing) = GroqConfig.fromEnvironment();
    if (config == null) {
      if (kDebugMode) {
        _devWarning = missing;
        Logs().w('Assist: $missing');
      }
      return HybridAssistBackend(local: local);
    }
    final client = Matrix.of(context).client;
    return HybridAssistBackend(
      local: local,
      remote: GroqAssistBackend(
        config,
        heuristics: _heuristics,
        // The names are only compared with the prompt on this phone, so
        // they can be removed from it; they are never sent.
        redactor: PromptRedactor(knownNames: () => _knownNames(client)),
      ),
    );
  }

  /// Room names and the display names of DM partners, room heroes and the
  /// user, as far as they are already in memory. Nothing is fetched.
  static Iterable<String> _knownNames(Client client) sync* {
    final me = client.userID;
    for (final room in client.rooms) {
      yield room.name;
      for (final id in {
        ...?room.summary.mHeroes,
        ?room.directChatMatrixID,
        ?me,
      }) {
        final name = room
            .getState(EventTypes.RoomMember, id)
            ?.asUser(room)
            .displayName;
        if (name != null) yield name;
      }
    }
  }

  @override
  void dispose() {
    _backend?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = PersonalizationLayer.maybeManagerOf(context);
    final accessibility = AccessibilityScope.maybeControllerOf(context);
    return MainNavigationBarInsets(
      child: Scaffold(
        appBar: AppBar(
          title: Text(L10n.of(context).assistant),
          automaticallyImplyLeading: false,
        ),
        body: manager == null || accessibility == null
            ? const SizedBox.expand()
            : AssistView(
                backend: _backend,
                manager: manager,
                accessibility: accessibility,
                devWarning: _devWarning,
                onOpenAccessibilitySettings: () =>
                    context.go('/rooms/settings/accessibility'),
              ),
      ),
    );
  }
}
