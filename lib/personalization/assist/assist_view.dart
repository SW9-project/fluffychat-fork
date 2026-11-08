// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../accessibility_controller.dart';
import '../model/heuristic_functions.dart';
import '../model/model_release.dart';
import '../model/settings_call_validator.dart';
import '../model/settings_intent_model.dart';
import '../personalization_l10n.dart';
import '../study/study_events.dart';
import '../study/study_log.dart';
import '../suggestions/suggestion.dart';
import '../suggestions/suggestion_manager.dart';
import 'assist_backend.dart';
import 'change_preview.dart';

/// The Assist tab: the user describes a problem with the UI, an assistant
/// proposes the change that fits, and the tab shows it with a preview.
/// Nothing changes until the user taps Apply, and Undo is offered
/// afterwards.
///
/// The assistant is an [AssistBackend]: the online model through our proxy,
/// with the on-device model as fallback. Each request carries only the
/// prompt, at most the one exchange before it when that ended in a question,
/// and the accessibility settings ([AssistRequest]). Chats and messages are
/// never sent. Every answer is checked by our own code before it is shown.
///
/// The study log (Phase 5) records each prompt and the answer, with timing
/// and which assistant answered, when the researcher turned logging on.
class AssistView extends StatefulWidget {
  /// The assistant, or null when it is off in the current study condition.
  final AssistBackend? backend;
  final SuggestionManager manager;
  final AccessibilityController accessibility;
  final VoidCallback onOpenAccessibilitySettings;

