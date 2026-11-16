// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../accessibility_controller.dart';
import '../accessibility_settings.dart';
import '../appearance_l10n.dart';
import '../model/personalization_tools.dart';
import '../model/settings_intent_model.dart';
import '../model/tool_call_interpreter.dart';
import '../personalization_l10n.dart';
import '../simple_view_setup.dart';
import '../simplified_interface.dart';
import '../simplified_interface_l10n.dart';
import '../simplified_interface_widgets.dart';
import '../study/study_events.dart';
import '../study/study_log.dart';
import '../suggestions/suggestion.dart';
import '../suggestions/suggestion_manager.dart';
import 'assist_conversation.dart';
import 'change_preview.dart';

/// A chat the user can mean by "the chat with Maria".
class AssistChat {
  final String id;
  final String name;

  /// The other person's username in a direct chat, such as `peter123` for
  /// `@peter123:example.org`.
  final String? username;

  const AssistChat({required this.id, required this.name, this.username});

  /// The chats [query] can mean: the exact name or username if one has it,
  /// otherwise every chat whose name contains it as a word.
  static List<AssistChat> matching(List<AssistChat> chats, String query) {
    String norm(String s) => s.trim().toLowerCase();
    final q = norm(query).replaceFirst(RegExp(r'^@'), '');
    if (q.isEmpty) return const [];
    final exact = [
      for (final c in chats)
        if (norm(c.name) == q || (c.username != null && norm(c.username!) == q))
          c,
    ];
    if (exact.isNotEmpty) return exact;
    final word = RegExp('(^|\\W)${RegExp.escape(q)}', caseSensitive: false);
    return [
      for (final c in chats)
        if (word.hasMatch(c.name) || (c.username?.startsWith(q) ?? false)) c,
    ];
  }
}

/// The Assist tab: the user describes a problem with the UI, the on-device
/// model calls one of the functions it was fine-tuned on, and the tab shows
/// the change with a preview. Nothing changes until the user taps Apply, and
/// Undo is offered afterwards.
///
/// Each request carries only the exchange in progress and the last answered
/// one, in the shapes the model was trained on (see [AssistConversation]).
/// Chats and messages are never sent; chat names are matched here, on the
/// phone.
///
/// The study log records each prompt and the answer, with the
/// model's timing, when the researcher turned logging on.
class AssistView extends StatefulWidget {
  /// The on-device model, or null when the assistant is off in the current
  /// study condition.
  final SettingsIntentModel? model;
  final SuggestionManager manager;
  final AccessibilityController accessibility;
  final VoidCallback onOpenAccessibilitySettings;

  /// The functions the model was trained on.
  final Future<PersonalizationTools> tools;

  /// The current light or dark setting.
  final ThemeMode Function() themeMode;

  /// The user's chats, most recent first.
  final List<AssistChat> Function() chats;

  const AssistView({
    required this.model,
    required this.manager,
    required this.accessibility,
    required this.onOpenAccessibilitySettings,
    required this.tools,
    required this.themeMode,
    required this.chats,
    super.key,
  });

  @override
  State<AssistView> createState() => _AssistViewState();
}

enum _Outcome { applied, declined, undone }

class _Exchange {
  /// What the user typed or tapped.
  final String prompt;
  AssistResult? result;
  Suggestion? suggestion;
  _Outcome? outcome;
  bool? simpleTarget;
  bool? simpleFrom;
  int? simpleRevision;
  int? appliedRevision;

  /// The chat a one-chat change is for, as shown to the user.
  String? chatName;

  /// The user answered this exchange's question.
  bool answered = false;

  _Exchange(this.prompt);
}

