// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../accessibility_controller.dart';
import '../heuristics/heuristic.dart';
import '../model/heuristic_functions.dart';
import '../model/settings_call_validator.dart';
import '../model/settings_intent_model.dart';
import '../personalization_l10n.dart';
import '../study/study_events.dart';
import '../study/study_log.dart';
import '../suggestions/suggestion.dart';
import '../suggestions/suggestion_manager.dart';
import 'change_preview.dart';

/// The Assist tab: the user describes a problem with the UI, the on-device
/// model picks the heuristic that fits, and the tab shows its change with a
/// preview. Nothing changes until the user taps Apply, and Undo is offered
/// afterwards.
///
/// Each prompt is sent to the model on its own, together with the heuristic
/// functions. Earlier prompts, chats and messages are never sent.
///
/// The study log (Phase 5) records each prompt and the answer, with the
/// model's timing, when the researcher turned logging on.
class AssistView extends StatefulWidget {
  /// The on-device model, or null when the assistant is off in the current
  /// study condition.
  final SettingsIntentModel? model;
  final SuggestionManager manager;
  final AccessibilityController accessibility;
  final VoidCallback onOpenAccessibilitySettings;

  const AssistView({
    required this.model,
    required this.manager,
    required this.accessibility,
    required this.onOpenAccessibilitySettings,
    super.key,
  });

  @override
  State<AssistView> createState() => _AssistViewState();
}

enum _Outcome { applied, declined, undone }

class _Exchange {
  final String prompt;
  AssistResult? result;
  Suggestion? suggestion;
  _Outcome? outcome;

  _Exchange(this.prompt);
}

