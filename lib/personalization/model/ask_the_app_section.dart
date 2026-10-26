// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../accessibility_controller.dart';
import '../personalization_l10n.dart';
import '../suggestions/suggestion.dart';
import '../suggestions/suggestion_manager.dart';
import 'settings_call_validator.dart';
import 'settings_intent_model.dart';

/// Lets the user describe a problem in their own words. The on-device model
/// proposes a settings change, which is validated and then shown on the
/// normal suggestion card for confirmation. Hidden when the model cannot run.
class AskTheAppSection extends StatefulWidget {
  final SettingsIntentModel model;
  final SuggestionManager manager;
  final AccessibilityController accessibility;

  const AskTheAppSection({
    required this.model,
    required this.manager,
    required this.accessibility,
    super.key,
  });

  @override
  State<AskTheAppSection> createState() => _AskTheAppSectionState();
}

class _AskTheAppSectionState extends State<AskTheAppSection> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  String? _feedback;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    final l10n = PersonalizationL10n.of(context);
    final language = Localizations.localeOf(context).languageCode;
    setState(() {
      _busy = true;
      _feedback = null;
    });
    String? feedback;
    try {
      final call = await widget.model.propose(text);
      final result = SettingsCallValidator.validate(
        call,
        widget.accessibility.settings,
      );
      switch (result) {
        case ValidCall(:final category, :final from, :final to):
          widget.manager.proposeUserRequest(
            Suggestion(
              id: Suggestion.modelRequestId,
              descriptions: {
                'en': l10n.youWrote(text),
                language: l10n.youWrote(text),
              },
              cooldown: Duration.zero,
              category: category,
              from: from,
              to: to,
            ),
          );
          _controller.clear();
        case RejectedCall(
          reason: RejectionReason.alreadyAtLimit,
          :final category?,
        ):
          feedback = l10n.alreadyAtLimit(l10n.categoryTitles[category]!);
        case RejectedCall():
          feedback = l10n.didNotCatchThat;
      }
    } catch (e, s) {
      // The user's words are not logged, only the failure.
      Logs().w('On-device model request failed', e, s);
      feedback = l10n.didNotCatchThat;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _feedback = feedback;
    });
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ModelStatus>(
    valueListenable: widget.model.status,
    builder: (context, status, _) {
      if (status.state == ModelState.unavailable) {
        return const SizedBox.shrink();
      }
      final theme = Theme.of(context);
      final l10n = PersonalizationL10n.of(context);
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withAlpha(96),
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        ),
        child: Column(
          crossAxisAlignment: .stretch,
          mainAxisSize: .min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.askTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(l10n.askDescription),
            const SizedBox(height: 12),
            ..._body(context, status, l10n),
          ],
        ),
      );
    },
  );

  List<Widget> _body(
    BuildContext context,
    ModelStatus status,
    PersonalizationL10n l10n,
  ) {
    switch (status.state) {
      case ModelState.unavailable:
        return const [];
      case ModelState.notPrepared:
        return [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const Key('ask_setup'),
              onPressed: widget.model.prepare,
              child: Text(l10n.askSetup),
            ),
          ),
        ];
      case ModelState.preparing:
        final progress = status.progress;
        return [
          LinearProgressIndicator(
            value: progress == null ? null : progress / 100,
          ),
          const SizedBox(height: 8),
          Text(l10n.askSettingUp(progress ?? 0)),
        ];
      case ModelState.failed:
        return [
          Text(l10n.askFailed),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: widget.model.prepare,
              child: Text(l10n.tryAgain),
            ),
          ),
        ];
      case ModelState.ready:
        return [
          TextField(
            key: const Key('ask_input'),
            controller: _controller,
            enabled: !_busy,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _ask(),
            decoration: InputDecoration(hintText: l10n.askHint),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _feedback == null
                    ? const SizedBox.shrink()
                    : Text(
                        _feedback!,
                        key: const Key('ask_feedback'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              _busy
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                    )
                  : FilledButton.icon(
                      key: const Key('ask_send'),
                      onPressed: _ask,
                      icon: const Icon(Icons.send),
                      label: Text(l10n.ask),
                    ),
            ],
          ),
        ];
    }
  }
}
