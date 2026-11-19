// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../accessibility_controller.dart';
import '../accessibility_settings.dart';
import '../appearance_l10n.dart';
import '../assistant_tutorial.dart';
import '../assistant_tutorial_l10n.dart';
import '../model/app_change.dart';
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
import '../voice/speech_transcriber.dart';
import 'assist_actions.dart';
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
///
/// With a [transcriber], a mic button lets the user speak the prompt
/// instead: one tap starts recording, a second tap stops it, and the words
/// land in the prompt field for the user to check before sending. Voice
/// never sends a prompt on its own.
class AssistView extends StatefulWidget {
  /// The on-device model, or null when the assistant is off in the current
  /// study condition.
  final SettingsIntentModel? model;

  /// On-device speech to text for the prompt, or null for no voice input.
  final SpeechTranscriber? transcriber;
  final SuggestionManager manager;
  final AccessibilityController accessibility;
  final VoidCallback onOpenAccessibilitySettings;

  /// The functions the model was trained on.
  final Future<PersonalizationTools> tools;

  /// The current light or dark setting.
  final ThemeMode Function() themeMode;

  /// The user's chats, most recent first.
  final List<AssistChat> Function() chats;

  /// The guided tour shown in place, or null for none.
  final AssistantGuide? guide;

  /// Reads and applies the app settings besides accessibility.
  final AssistActions actions;

  const AssistView({
    required this.model,
    required this.manager,
    required this.accessibility,
    required this.onOpenAccessibilitySettings,
    required this.tools,
    required this.themeMode,
    required this.chats,
    required this.actions,
    this.transcriber,
    this.guide,
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
  String? roomId;

  /// The value an applied app change replaced, for undo.
  Object? appFrom;

  /// The user answered this exchange's question.
  bool answered = false;

  _Exchange(this.prompt);
}

/// What the line above the prompt field tells the user after a recording.
enum _VoiceNotice {
  heardNothing,
  timeLimit,
  permissionDenied,
  notOnDevice,
  languageMissing,
  error,
}

class _AssistViewState extends State<AssistView> with WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_Exchange> _exchanges = [];
  final AssistConversation _conversation = AssistConversation();
  PersonalizationTools? _tools;
  bool _busy = false;

  /// The only app change Undo is offered for, like the manager's applied
  /// suggestion: undoing an older one would overwrite newer changes.
  _Exchange? _lastAppApplied;
  ModelState? _modelState;

  /// True from the user's tap on the mic until the recording's text is in
  /// the field.
  bool _voiceActive = false;

  /// The field's text when the recording started. The spoken words go after
  /// it.
  String _textBeforeVoice = '';
  _VoiceNotice? _voiceNotice;
  Timer? _elapsedTimer;
  int _elapsedSeconds = 0;

  /// Spoken words were put into the field since the last send, for the
  /// study log. Stays true when the user edits them; resets on send and when
  /// the field is cleared.
  bool _usedVoice = false;

  @override
  void initState() {
    super.initState();
    widget.model?.status.addListener(_onModelStatus);
    widget.tools.then(
      (tools) => mounted ? setState(() => _tools = tools) : null,
      onError: (Object e, StackTrace s) =>
          Logs().e('Unable to load the assistant functions', e, s),
    );
    _listenToVoice(widget.transcriber);
    _controller.addListener(_onFieldChanged);
    widget.guide?.addListener(_onGuide);
    WidgetsBinding.instance.addObserver(this);
  }

  int? _guideStep;

  /// Entering the "try it" step puts the example in the real prompt field.
  void _onGuide() {
    final step = widget.guide?.step;
    if (step == 1 && _guideStep != 1 && _controller.text.isEmpty) {
      _setField(AssistantTutorialL10n.of(context).example);
    }
    _guideStep = step;
  }

  /// The real control the guide's example points at.
  AssistantGuideSpot? get _guideSpot {
    if (widget.guide?.step != 1) return null;
    final last = _last;
    final suggestion = last?.suggestion;
    if (suggestion != null && widget.manager.current == suggestion) {
      return AssistantGuideSpot.apply;
    }
    if (suggestion != null &&
        widget.manager.applied?.suggestion == suggestion) {
      return AssistantGuideSpot.undo;
    }
    if (last?.outcome == _Outcome.undone) return AssistantGuideSpot.done;
    if (last?.outcome == _Outcome.declined) return AssistantGuideSpot.declined;
    return AssistantGuideSpot.send;
  }

  /// The guide above the prompt field. It waits until the AI is set up, so
  /// a first visit shows only the Set up button.
  Widget _guideCard(AssistantGuideSpot? spot) => widget.guide == null
      ? const SizedBox.shrink()
      : AssistantGuideCard(
          guide: widget.guide!,
          spot: spot,
          onOpenSettings: widget.onOpenAccessibilitySettings,
        );

  void _onFieldChanged() {
    if (_controller.text.isEmpty) _usedVoice = false;
  }

  @override
  void didUpdateWidget(AssistView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transcriber != widget.transcriber) {
      _forgetVoice(oldWidget.transcriber);
      _listenToVoice(widget.transcriber);
    }
    if (oldWidget.guide != widget.guide) {
      oldWidget.guide?.removeListener(_onGuide);
      widget.guide?.addListener(_onGuide);
    }
    if (oldWidget.model == widget.model) return;
    oldWidget.model?.status.removeListener(_onModelStatus);
    widget.model?.status.addListener(_onModelStatus);
  }

