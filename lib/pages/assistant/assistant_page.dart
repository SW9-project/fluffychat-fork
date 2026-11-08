// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/personalization/accessibility_scope.dart';
import 'package:fluffychat/personalization/assist/assist_backend.dart';
import 'package:fluffychat/personalization/assist/assist_view.dart';
import 'package:fluffychat/personalization/assist/hybrid_assist_backend.dart';
import 'package:fluffychat/personalization/assist/local_gemma_backend.dart';
import 'package:fluffychat/personalization/assist/remote_assist_backend.dart';
import 'package:fluffychat/personalization/heuristics/heuristic.dart';
import 'package:fluffychat/personalization/model/function_gemma_model.dart';
import 'package:fluffychat/personalization/personalization_layer.dart';
import 'package:fluffychat/personalization/study/study_events.dart';
import 'package:fluffychat/personalization/study/study_log.dart';
import 'package:fluffychat/personalization/study/study_settings.dart';
import 'package:fluffychat/widgets/layouts/main_navigation_bar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

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
    final endpoint = RemoteAssistBackend.configuredEndpoint();
    final client = Matrix.of(context).client;
    final userId = client.userID;
    if (endpoint == null || userId == null) {
      return HybridAssistBackend(local: local);
    }
    return HybridAssistBackend(
      local: local,
      remote: RemoteAssistBackend(
        endpoint: endpoint,
        heuristics: _heuristics,
        // An OpenID token only proves who the user is to our proxy; the
        // Matrix access token never leaves the app.
        token: OpenIdTokenSource(() async {
          final credentials = await client.requestOpenIdToken(userId, {});
          return (
            token: credentials.accessToken,
            expiresIn: Duration(seconds: credentials.expiresIn),
          );
        }),
      ),
    );
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
                onOpenAccessibilitySettings: () =>
                    context.go('/rooms/settings/accessibility'),
              ),
      ),
    );
  }
}
