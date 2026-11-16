// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import '../accessibility_controller.dart';
import '../model/settings_intent_model.dart';
import '../model/tool_call_interpreter.dart';
import '../suggestions/suggestion.dart';
import 'study_settings.dart';

/// One entry in the study log (Phase 5).
///
/// Events hold ids, enums, numbers and booleans. The only text is what the
/// participant typed to the assistant ([AssistPrompted]), which the team
/// decided to keep. Message text is never part of an event.
sealed class StudyEvent {
  const StudyEvent();

  /// The event name in the log, such as `assist_proposal`.
  String get type;

  Map<String, Object?> get data;
}

/// The researcher turned logging on.
class LoggingStarted extends StudyEvent {
  final StudyCondition condition;

  const LoggingStarted(this.condition);

  @override
  String get type => 'logging_started';

  @override
  Map<String, Object?> get data => {'condition': condition.id};
}

/// The researcher turned logging off. Nothing is recorded after this until
/// logging is turned on again.
class LoggingStopped extends StudyEvent {
  const LoggingStopped();

  @override
  String get type => 'logging_stopped';

  @override
  Map<String, Object?> get data => const {};
}

class ConditionChanged extends StudyEvent {
  final StudyCondition from;
  final StudyCondition to;

  const ConditionChanged(this.from, this.to);

  @override
  String get type => 'condition_changed';

  @override
  Map<String, Object?> get data => {'from': from.id, 'to': to.id};
}

/// The researcher saved the log as a file.
class LogExported extends StudyEvent {
  final int events;

  const LogExported(this.events);

  @override
  String get type => 'log_exported';

  @override
  Map<String, Object?> get data => {'events': events};
}

class AssistOpened extends StudyEvent {
  final StudyCondition condition;

  const AssistOpened(this.condition);

  @override
  String get type => 'assist_opened';

  @override
  Map<String, Object?> get data => {'condition': condition.id};
}

/// The on-device model changed state, for example from preparing to ready.
class AssistModelState extends StudyEvent {
  final ModelState state;

  const AssistModelState(this.state);

  @override
  String get type => 'assist_model_state';

  @override
  Map<String, Object?> get data => {'state': state.name};
}

/// The participant sent a prompt in the Assist tab.
class AssistPrompted extends StudyEvent {
  final String prompt;

  const AssistPrompted(this.prompt);

  @override
  String get type => 'assist_prompt';

  @override
  Map<String, Object?> get data => {'prompt': prompt};
}

/// The assistant's answer to a prompt, with the model's timing.
class AssistAnswered extends StudyEvent {
  final AssistResult result;
  final ModelTiming? timing;

  /// The request failed with an error, which the tab shows as no suggestion.
  final bool failed;

  /// The request answered the model's question: a tapped option or quick
  /// reply, typed words, or a chosen chat.
  final bool answer;

  const AssistAnswered(
    this.result, {
    this.timing,
    this.failed = false,
    this.answer = false,
  });

  @override
  String get type => switch (result) {
    AssistProposal() => 'assist_proposal',
    AssistClarification() => 'assist_clarification',
    AssistNeedsChat() => 'assist_needs_chat',
    AssistUnchanged() => 'assist_unchanged',
    AssistNotAvailable() => 'assist_not_available',
    AssistNoAction() => 'assist_no_action',
    AssistNoSuggestion() => 'assist_no_suggestion',
  };

  /// The call as the model made it. A chat name the user typed is not kept.
  static Map<String, Object?> _call(ProposedCall? call) => call == null
      ? const {}
      : {
          'function': call.name,
          'arguments': {
            for (final MapEntry(:key, :value) in call.args.entries)
              key: key == 'chat' ? '(chat)' : value,
          },
        };

  @override
  Map<String, Object?> get data => {
    if (answer) 'answer': true,
    ...switch (result) {
      AssistProposal(:final call, :final change) => {
        ..._call(call),
        'changes': change.toJson(),
      },
      AssistClarification(:final call, :final options) => {
        ..._call(call),
        'options': options,
      },
      AssistNeedsChat(:final call) => _call(call),
      AssistUnchanged(:final call, :final reason, :final category) => {
        ..._call(call),
        'reason': reason.name,
        if (category != null) 'category': category.id,
      },
      AssistNotAvailable(:final call) => _call(call),
      AssistNoAction(:final call) => _call(call),
      AssistNoSuggestion(:final reason, :final call) => {
        ..._call(call),
        'reason': failed ? 'error' : reason.name,
      },
    },
    ...?timing?.toJson(),
  };
}

enum SuggestionOutcome {
  applied('suggestion_applied'),
  declined('suggestion_declined'),
  undone('suggestion_undone'),
  optedOut('suggestion_opted_out');

  final String type;

  const SuggestionOutcome(this.type);
}

/// What the participant did with a proposed change.
class SuggestionResolved extends StudyEvent {
  final SuggestionOutcome outcome;
  final Suggestion suggestion;

  const SuggestionResolved(this.outcome, this.suggestion);

  @override
  String get type => outcome.type;

  @override
  Map<String, Object?> get data => {
    // The heuristic id, or the function the model called.
    suggestion.isUserRequest ? 'function' : 'heuristic': suggestion.id,
    'changes': suggestion.change.toJson(),
  };
}

/// A change to the accessibility settings from any source: a slider, an
/// applied suggestion, reset or undo. Lists each changed value as
/// `[from, to]`.
class SettingsChanged extends StudyEvent {
  final SettingsCommit commit;

  const SettingsChanged(this.commit);

  @override
  String get type => 'settings_changed';

  @override
  Map<String, Object?> get data => {
    'kind': commit.kind.name,
    'changes': commit.to.diff(commit.from),
  };
}