class _AssistViewState extends State<AssistView> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_Exchange> _exchanges = [];
  bool _busy = false;
  ModelState? _modelState;

  List<Heuristic> get _heuristics => widget.manager.config.heuristics;

  @override
  void initState() {
    super.initState();
    widget.model?.status.addListener(_onModelStatus);
  }

  @override
  void didUpdateWidget(AssistView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model == widget.model) return;
    oldWidget.model?.status.removeListener(_onModelStatus);
    widget.model?.status.addListener(_onModelStatus);
  }

  /// Records when the model changes state, not every progress update.
  void _onModelStatus() {
    final state = widget.model?.status.value.state;
    if (state == null || state == _modelState) return;
    _modelState = state;
    StudyLog.instance.record(AssistModelState(state));
  }

  @override
  void dispose() {
    // A proposal left open here has nowhere else to be answered.
    final open = widget.manager.current;
    if (open != null && _exchanges.any((e) => e.suggestion == open)) {
      widget.manager.abandonOpen();
    }
    widget.model?.status.removeListener(_onModelStatus);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final model = widget.model;
    final text = _controller.text.trim();
    if (model == null || text.isEmpty || _busy) return;
    final exchange = _Exchange(text);
    setState(() {
      _exchanges.add(exchange);
      _busy = true;
      _controller.clear();
    });
    _scrollToEnd();
    StudyLog.instance.record(AssistPrompted(text));

    AssistResult result;
    ModelTiming? timing;
    var failed = false;
    try {
      final functions = HeuristicFunctions.declarationsFor(_heuristics);
      ProposedCall? call;
      if (functions.isNotEmpty) {
        call = await model.propose(text, functions);
        timing = model.lastTiming;
      }
      result = HeuristicFunctions.interpret(
        call,
        _heuristics,
        widget.accessibility.settings,
      );
    } catch (e, s) {
      // The app log gets the failure, never the user's words.
      Logs().w('Assistant request failed', e, s);
      result = const AssistNoSuggestion(RejectionReason.noCall);
      failed = true;
    }
    StudyLog.instance.record(
      AssistAnswered(result, timing: timing, failed: failed),
    );
    if (!mounted) return;
    if (result case AssistProposal(:final heuristic, :final from, :final to)) {
      final suggestion = Suggestion.fromHeuristic(
        heuristic,
        from: from,
        to: to,
      );
      exchange.suggestion = suggestion;
      widget.manager.proposeUserRequest(suggestion);
    }
    setState(() {
      exchange.result = result;
      _busy = false;
    });
    _scrollToEnd();
  }

  Future<void> _apply(_Exchange exchange) async {
    if (widget.manager.current != exchange.suggestion) return;
    await widget.manager.apply();
    setState(() => exchange.outcome = _Outcome.applied);
  }

  void _decline(_Exchange exchange) {
    if (widget.manager.current != exchange.suggestion) return;
    widget.manager.notNow();
    setState(() => exchange.outcome = _Outcome.declined);
  }

  Future<void> _undo(_Exchange exchange) async {
    if (widget.manager.applied?.suggestion != exchange.suggestion) return;
    await widget.manager.undoApplied();
    setState(() => exchange.outcome = _Outcome.undone);
  }

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
    );
  });

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    if (model == null) return _statusPanel(context, null);
    return ValueListenableBuilder<ModelStatus>(
      valueListenable: model.status,
      builder: (context, status, _) => switch (status.state) {
        ModelState.ready => _conversation(context),
        _ => _statusPanel(context, status),
      },
    );
  }

  /// [status] is null when the assistant is off in this study condition.
  Widget _statusPanel(BuildContext context, ModelStatus? status) {
    final theme = Theme.of(context);
    final l10n = PersonalizationL10n.of(context);
    final List<Widget> children;
    switch (status?.state) {
      case null || ModelState.unavailable:
        children = [
          Text(
            status == null ? l10n.assistOff : l10n.assistUnavailable,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('assist_open_settings'),
            onPressed: widget.onOpenAccessibilitySettings,
            icon: const Icon(Icons.accessibility_new_outlined),
            label: Text(l10n.openAccessibilitySettings),
          ),
        ];
      case ModelState.notPrepared:
        children = [
          Text(l10n.assistIntro, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(l10n.assistSetupInfo, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('assist_setup'),
            onPressed: widget.model?.prepare,
            child: Text(l10n.askSetup),
          ),
        ];
      case ModelState.preparing:
        final progress = status?.progress;
        children = [
          LinearProgressIndicator(
            value: progress == null ? null : progress / 100,
          ),
          const SizedBox(height: 8),
          Text(l10n.askSettingUp(progress ?? 0)),
        ];
      case ModelState.failed:
        children = [
          Text(l10n.askFailed, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          TextButton(
            key: const Key('assist_retry'),
            onPressed: widget.model?.prepare,
            child: Text(l10n.tryAgain),
          ),
        ];
      case ModelState.ready:
        children = const [];
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: .min,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _conversation(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = PersonalizationL10n.of(context);
    return Column(
      children: [
        Expanded(
          child: ListenableBuilder(
            listenable: widget.manager,
            builder: (context, _) => ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                _AssistantBubble(child: Text(l10n.assistIntro)),
                for (final exchange in _exchanges) ...[
                  _UserBubble(text: exchange.prompt),
                  _AssistantBubble(child: _answer(context, exchange)),
                ],
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('assist_input'),
                    controller: _controller,
                    enabled: !_busy,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _ask(),
                    decoration: InputDecoration(hintText: l10n.askHint),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: const Key('assist_send'),
                  onPressed: _busy ? null : _ask,
                  tooltip: l10n.ask,
                  icon: const Icon(Icons.send),
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _answer(BuildContext context, _Exchange exchange) {
    final l10n = PersonalizationL10n.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final settingsLink = TextButton.icon(
      key: const Key('assist_open_settings'),
      onPressed: widget.onOpenAccessibilitySettings,
      icon: const Icon(Icons.accessibility_new_outlined),
      label: Text(l10n.openAccessibilitySettings),
    );
    switch (exchange.result) {
      case null:
        return Row(
          mainAxisSize: .min,
          children: [
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(l10n.thinking),
          ],
        );
      case AssistNoSuggestion():
        return Column(
          key: const Key('assist_no_suggestion'),
          crossAxisAlignment: .start,
          children: [Text(l10n.noSuggestion), settingsLink],
        );
      case AssistAtLimit(:final category):
        return Column(
          crossAxisAlignment: .start,
          children: [
            Text(l10n.alreadyAtLimit(l10n.categoryTitles[category]!)),
            settingsLink,
          ],
        );
      case AssistProposal(
        :final heuristic,
        :final category,
        :final from,
        :final to,
      ):
        final suggestion = exchange.suggestion!;
        final changed = l10n.changedTo(
          l10n.categoryTitles[category]!,
          to.toStringAsFixed(1),
        );
        final Widget actions;
        if (widget.manager.current == suggestion) {
          actions = Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton(
                key: const Key('assist_no_thanks'),
                onPressed: () => _decline(exchange),
                child: Text(l10n.noThanks),
              ),
              FilledButton(
                key: const Key('assist_apply'),
                onPressed: () => _apply(exchange),
                child: Text(l10n.applyChange),
              ),
            ],
          );
        } else if (widget.manager.applied?.suggestion == suggestion) {
          actions = Row(
            children: [
              Expanded(child: Text(changed)),
              TextButton.icon(
                key: const Key('assist_undo'),
                onPressed: () => _undo(exchange),
                icon: const Icon(Icons.undo),
                label: Text(l10n.undo),
              ),
            ],
          );
        } else {
          actions = Text(switch (exchange.outcome) {
            _Outcome.applied => changed,
            _Outcome.undone => l10n.changeUndone,
            _Outcome.declined || null => l10n.notChanged,
          });
        }
        return Column(
          crossAxisAlignment: .stretch,
          children: [
            Text(heuristic.description(language)),
            const SizedBox(height: 12),
            ChangePreview(category: category, from: from, to: to),
            const SizedBox(height: 12),
            actions,
            // Undo here lasts only a moment and goes with the tab.
            if (exchange.outcome == _Outcome.applied) ...[
              const SizedBox(height: 8),
              Text(l10n.changeBackInSettings),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: settingsLink,
              ),
            ],
          ],
        );
    }
  }
}

class _UserBubble extends StatelessWidget {
  final String text;

  const _UserBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(left: 48, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.bubbleColor,
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        ),
        child: Text(text, style: TextStyle(color: theme.onBubbleColor)),
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  final Widget child;

  const _AssistantBubble({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(right: 24, bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        ),
        child: child,
      ),
    );
  }
}
