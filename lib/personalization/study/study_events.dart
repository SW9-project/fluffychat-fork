// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import '../accessibility_controller.dart';
import '../accessibility_settings.dart';
import '../meaning/meaning_settings.dart';
import '../meaning/message_meaning.dart';
import '../model/heuristic_functions.dart';
import '../model/settings_intent_model.dart';
import '../suggestions/suggestion.dart';
import 'study_settings.dart';

/// One entry in the study log (Phase 5).
///
/// Events hold ids, enums, numbers and booleans. The only text is what the
/// participant typed to the assistant ([AssistPrompted]), which the team
/// decided to keep. Message text is never part of an event: [MeaningSent]
/// keeps the kind of meaning and how many times it mentions, not the words.
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

  const AssistAnswered(this.result, {this.timing, this.failed = false});

  @override
  String get type => switch (result) {
    AssistProposal() => 'assist_proposal',
    AssistAtLimit() => 'assist_at_limit',
    AssistNoSuggestion() => 'assist_no_suggestion',
  };

  @override
  Map<String, Object?> get data => {
    ...switch (result) {
      AssistProposal(
        :final heuristic,
        :final category,
        :final from,
        :final to,
      ) =>
        {
          'heuristic': heuristic.id,
          'category': category.id,
          'from': from,
          'to': to,
        },
      AssistAtLimit(:final heuristic, :final category) => {
        'heuristic': heuristic.id,
        'category': category.id,
      },
      AssistNoSuggestion(:final reason) => {
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
    'heuristic': suggestion.id,
    'category': suggestion.category.id,
    'from': suggestion.from,
    'to': suggestion.to,
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
    'changes': {
      for (final category in ScaleCategory.values)
        if (commit.from[category] != commit.to[category])
          category.id: [commit.from[category], commit.to[category]],
    },
  };
}

/// The sender changed the proposed meaning before sending: another intent
/// or urgency, or removed a time.
class MeaningChanged extends StudyEvent {
  final MessageIntent? intent;
  final MessageUrgency? urgency;
  final bool timeRemoved;

  const MeaningChanged({this.intent, this.urgency, this.timeRemoved = false});

  @override
  String get type => 'meaning_changed';

  @override
  Map<String, Object?> get data => {
    if (intent != null) 'intent': intent!.name,
    if (urgency != null) 'urgency': urgency!.name,
    if (timeRemoved) 'time_removed': true,
  };
}

/// The sender chose to send the message without meaning.
class MeaningRemoved extends StudyEvent {
  const MeaningRemoved();

  @override
  String get type => 'meaning_removed';

  @override
  Map<String, Object?> get data => const {};
}

/// A message was sent with meaning. Only the kind of meaning is kept.
class MeaningSent extends StudyEvent {
  final MessageMeaning meaning;
  final bool edit;

  const MeaningSent(this.meaning, {this.edit = false});

  @override
  String get type => 'meaning_sent';

  @override
  Map<String, Object?> get data => {
    'intent': meaning.intent.name,
    'urgency': meaning.urgency.name,
    'times': meaning.times.length,
    'edit': edit,
  };
}

class MeaningSettingsChanged extends StudyEvent {
  final MeaningPreferences preferences;

  const MeaningSettingsChanged(this.preferences);

  @override
  String get type => 'meaning_settings';

  @override
  Map<String, Object?> get data => {
    'annotate_outgoing': preferences.annotateOutgoing,
    'show_intent': preferences.showIntent,
    'show_urgency': preferences.showUrgency,
    'highlight_times': preferences.highlightTimes,
  };
}
