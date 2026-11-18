// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

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
import '../voice/speech_transcriber.dart';
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

  const AssistView({
    required this.model,
    required this.manager,
    required this.accessibility,
    required this.onOpenAccessibilitySettings,
    this.transcriber,
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
  bool _busy = false;
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

  List<Heuristic> get _heuristics => widget.manager.config.heuristics;

  @override
  void initState() {
    super.initState();
    widget.model?.status.addListener(_onModelStatus);
    _listenToVoice(widget.transcriber);
    _controller.addListener(_onFieldChanged);
    WidgetsBinding.instance.addObserver(this);
  }

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

  Future<void> _ask() async {
    final model = widget.model;
    final text = _controller.text.trim();
    if (model == null || text.isEmpty || _busy || _voiceBusy) return;
    final exchange = _Exchange(text);
    final voice = _usedVoice;
    setState(() {
      _exchanges.add(exchange);
      _busy = true;
      _voiceNotice = null;
      _usedVoice = false;
      _controller.clear();
    });
    _scrollToEnd();
    StudyLog.instance.record(AssistPrompted(text, voice: voice));

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

  /// Rebuilt by [_onVoiceStatus] when the transcriber's status changes.
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
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .stretch,
              children: [
                ?_voiceLine(context),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('assist_input'),
                        controller: _controller,
                        enabled: !_busy,
                        // Shows the live text while recording; editable
                        // again after stop.
                        readOnly: _voiceBusy,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _ask(),
                        decoration: InputDecoration(hintText: l10n.askHint),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ?_micButton(context),
                    IconButton.filled(
                      key: const Key('assist_send'),
                      onPressed: _busy || _voiceBusy ? null : _ask,
                      tooltip: l10n.ask,
                      icon: const Icon(Icons.send),
                      style: IconButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
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