  const AssistView({
    required this.backend,
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
  AssistSource? source;
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

  /// The on-device model's state is what the study log has always recorded.
  ValueListenable<ModelStatus>? _modelStatusOf(AssistBackend? backend) =>
      backend?.offlineStatus ?? backend?.status;

  @override
  void initState() {
    super.initState();
    _modelStatusOf(widget.backend)?.addListener(_onModelStatus);
  }

  @override
  void didUpdateWidget(AssistView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backend == widget.backend) return;
    _modelStatusOf(oldWidget.backend)?.removeListener(_onModelStatus);
    _modelStatusOf(widget.backend)?.addListener(_onModelStatus);
  }

  /// Records when the model changes state, not every progress update.
  void _onModelStatus() {
    final state = _modelStatusOf(widget.backend)?.value.state;
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
    _modelStatusOf(widget.backend)?.removeListener(_onModelStatus);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// The exchange before this one, when the assistant answered it with a
  /// question, so the user's reply can be understood.
  AssistTurn? get _openQuestion {
    final last = _exchanges.lastOrNull;
    return switch (last?.result) {
      AssistMessage(:final text) => AssistTurn(last!.prompt, text),
      _ => null,
    };
  }

  Future<void> _ask() async {
    final backend = widget.backend;
    final text = _controller.text.trim();
    if (backend == null || text.isEmpty || _busy) return;
    final request = AssistRequest(
      text,
      widget.accessibility.settings,
      previous: _openQuestion,
    );
    final exchange = _Exchange(text);
    setState(() {
      _exchanges.add(exchange);
      _busy = true;
      _controller.clear();
    });
    _scrollToEnd();
    StudyLog.instance.record(AssistPrompted(text));

    AssistResult result;
    AssistSource? source;
    ModelTiming? timing;
    var failed = false;
    try {
      final outcome = await backend.ask(request);
      result = outcome.result;
      source = outcome.source;
      timing = outcome.timing;
    } catch (e, s) {
      // The app log gets the failure, never the user's words.
      Logs().w('Assistant request failed', e, s);
      result = const AssistNoSuggestion(RejectionReason.noCall);
      failed = true;
    }
    StudyLog.instance.record(
      AssistAnswered(result, timing: timing, source: source, failed: failed),
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
      exchange.source = source;
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

  /// Asks before downloading the on-device model, because the download is
  /// large and the model comes with its own terms.
  Future<void> _confirmOfflineSetup() async {
    final l10n = PersonalizationL10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.offlineSetupTitle),
        content: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            Text(
              bundledModel
                  ? l10n.assistSetupInfo
                  : l10n.assistDownloadInfo(currentModel.megabytes),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.assistModelTerms,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            TextButton(
              onPressed: () => showLicensePage(context: context),
              child: Text(l10n.assistReadTerms),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.notNow),
          ),
          FilledButton(
            key: const Key('assist_offline_confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.askSetup),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.backend?.prepare();
  }

  @override
  Widget build(BuildContext context) {
    final backend = widget.backend;
    if (backend == null) return _statusPanel(context, null);
    return ValueListenableBuilder<ModelStatus>(
      valueListenable: backend.status,
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
          Text(
            bundledModel
                ? l10n.assistSetupInfo
                : l10n.assistDownloadInfo(currentModel.megabytes),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.assistModelTerms,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          TextButton(
            key: const Key('assist_terms'),
            onPressed: () => showLicensePage(context: context),
            child: Text(l10n.assistReadTerms),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('assist_setup'),
            onPressed: widget.backend?.prepare,
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
      case ModelState.verifying:
        children = [
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(l10n.askVerifying),
        ];
      case ModelState.failed:
        children = [
          Text(
            bundledModel ? l10n.askFailed : l10n.askFailedDownload,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextButton(
            key: const Key('assist_retry'),
            onPressed: widget.backend?.prepare,
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
    final offline = widget.backend?.offlineStatus;
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
                  _AssistantBubble(
                    source: exchange.result == null ? null : exchange.source,
                    child: _answer(context, exchange),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (offline != null)
          ValueListenableBuilder<ModelStatus>(
            valueListenable: offline,
            builder: (context, status, _) => _offlineRow(context, status),
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

  /// A quiet line above the input while the on-device fallback is not
  /// ready, with a way to set it up.
  Widget _offlineRow(BuildContext context, ModelStatus status) {
    final theme = Theme.of(context);
    final l10n = PersonalizationL10n.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final (String text, Widget? action) = switch (status.state) {
      ModelState.ready || ModelState.unavailable => ('', null),
      ModelState.notPrepared => (
        l10n.offlineNotSetUp,
        TextButton(
          key: const Key('assist_offline_setup'),
          onPressed: _confirmOfflineSetup,
          child: Text(l10n.askSetup),
        ),
      ),
      ModelState.preparing => (l10n.askSettingUp(status.progress ?? 0), null),
      ModelState.verifying => (l10n.askVerifying, null),
      ModelState.failed => (
        l10n.offlineFailed,
        TextButton(
          key: const Key('assist_offline_retry'),
          onPressed: widget.backend?.prepare,
          child: Text(l10n.tryAgain),
        ),
      ),
    };
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: const Key('assist_offline_row'),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(Icons.phone_android_outlined, size: 16, color: style?.color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: style)),
          ?action,
        ],
      ),
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
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(l10n.thinking),
          ],
        );
      case AssistMessage(:final text):
        return Text(text, key: const Key('assist_message'));
      case AssistUnavailable(:final reason):
        return withSettingsLink(switch (reason) {
          AssistUnavailableReason.offline => l10n.assistOnlineUnavailable,
          AssistUnavailableReason.rateLimited => l10n.assistRateLimited,
        }, key: const Key('assist_unavailable'));
      case AssistNoSuggestion(:final reason):
        return withSettingsLink(
          reason == RejectionReason.noChange
              ? l10n.assistNoChange
              : l10n.noSuggestion,
          key: const Key('assist_no_suggestion'),
        );
      case AssistAtLimit(:final category):
        return withSettingsLink(
          l10n.alreadyAtLimit(l10n.categoryTitles[category]!),
        );
      case AssistProposal(
        :final heuristic,
        :final category,
        :final from,
        :final to,
        :final rationale,
        :final clamped,
      ):
        final suggestion = exchange.suggestion!;
        final premade = heuristic.description(language);
        final reason =
            rationale ??
            (premade.isNotEmpty ? premade : l10n.assistGenericReason);
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
            Text(reason, key: const Key('assist_reason')),
            if (clamped) ...[
              const SizedBox(height: 4),
              Text(l10n.assistClamped),
            ],
            const SizedBox(height: 12),
            ChangePreview(category: category, from: from, to: to),
            const SizedBox(height: 12),
            actions,
            // Undo here lasts only a moment; the settings page keeps it.
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

  /// Which assistant answered, shown as a small label under the bubble.
  final AssistSource? source;

  const _AssistantBubble({required this.child, this.source});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = PersonalizationL10n.of(context);
    final source = this.source;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(right: 24, bottom: 16),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppConfig.borderRadius),
              ),
              child: child,
            ),
            if (source != null)
              Padding(
                key: Key('assist_source_${source.kind.name}'),
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: Row(
                  mainAxisSize: .min,
                  children: [
                    Icon(
                      source.kind == AssistBackendKind.remote
                          ? Icons.cloud_outlined
                          : Icons.phone_android_outlined,
                      size: 12,
                      color: labelStyle?.color,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      source.kind == AssistBackendKind.remote
                          ? l10n.answeredOnline
                          : l10n.answeredOnDevice,
                      style: labelStyle,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