  void _listenToVoice(SpeechTranscriber? transcriber) {
    transcriber?.status.addListener(_onVoiceStatus);
    transcriber?.text.addListener(_onVoiceText);
  }

  /// Stops listening to [transcriber] and cancels a recording in progress.
  void _forgetVoice(SpeechTranscriber? transcriber) {
    if (transcriber == null) return;
    transcriber.status.removeListener(_onVoiceStatus);
    transcriber.text.removeListener(_onVoiceText);
    _elapsedTimer?.cancel();
    if (_voiceActive || _isRecording(transcriber.status.value)) {
      _voiceActive = false;
      transcriber.cancel();
    }
  }

  static bool _isRecording(TranscriberStatus status) =>
      status == TranscriberStatus.recording ||
      status == TranscriberStatus.finishing;

  bool get _voiceBusy {
    final transcriber = widget.transcriber;
    return transcriber != null && _isRecording(transcriber.status.value);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Not on inactive: the permission dialog makes the app inactive.
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _cancelVoice();
    }
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
    WidgetsBinding.instance.removeObserver(this);
    widget.model?.status.removeListener(_onModelStatus);
    widget.guide?.removeListener(_onGuide);
    _forgetVoice(widget.transcriber);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _toggleVoice() async {
    final transcriber = widget.transcriber;
    if (transcriber == null || _busy) return;
    switch (transcriber.status.value) {
      case TranscriberStatus.ready || TranscriberStatus.failed:
        FocusScope.of(context).unfocus();
        setState(() {
          _voiceNotice = null;
          _voiceActive = true;
          _textBeforeVoice = _controller.text;
        });
        await transcriber.start();
      case TranscriberStatus.recording:
        await transcriber.stop();
      case TranscriberStatus.finishing ||
          TranscriberStatus.unavailable ||
          TranscriberStatus.preparing:
        return;
    }
  }

  /// Ends a recording and puts the field back as it was before it.
  void _cancelVoice() {
    final transcriber = widget.transcriber;
    if (transcriber == null) return;
    if (!_voiceActive && !_isRecording(transcriber.status.value)) return;
    final wasActive = _voiceActive;
    _voiceActive = false;
    _elapsedTimer?.cancel();
    if (wasActive) _setField(_textBeforeVoice);
    transcriber.cancel();
    if (mounted) setState(() {});
  }

  void _onVoiceStatus() {
    final transcriber = widget.transcriber;
    if (transcriber == null || !mounted) return;
    switch (transcriber.status.value) {
      case TranscriberStatus.recording:
        if (_elapsedTimer?.isActive != true) {
          _elapsedSeconds = 0;
          _elapsedTimer = Timer.periodic(
            const Duration(seconds: 1),
            (_) => setState(() => _elapsedSeconds++),
          );
        }
      case TranscriberStatus.finishing:
        _elapsedTimer?.cancel();
      case TranscriberStatus.ready ||
          TranscriberStatus.failed ||
          TranscriberStatus.unavailable ||
          TranscriberStatus.preparing:
        _elapsedTimer?.cancel();
        if (_voiceActive) {
          _finishVoice(transcriber.text.value, transcriber.lastEnd);
        } else if (transcriber.status.value == TranscriberStatus.ready &&
            _voiceNotice == _VoiceNotice.languageMissing) {
          // The pack arrived after a recording found it missing.
          _voiceNotice = null;
        }
    }
    setState(() {});
  }

