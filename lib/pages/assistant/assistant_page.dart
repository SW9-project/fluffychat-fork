// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/personalization/accessibility_scope.dart';
import 'package:fluffychat/personalization/assist/assist_view.dart';
import 'package:fluffychat/personalization/model/emulator_host_model.dart';
import 'package:fluffychat/personalization/model/function_gemma_model.dart';
import 'package:fluffychat/personalization/model/personalization_tools.dart';
import 'package:fluffychat/personalization/model/settings_intent_model.dart';
import 'package:fluffychat/personalization/personalization_layer.dart';
import 'package:fluffychat/personalization/study/study_events.dart';
import 'package:fluffychat/personalization/study/study_log.dart';
import 'package:fluffychat/personalization/study/study_settings.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/layouts/main_navigation_bar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/theme_builder.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

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
  final Future<PersonalizationTools> _tools = PersonalizationTools.load();

  @override
  void initState() {
    super.initState();
    final condition = StudySettings.instance.value.condition;
    StudyLog.instance.record(AssistOpened(condition));
    if (condition == StudyCondition.assist) {
      _model = EmulatorHostModel.enabled
          ? EmulatorHostModel()
          : FunctionGemmaModel();
    }
  }

  @override
  void dispose() {
    _model?.dispose();
    super.dispose();
  }

  /// The chats a request can name, matched on the phone: the model never
  /// sees them.
  static List<AssistChat> _chats(BuildContext context) {
    final locals = MatrixLocals(L10n.of(context));
    return [
      for (final room in Matrix.of(context).client.rooms)
        if (!room.isSpace && room.membership == Membership.join)
          AssistChat(
            id: room.id,
            name: room.getLocalizedDisplayname(locals),
            username: room.directChatMatrixID?.localpart,
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final manager = PersonalizationLayer.maybeManagerOf(context);
    final accessibility = AccessibilityScope.maybeControllerOf(context);
    return MainNavigationBarInsets(
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(L10n.of(context).assistant),
              // Debug builds only: the model runs on the developer's computer.
              if (EmulatorHostModel.enabled)
                Text(
                  'Model on this computer',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ],
          ),
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
                tools: _tools,
                themeMode: () => ThemeController.of(context).themeMode,
                chats: () => _chats(context),
              ),
      ),
    );
  }
}
