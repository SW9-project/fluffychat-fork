// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/personalization/accessibility_scope.dart';
import 'package:fluffychat/personalization/assist/assist_view.dart';
import 'package:fluffychat/personalization/model/function_gemma_model.dart';
import 'package:fluffychat/personalization/model/settings_intent_model.dart';
import 'package:fluffychat/personalization/personalization_layer.dart';
import 'package:fluffychat/personalization/study/study_events.dart';
import 'package:fluffychat/personalization/study/study_log.dart';
import 'package:fluffychat/personalization/study/study_settings.dart';
import 'package:fluffychat/widgets/layouts/main_navigation_bar.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key});

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  /// The on-device model exists only while this tab is open, and only in
  /// the Assist study condition. It is the only owner, so no other part of
  /// the app can reach it.
  SettingsIntentModel? _model;

  @override
  void initState() {
    super.initState();
    final condition = StudySettings.instance.value.condition;
    StudyLog.instance.record(AssistOpened(condition));
    if (condition == StudyCondition.assist) _model = FunctionGemmaModel();
  }

  @override
  void dispose() {
    _model?.dispose();
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
                model: _model,
                manager: manager,
                accessibility: accessibility,
                onOpenAccessibilitySettings: () =>
                    context.go('/rooms/settings/accessibility'),
              ),
      ),
    );
  }
}