  /// Shows the live text while recording. The field is read-only then.
  void _onVoiceText() {
    final transcriber = widget.transcriber;
    if (transcriber == null || !_voiceActive) return;
    if (!_isRecording(transcriber.status.value)) return;
    _setField(_withSpoken(transcriber.text.value));
  }

  /// The recording is over: its words stay in the field for the user to
  /// check and send.
  void _finishVoice(String spoken, TranscriberEnd? end) {
    _voiceActive = false;
    final heard = spoken.trim();
    _setField(heard.isEmpty ? _textBeforeVoice : _withSpoken(heard));
    if (heard.isNotEmpty) _usedVoice = true;
    _voiceNotice = switch (end) {
      null ||
      TranscriberEnd.timeLimit when heard.isEmpty => _VoiceNotice.heardNothing,
      null => null,
      TranscriberEnd.timeLimit => _VoiceNotice.timeLimit,
      TranscriberEnd.permissionDenied => _VoiceNotice.permissionDenied,
      TranscriberEnd.notOnDevice => _VoiceNotice.notOnDevice,
      TranscriberEnd.languageMissing => _VoiceNotice.languageMissing,
      TranscriberEnd.restartFailed ||
      TranscriberEnd.error => _VoiceNotice.error,
    };
  }

  /// [spoken] after the text the field had before the recording, with one
  /// space between.
  String _withSpoken(String spoken) {
    final before = _textBeforeVoice.trimRight();
    final words = spoken.trim();
    if (words.isEmpty) return _textBeforeVoice;
    return before.isEmpty ? words : '$before $words';
  }