class _AssistViewState extends State<AssistView> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_Exchange> _exchanges = [];
  final AssistConversation _conversation = AssistConversation();
  PersonalizationTools? _tools;
  bool _busy = false;
  ModelState? _modelState;

  @override
  void initState() {
    super.initState();
    widget.model?.status.addListener(_onModelStatus);
    widget.tools.then(
      (tools) => mounted ? setState(() => _tools = tools) : null,
      onError: (Object e, StackTrace s) =>
          Logs().e('Unable to load the assistant functions', e, s),
    );
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
    widget.model?.status.removeListener(_onModelStatus);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  _Exchange? get _last => _exchanges.lastOrNull;

  ToolCallInterpreter _interpreter(PersonalizationTools tools) =>
      ToolCallInterpreter(
        tools: tools,
        settings: widget.accessibility.settings,
        theme: widget.themeMode(),
      );

  /// What the user typed: the answer to an open question, or a new request.
  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    final last = _last;
    if (last != null &&
        !last.answered &&
        last.result is AssistClarification &&
        _conversation.awaitsAnswer) {
      last.answered = true;
      return _send(text, _conversation.answer(text), answer: true);
    }
    _closeOpen();
    await _send(text, _conversation.ask(text));
  }

  /// A new request replaces what is still open: an unanswered proposal is
  /// declined for the model (the manager logs it as superseded), an open
  /// question is left.
  void _closeOpen() {
    final last = _last;
    if (last == null) return;
    last.answered = true;
    if (last.suggestion != null &&
        last.outcome == null &&
        widget.manager.current == last.suggestion) {
      last.outcome = _Outcome.declined;
      _conversation.resolved(applied: false);
    }
  }

  Future<void> _answerOption(_Exchange exchange, String answer, String shown) {
    if (_busy || exchange.answered || !_conversation.awaitsAnswer) {
      return Future.value();
    }
    exchange.answered = true;
    return _send(shown, _conversation.answer(answer), answer: true);
  }

  Future<void> _send(
    String shown,
    List<ModelTurn> turns, {
    bool answer = false,
  }) async {
    final model = widget.model;
    final tools = _tools;
    if (model == null || tools == null) return;
    final exchange = _Exchange(shown);
    setState(() {
      _exchanges.add(exchange);
      _busy = true;
      _controller.clear();
    });
    _scrollToEnd();
    StudyLog.instance.record(AssistPrompted(shown));

    AssistResult result;
    ModelTiming? timing;
    var failed = false;
    try {
      final call = await model.propose(turns, tools.declarations);
      timing = model.lastTiming;
      if (call != null) _conversation.called(call);
      result = _interpreter(tools).interpret(call);
      if (result case AssistNeedsChat(:final call, :final chatName)) {
        result = _resolveChat(tools, exchange, call, chatName);
      }
    } catch (e, s) {
      // The app log gets the failure, never the user's words.
      Logs().w('Assistant request failed', e, s);
      result = const AssistNoSuggestion(RejectionReason.noCall);
      failed = true;
    }
    StudyLog.instance.record(
      AssistAnswered(result, timing: timing, failed: failed, answer: answer),
    );
    if (!mounted) return;
    final simpleController = SimplifiedInterfaceScope.maybeOf(context);
    final simpleTarget = switch (result) {
      AssistNotAvailable(:final call) => _simpleTarget(call),
      _ => null,
    };
    if (simpleController != null && simpleTarget != null) {
      // The trained model knows the simple view; the simplified interface
      // confirms the switch with its own preview.
      _conversation.ended();
      setState(() {
        exchange.simpleTarget = simpleTarget;
        exchange.simpleFrom = simpleController.enabled;
        exchange.simpleRevision = simpleController.revision;
        _busy = false;
      });
      StudyLog.instance.record(
        SimpleViewAction(
          'model_proposal',
          simpleController.enabled,
          simpleTarget,
        ),
      );
      _scrollToEnd();
      return;
    }
    _show(exchange, result);
    setState(() => _busy = false);
    _scrollToEnd();
  }

  /// A named chat that matches exactly one chat needs no question.
  AssistResult _resolveChat(
    PersonalizationTools tools,
    _Exchange exchange,
    ProposedCall call,
    String? chatName,
  ) {
    if (chatName == null) return AssistNeedsChat(call, null);
    final matches = AssistChat.matching(widget.chats(), chatName);
    if (matches.length != 1) return AssistNeedsChat(call, chatName);
    exchange.chatName = matches.single.name;
    return _interpreter(tools).forChat(call, matches.single.id);
  }

  void _chooseChat(_Exchange exchange, AssistChat chat) {
    final tools = _tools;
    final result = exchange.result;
    if (tools == null || exchange.answered || result is! AssistNeedsChat) {
      return;
    }
    exchange.answered = true;
    final answer = _Exchange(chat.name)..chatName = chat.name;
    final next = _interpreter(tools).forChat(result.call, chat.id);
    StudyLog.instance.record(AssistAnswered(next, answer: true));
    setState(() => _exchanges.add(answer));
    _show(answer, next);
    _scrollToEnd();
  }

  /// The simple view [call] asks for: `set_simple_mode`, or resetting it.
  static bool? _simpleTarget(ProposedCall call) => switch (call.name) {
    PersonalizationTools.setSimpleMode => switch (call.args['enabled']) {
      final bool enabled => enabled,
      _ => null,
    },
    PersonalizationTools.resetSettings
        when call.args['setting'] == 'simple_mode' =>
      false,
    _ => null,
  };

  void _offerSimpleView(SimplifiedInterfaceController controller) {
    final target = !controller.enabled;
    final text = SimplifiedInterfaceL10n.of(context);
    final exchange = _Exchange(target ? text.turnOn : text.turnOff)
      ..simpleTarget = target
      ..simpleFrom = controller.enabled
      ..simpleRevision = controller.revision;
    setState(() => _exchanges.add(exchange));
    StudyLog.instance.record(
      SimpleViewAction('quick_action_proposal', controller.enabled, target),
    );
    _scrollToEnd();
  }

  Widget _simpleAnswer(BuildContext context, _Exchange exchange) {
    final controller = SimplifiedInterfaceScope.maybeOf(context)!;
    final text = SimplifiedInterfaceL10n.of(context);
    final l10n = PersonalizationL10n.of(context);
    final target = exchange.simpleTarget!;
    final fresh = controller.revision == exchange.simpleRevision;
    final canUndo =
        exchange.outcome == _Outcome.applied &&
        controller.revision == exchange.appliedRevision;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(target ? text.turnOn : text.turnOff),
        const SizedBox(height: 8),
        Text(text.proposalInfo),
        const SizedBox(height: 12),
        SimplifiedInterfacePreview(enabled: target),
        const SizedBox(height: 12),
        if (exchange.outcome == _Outcome.undone)
          Text(l10n.changeUndone)
        else if (exchange.outcome == _Outcome.declined)
          Text(text.unchanged)
        else if (canUndo)
          TextButton.icon(
            key: const Key('assist_simple_undo'),
            icon: const Icon(Icons.undo),
            label: Text(l10n.undo),
            onPressed: () async {
              if (controller.revision != exchange.appliedRevision) return;
              await controller.setEnabled(exchange.simpleFrom!);
              StudyLog.instance.record(
                SimpleViewAction('undo', target, exchange.simpleFrom!),
              );
              if (mounted) setState(() => exchange.outcome = _Outcome.undone);
            },
          )
        else if (!fresh)
          Text(text.stale)
        else if (controller.enabled == target)
          Text(text.alreadySelected)
        else
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              OutlinedButton(
                key: const Key('assist_simple_decline'),
                onPressed: () =>
                    setState(() => exchange.outcome = _Outcome.declined),
                child: Text(l10n.noThanks),
              ),
              FilledButton(
                key: const Key('assist_simple_apply'),
                onPressed: () async {
                  if (controller.revision != exchange.simpleRevision) return;
                  final appliedRevision = await requestSimpleViewChange(
                    context,
                    controller,
                    target,
                    previewAlreadyShown: true,
                  );
                  if (appliedRevision == null || !mounted) return;
                  StudyLog.instance.record(
                    SimpleViewAction('apply', exchange.simpleFrom!, target),
                  );
                  setState(() {
                    exchange.appliedRevision = appliedRevision;
                    exchange.outcome = _Outcome.applied;
                  });
                },
                child: Text(l10n.applyChange),
              ),
            ],
          ),
      ],
    );
  }

  void _show(_Exchange exchange, AssistResult result) {
    switch (result) {
      case AssistProposal(:final call, :final change):
        final suggestion = Suggestion.userRequest(call.name, change);
        exchange.suggestion = suggestion;
        widget.manager.proposeUserRequest(suggestion);
      case AssistClarification() || AssistNeedsChat():
        // The conversation waits for the user's answer.
        break;
      default:
        _conversation.ended();
    }
    setState(() => exchange.result = result);
  }

  Future<void> _apply(_Exchange exchange) async {
    if (widget.manager.current != exchange.suggestion) return;
    await widget.manager.apply();
    _conversation.resolved(applied: true);
    setState(() => exchange.outcome = _Outcome.applied);
  }

  void _decline(_Exchange exchange) {
    if (widget.manager.current != exchange.suggestion) return;
    widget.manager.notNow();
    _conversation.resolved(applied: false);
    setState(() => exchange.outcome = _Outcome.declined);
  }

  Future<void> _undo(_Exchange exchange) async {
    if (widget.manager.applied?.suggestion != exchange.suggestion) return;
    await widget.manager.undoApplied();
    if (exchange == _last) _conversation.undone();
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
        ModelState.ready => _conversationView(context),
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

  Widget _conversationView(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = PersonalizationL10n.of(context);
    final ready = _tools != null && !_busy;
    return Column(
      children: [
        Expanded(
          child: ListenableBuilder(
            listenable: widget.manager,
            builder: (context, _) => ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                _AssistantBubble(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.assistIntro),
                      if (SimplifiedInterfaceScope.maybeOf(context)
                          case final controller?)
                        TextButton.icon(
                          key: const Key('assist_simple_view'),
                          onPressed: _busy
                              ? null
                              : () => _offerSimpleView(controller),
                          icon: const Icon(Icons.view_agenda_outlined),
                          label: Text(
                            controller.enabled
                                ? SimplifiedInterfaceL10n.of(context).turnOff
                                : SimplifiedInterfaceL10n.of(context).turnOn,
                          ),
                        ),
                    ],
                  ),
                ),
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
                    enabled: ready,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(hintText: l10n.askHint),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: const Key('assist_send'),
                  onPressed: ready ? _submit : null,
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
    if (exchange.simpleTarget != null) return _simpleAnswer(context, exchange);
    final l10n = PersonalizationL10n.of(context);
    final words = AppearanceL10n.of(context);
    final settingsLink = TextButton.icon(
      key: const Key('assist_open_settings'),
      onPressed: widget.onOpenAccessibilitySettings,
      icon: const Icon(Icons.accessibility_new_outlined),
      label: Text(l10n.openAccessibilitySettings),
    );
    Widget withSettingsLink(String text, {Key? key}) => Column(
      key: key,
      crossAxisAlignment: .start,
      children: [Text(text), settingsLink],
    );
    switch (exchange.result) {
      case null:
        return Row(
          mainAxisSize: .min,
          children: [
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator.adaptive(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(l10n.thinking),
          ],
        );
      case AssistNoSuggestion():
        return withSettingsLink(
          l10n.noSuggestion,
          key: const Key('assist_no_suggestion'),
        );
      case AssistNoAction():
        return withSettingsLink(
          words.noAction,
          key: const Key('assist_no_action'),
        );
      case AssistNotAvailable():
        return Text(words.notAvailable, key: const Key('assist_not_available'));
      case AssistUnchanged(:final reason, :final category):
        return withSettingsLink(
          reason == UnchangedReason.atLimit && category != null
              ? l10n.alreadyAtLimit(l10n.categoryTitles[category]!)
              : words.alreadySet,
          key: const Key('assist_unchanged'),
        );
      case AssistClarification(:final options):
        return _clarification(context, exchange, options);
      case AssistNeedsChat(:final chatName):
        return _chatChoice(context, exchange, chatName);
      case AssistProposal(:final call, :final change):
        return _proposal(context, exchange, call, change, settingsLink);
    }
  }

  Widget _clarification(
    BuildContext context,
    _Exchange exchange,
    List<String> options,
  ) {
    final words = AppearanceL10n.of(context);
    final open = !exchange.answered && !_busy;
    // One function: only its details are unclear, so the choices are the
    // details, sent as the user's own words.
    final single = options.length == 1;
    final replies = single
        ? AppearanceL10n.quickReplies(options.single)
        : options;
    return Column(
      key: const Key('assist_clarification'),
      crossAxisAlignment: .start,
      children: [
        Text(
          single
              ? '${words.functionTitles[options.single]}: ${words.clarifyOne}'
              : words.clarifyMany,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final reply in replies)
              ActionChip(
                key: Key('assist_option_$reply'),
                label: Text(
                  (single
                          ? words.replyLabels[reply]
                          : words.functionTitles[reply]) ??
                      reply,
                ),
                onPressed: open
                    ? () => _answerOption(
                        exchange,
                        reply,
                        (single
                                ? words.replyLabels[reply]
                                : words.functionTitles[reply]) ??
                            reply,
                      )
                    : null,
              ),
          ],
        ),
      ],
    );
  }

  Widget _chatChoice(
    BuildContext context,
    _Exchange exchange,
    String? chatName,
  ) {
    final words = AppearanceL10n.of(context);
    final all = widget.chats();
    final matches = chatName == null
        ? const <AssistChat>[]
        : AssistChat.matching(all, chatName);
    final shown = (matches.isNotEmpty ? matches : all).take(8).toList();
    final open = !exchange.answered && !_busy;
    return Column(
      key: const Key('assist_which_chat'),
      crossAxisAlignment: .start,
      children: [
        Text(words.whichChat(chatName)),
        const SizedBox(height: 8),
        if (shown.isEmpty)
          Text(words.noChats)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final chat in shown)
                ActionChip(
                  key: Key('assist_chat_${chat.id}'),
                  label: Text(chat.name),
                  onPressed: open ? () => _chooseChat(exchange, chat) : null,
                ),
            ],
          ),
      ],
    );
  }

  Widget _proposal(
    BuildContext context,
    _Exchange exchange,
    ProposedCall call,
    SettingsChange change,
    Widget settingsLink,
  ) {
    final l10n = PersonalizationL10n.of(context);
    final words = AppearanceL10n.of(context);
    final suggestion = exchange.suggestion!;
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
          Expanded(child: Text(_applied(context, change))),
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
        _Outcome.applied => _applied(context, change),
        _Outcome.undone => l10n.changeUndone,
        _Outcome.declined || null => l10n.notChanged,
      });
    }
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Text(_describe(words, call, exchange.chatName)),
        const SizedBox(height: 12),
        ChangePreview(change: change),
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

  String _applied(BuildContext context, SettingsChange change) {
    final l10n = PersonalizationL10n.of(context);
    final category = change.onlyCategory;
    if (category == null) return AppearanceL10n.of(context).applied;
    return l10n.changedTo(
      l10n.categoryTitles[category]!,
      change.to
          .effective(category)
          .toStringAsFixed(category.step < 0.1 ? 2 : 1),
    );
  }

  /// The question above the preview, from the call itself.
  static String _describe(
    AppearanceL10n words,
    ProposedCall call,
    String? chat,
  ) {
    final args = call.args;
    bool up(String word) => args['direction'] == word;
    bool on() => args['enabled'] == true || args['enabled'] == 'true';
    return switch (call.name) {
      PersonalizationTools.changeTextSize when chat != null =>
        words.chatTextSize(chat, up('bigger')),
      PersonalizationTools.changeTextSize => words.textSize(
        switch (args['target']) {
          'messages' => ScaleCategory.messageText,
          'chat_list' => ScaleCategory.chatListText,
          'titles' => ScaleCategory.titleText,
          'message_input' => ScaleCategory.inputText,
          _ => ScaleCategory.text,
        },
        up('bigger'),
      ),
      PersonalizationTools.changeButtonSize => words.buttonSize(
        AccessibleButton.values
            .where((b) => b.name == args['button'])
            .firstOrNull,
        up('bigger'),
      ),
      PersonalizationTools.changeSpacing => words.spacing(up('more')),
      PersonalizationTools.changeAvatarSize => words.avatarSize(up('bigger')),
      PersonalizationTools.setButtonLabels => words.toggle(
        AccessibilityToggle.buttonLabels,
        on(),
      ),
      PersonalizationTools.setHighContrast => words.toggle(
        AccessibilityToggle.highContrast,
        on(),
      ),
      PersonalizationTools.setTheme => words.theme(switch (args['mode']) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        _ => ThemeMode.system,
      }),
      _ => words.reset(args['setting'] as String?),
    };
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