  void _setField(String text) => _controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );

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
    if (text.isEmpty || _busy || _voiceBusy) return;
    // Spoken words are in the field: the study log records it.
    final voice = _usedVoice;
    final last = _last;
    if (last != null &&
        !last.answered &&
        last.result is AssistClarification &&
        _conversation.awaitsAnswer) {
      last.answered = true;
      return _send(
        text,
        _conversation.answer(text),
        answer: true,
        voice: voice,
      );
    }
    _closeOpen();
    await _send(text, _conversation.ask(text), voice: voice);
  }

  /// A new request replaces what is still open: an unanswered proposal is
  /// declined for the model (the manager logs it as superseded), an open
  /// question is left.
  void _closeOpen() {
    final last = _last;
    if (last == null) return;
    last.answered = true;
    if (last.outcome == null &&
        (last.result is AssistAppProposal ||
            (last.suggestion != null &&
                widget.manager.current == last.suggestion))) {
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
    bool voice = false,
  }) async {
    final model = widget.model;
    final tools = _tools;
    if (model == null || tools == null) return;
    final exchange = _Exchange(shown);
    setState(() {
      _exchanges.add(exchange);
      _busy = true;
      _voiceNotice = null;
      _usedVoice = false;
      _controller.clear();
    });
    _scrollToEnd();
    StudyLog.instance.record(AssistPrompted(shown, voice: voice));

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
      result = _checked(result);
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
    exchange
      ..chatName = matches.single.name
      ..roomId = matches.single.id;
    return _interpreter(tools).forChat(call, matches.single.id);
  }

  void _chooseChat(_Exchange exchange, AssistChat chat) {
    final tools = _tools;
    final result = exchange.result;
    if (tools == null || exchange.answered || result is! AssistNeedsChat) {
      return;
    }
    exchange.answered = true;
    final answer = _Exchange(chat.name)
      ..chatName = chat.name
      ..roomId = chat.id;
    _answerOnPhone(answer, _interpreter(tools).forChat(result.call, chat.id));
  }

  /// A side or color chosen on the phone: the model is not asked again.
  void _chooseDetail(
    _Exchange exchange,
    AssistNeedsDetail detail,
    String option,
  ) {
    final tools = _tools;
    if (tools == null || exchange.answered) return;
    exchange.answered = true;
    final answer = _Exchange(AppearanceL10n.of(context).detailOption(option))
      ..chatName = exchange.chatName
      ..roomId = exchange.roomId;
    _answerOnPhone(
      answer,
      _interpreter(tools).interpret(
        detail.call.withArg(detail.parameter, option),
        roomId: exchange.roomId,
      ),
    );
  }

  void _answerOnPhone(_Exchange answer, AssistResult result) {
    final next = _checked(result);
    StudyLog.instance.record(AssistAnswered(next, answer: true));
    setState(() => _exchanges.add(answer));
    _show(answer, next);
    _scrollToEnd();
  }

  /// An app change that is already as asked, or a bubble color the other
  /// side already has, changes nothing.
  AssistResult _checked(AssistResult result) {
    if (result is! AssistAppProposal) return result;
    final AppChange(:setting, :roomId, :value) = result.change;
    final actions = widget.actions;
    if (actions.current(setting, roomId) == value) {
      return AssistUnchanged(result.call, UnchangedReason.alreadySet);
    }
    final otherSide = switch (setting) {
      AppSetting.ownBubbleColor => AppSetting.otherBubbleColor,
      AppSetting.otherBubbleColor => AppSetting.ownBubbleColor,
      _ => null,
    };
    // Both sides may have the default color: it differs by side.
    if (otherSide != null &&
        value != null &&
        actions.current(otherSide, roomId) == value) {
      return AssistUnchanged(result.call, UnchangedReason.sameAsOtherSide);
    }
    return result;
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
      case AssistClarification() ||
          AssistNeedsChat() ||
          AssistNeedsDetail() ||
          AssistAppProposal():
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

  Future<void> _applyApp(_Exchange exchange, AppChange change) async {
    if (exchange.outcome != null) return;
    exchange.appFrom = widget.actions.current(change.setting, change.roomId);
    setState(() => exchange.outcome = _Outcome.applied);
    if (!await _run(change)) {
      if (mounted) setState(() => exchange.outcome = null);
      return;
    }
    if (mounted) setState(() => _lastAppApplied = exchange);
    _conversation.resolved(applied: true);
    StudyLog.instance.record(
      AssistAppChangeEvent(change.setting.name, 'apply'),
    );
  }

  void _declineApp(_Exchange exchange, AppChange change) {
    if (exchange.outcome != null) return;
    _conversation.resolved(applied: false);
    StudyLog.instance.record(
      AssistAppChangeEvent(change.setting.name, 'decline'),
    );
    setState(() => exchange.outcome = _Outcome.declined);
  }

  Future<void> _undoApp(_Exchange exchange, AppChange change) async {
    if (exchange.outcome != _Outcome.applied || exchange != _lastAppApplied) {
      return;
    }
    setState(() => exchange.outcome = _Outcome.undone);
    if (!await _run(
      AppChange(change.setting, change.roomId, exchange.appFrom),
    )) {
      if (mounted) setState(() => exchange.outcome = _Outcome.applied);
      return;
    }
    if (exchange == _last) _conversation.undone();
    StudyLog.instance.record(AssistAppChangeEvent(change.setting.name, 'undo'));
  }

  /// Applies [change], or says it failed. The app log gets the error.
  Future<bool> _run(AppChange change) async {
    try {
      await widget.actions.apply(change);
      return true;
    } catch (e, s) {
      Logs().w('Assistant change failed', e, s);
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(AppearanceL10n.of(context).changeFailed)),
        );
      }
      return false;
    }
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
    return ListenableBuilder(
      listenable: Listenable.merge([widget.manager, ?widget.guide]),
      builder: (context, _) => model == null
          ? _statusPanel(context, null)
          : ValueListenableBuilder<ModelStatus>(
              valueListenable: model.status,
              builder: (context, status, _) => switch (status.state) {
                ModelState.ready => _conversationView(context),
                _ => _statusPanel(context, status),
              },
            ),
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
    return Column(
      children: [
        Expanded(
          child: Center(
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
          ),
        ),
      ],
    );
  }

  /// Rebuilt by [_onVoiceStatus] when the transcriber's status changes.
  Widget _conversationView(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = PersonalizationL10n.of(context);
    final ready = _tools != null && !_busy;
    final spot = _guideSpot;
    return Column(
      children: [
        Expanded(
          child: ListView(
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
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .stretch,
              children: [
                // Out of the way while the example's answer is on its way.
                if (widget.guide?.step != null &&
                    !(widget.guide!.step == 1 && _busy)) ...[
                  _guideCard(spot),
                  const SizedBox(height: 8),
                ],
                ?_voiceLine(context),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('assist_input'),
                        controller: _controller,
                        enabled: ready,
                        // Shows the live text while recording; editable
                        // again after stop.
                        readOnly: _voiceBusy,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(hintText: l10n.askHint),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ?_micButton(context),
                    AssistantGuideSpotlight(
                      on: spot == AssistantGuideSpot.send,
                      child: IconButton.filled(
                        key: const Key('assist_send'),
                        onPressed: ready && !_voiceBusy ? _submit : null,
                        tooltip: l10n.ask,
                        icon: const Icon(Icons.send),
                        style: IconButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The mic button, or null when this device has no voice input.
  Widget? _micButton(BuildContext context) {
    final transcriber = widget.transcriber;
    if (transcriber == null) return null;
    final status = transcriber.status.value;
    if (status == TranscriberStatus.unavailable) return null;
    final theme = Theme.of(context);
    final l10n = PersonalizationL10n.of(context);
    final recording = status == TranscriberStatus.recording;
    final finishing = status == TranscriberStatus.finishing;
    final preparing = status == TranscriberStatus.preparing;
    final iconSize = IconTheme.of(context).size ?? 24;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: IconButton.filled(
        key: const Key('assist_mic'),
        onPressed: _busy || finishing || preparing ? null : _toggleVoice,
        tooltip: recording
            ? l10n.voiceStop
            : finishing
            ? l10n.voiceFinishing
            : preparing
            ? l10n.voicePreparingShort
            : l10n.voiceStart,
        icon: finishing
            ? SizedBox.square(
                dimension: iconSize,
                child: const CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                recording
                    ? Icons.stop
                    : preparing
                    ? Icons.downloading
                    : Icons.mic,
              ),
        style: recording
            ? IconButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              )
            : IconButton.styleFrom(
                backgroundColor: theme.colorScheme.secondaryContainer,
                foregroundColor: theme.colorScheme.onSecondaryContainer,
              ),
      ),
    );
  }

  /// "Listening" with the elapsed time while recording, a progress line
  /// while finishing, or the notice after a recording. Null when there is
  /// nothing to say.
  Widget? _voiceLine(BuildContext context) {
    final transcriber = widget.transcriber;
    if (transcriber == null) return null;
    final theme = Theme.of(context);
    final l10n = PersonalizationL10n.of(context);
    final Widget line;
    switch (transcriber.status.value) {
      case TranscriberStatus.recording:
        final minutes = _elapsedSeconds ~/ 60;
        final seconds = (_elapsedSeconds % 60).toString().padLeft(2, '0');
        line = Row(
          key: const Key('assist_listening'),
          children: [
            Icon(Icons.mic, color: theme.colorScheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.voiceListening,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text('$minutes:$seconds', key: const Key('assist_voice_timer')),
          ],
        );
      case TranscriberStatus.finishing:
        line = Row(
          key: const Key('assist_voice_finishing'),
          children: [
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(l10n.voiceFinishing)),
          ],
        );
      case TranscriberStatus.preparing:
        line = Row(
          key: const Key('assist_voice_preparing'),
          children: [
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(l10n.voicePreparing)),
          ],
        );
      case TranscriberStatus.ready ||
          TranscriberStatus.failed ||
          TranscriberStatus.unavailable:
        final notice = _voiceNotice;
        if (notice == null) return null;
        line = Text(key: const Key('assist_voice_message'), switch (notice) {
          _VoiceNotice.heardNothing => l10n.voiceHeardNothing,
          _VoiceNotice.timeLimit => l10n.voiceTimeLimit,
          _VoiceNotice.permissionDenied => l10n.voicePermissionDenied,
          _VoiceNotice.notOnDevice => l10n.voiceNotOnDevice,
          _VoiceNotice.languageMissing => l10n.voiceLanguageMissing,
          _VoiceNotice.error => l10n.voiceError,
        });
    }
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: Semantics(liveRegion: true, child: line),
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
        return withSettingsLink(switch (reason) {
          UnchangedReason.atLimit when category != null => l10n.alreadyAtLimit(
            l10n.categoryTitles[category]!,
          ),
          UnchangedReason.sameAsOtherSide => words.sameAsOtherSide,
          _ => words.alreadySet,
        }, key: const Key('assist_unchanged'));
      case final AssistNeedsDetail detail:
        return _detail(context, exchange, detail);
      case AssistAppProposal(:final change):
        return _appProposal(context, exchange, change);
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

  Widget _detail(
    BuildContext context,
    _Exchange exchange,
    AssistNeedsDetail detail,
  ) {
    final words = AppearanceL10n.of(context);
    final open = !exchange.answered && !_busy;
    return Column(
      key: const Key('assist_detail'),
      crossAxisAlignment: .start,
      children: [
        Text(words.detailQuestions[detail.parameter] ?? words.clarifyOne),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in detail.options)
              ActionChip(
                key: Key('assist_detail_$option'),
                avatar: switch (ToolCallInterpreter.colorValues[option]) {
                  final argb? => Icon(Icons.circle, color: Color(argb)),
                  null => null,
                },
                label: Text(words.detailOption(option)),
                onPressed: open
                    ? () => _chooseDetail(exchange, detail, option)
                    : null,
              ),
          ],
        ),
      ],
    );
  }

  Widget _appProposal(
    BuildContext context,
    _Exchange exchange,
    AppChange change,
  ) {
    final l10n = PersonalizationL10n.of(context);
    final words = AppearanceL10n.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Text(words.appChange(change, exchange.chatName)),
        const SizedBox(height: 12),
        switch (exchange.outcome) {
          null => Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton(
                key: const Key('assist_no_thanks'),
                onPressed: () => _declineApp(exchange, change),
                child: Text(l10n.noThanks),
              ),
              FilledButton(
                key: const Key('assist_apply'),
                onPressed: () => _applyApp(exchange, change),
                child: Text(l10n.applyChange),
              ),
            ],
          ),
          _Outcome.applied when exchange == _lastAppApplied => Row(
            children: [
              Expanded(child: Text(words.applied)),
              TextButton.icon(
                key: const Key('assist_undo'),
                onPressed: () => _undoApp(exchange, change),
                icon: const Icon(Icons.undo),
                label: Text(l10n.undo),
              ),
            ],
          ),
          _Outcome.applied => Text(words.applied),
          _Outcome.undone => Text(l10n.changeUndone),
          _Outcome.declined => Text(l10n.notChanged),
        },
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
          AssistantGuideSpotlight(
            on: _guideSpot == AssistantGuideSpot.apply,
            child: OutlinedButton(
              key: const Key('assist_no_thanks'),
              onPressed: () => _decline(exchange),
              child: Text(l10n.noThanks),
            ),
          ),
          AssistantGuideSpotlight(
            on: _guideSpot == AssistantGuideSpot.apply,
            child: FilledButton(
              key: const Key('assist_apply'),
              onPressed: () => _apply(exchange),
              child: Text(l10n.applyChange),
            ),
          ),
        ],
      );
    } else if (widget.manager.applied?.suggestion == suggestion) {
      actions = Row(
        children: [
          Expanded(child: Text(_applied(context, change))),
          AssistantGuideSpotlight(
            on: _guideSpot == AssistantGuideSpot.undo,
            child: TextButton.icon(
              key: const Key('assist_undo'),
              onPressed: () => _undo(exchange),
              icon: const Icon(Icons.undo),
              label: Text(l10n.undo),
            ),
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
    final target = switch (args['target']) {
      'messages' => ScaleCategory.messageText,
      'chat_list' => ScaleCategory.chatListText,
      'titles' => ScaleCategory.titleText,
      'message_input' => ScaleCategory.inputText,
      _ => ScaleCategory.text,
    };
    final button = AccessibleButton.values
        .where((b) => b.name == args['button'])
        .firstOrNull;
    final sized = switch (call.name) {
      PersonalizationTools.changeTextSize when chat != null => words.chatText(
        chat,
      ),
      PersonalizationTools.changeTextSize => words.sizeTarget(target),
      PersonalizationTools.changeButtonSize => words.sizeTarget(
        button?.category ?? ScaleCategory.button,
      ),
      PersonalizationTools.changeSpacing => words.sizeTarget(
        ScaleCategory.spacing,
      ),
      PersonalizationTools.changeLineSpacing => words.sizeTarget(
        ScaleCategory.lineSpacing,
      ),
      PersonalizationTools.changeAvatarSize => words.sizeTarget(
        ScaleCategory.avatar,
      ),
      _ => null,
    };
    final size = args['size'];
    // An exact size wins over the direction, as in the interpreter.
    if (sized != null && size != null) {
      final written = '$size'.trim();
      return words.sizeTo(
        sized,
        words.sizeLabels[written.toLowerCase().replaceAll(' ', '_')] ?? written,
      );
    }
    return switch (call.name) {
      PersonalizationTools.changeTextSize when chat != null =>
        words.chatTextSize(chat, up('bigger')),
      PersonalizationTools.changeTextSize => words.textSize(
        target,
        up('bigger'),
      ),
      PersonalizationTools.changeButtonSize => words.buttonSize(
        button,
        up('bigger'),
      ),
      PersonalizationTools.changeSpacing => words.spacing(up('more')),
      PersonalizationTools.changeLineSpacing => words.lineSpacing(up('more')),
      PersonalizationTools.changeAvatarSize => words.avatarSize(up('bigger')),
      PersonalizationTools.setReadAloud => words.toggle(
        AccessibilityToggle.tripleTapToRead,
        on(),
      ),
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
