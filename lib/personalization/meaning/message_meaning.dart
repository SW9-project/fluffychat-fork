// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';

enum MessageIntent { question, information, request }

enum MessageUrgency { normal, high }

/// A time or date mentioned in the message.
class MeaningTime {
  /// The words in the message, e.g. "tomorrow at 10".
  final String text;

  /// ISO 8601 date ("2026-10-27") or local date and time
  /// ("2026-10-27T10:00"), when it could be worked out.
  final String? at;

  const MeaningTime(this.text, {this.at});

  Map<String, Object?> toJson() => {'text': text, 'at': ?at};

  @override
  bool operator ==(Object other) =>
      other is MeaningTime && other.text == text && other.at == at;

  @override
  int get hashCode => Object.hash(text, at);

  @override
  String toString() => 'MeaningTime($text, $at)';
}

/// What a message means, as confirmed by its sender. It describes meaning,
/// never presentation: each receiver decides how to show it from their own
/// settings.
///
/// It is stored next to `body` in the message content under [namespace], so
/// in encrypted rooms it is encrypted with the rest of the content. Clients
/// that do not know it, such as Element, simply ignore it.
class MessageMeaning {
  static const namespace = 'dk.aau.sw9.meaning';
  static const version = 1;

  final MessageIntent intent;
  final MessageUrgency urgency;
  final List<MeaningTime> times;

  const MessageMeaning({
    this.intent = MessageIntent.information,
    this.urgency = MessageUrgency.normal,
    this.times = const [],
  });

  MessageMeaning copyWith({
    MessageIntent? intent,
    MessageUrgency? urgency,
    List<MeaningTime>? times,
  }) => MessageMeaning(
    intent: intent ?? this.intent,
    urgency: urgency ?? this.urgency,
    times: times ?? this.times,
  );

  Map<String, Object?> toJson() => {
    'v': version,
    'intent': intent.name,
    'urgency': urgency.name,
    if (times.isNotEmpty) 'times': [for (final t in times) t.toJson()],
  };

  /// Reads the meaning from message [content]. Missing, unknown-version or
  /// invalid metadata gives null, and the message is shown as plain text.
  static MessageMeaning? fromContent(Map<String, Object?> content) {
    final raw = content[namespace];
    if (raw is! Map) return null;
    if (raw['v'] != version) return null;
    final intent = MessageIntent.values.firstWhereOrNull(
      (i) => i.name == raw['intent'],
    );
    if (intent == null) return null;
    final rawUrgency = raw['urgency'];
    final urgency = rawUrgency == null
        ? MessageUrgency.normal
        : MessageUrgency.values.firstWhereOrNull((u) => u.name == rawUrgency);
    if (urgency == null) return null;
    final rawTimes = raw['times'] ?? const [];
    if (rawTimes is! List) return null;
    final times = <MeaningTime>[];
    for (final t in rawTimes) {
      if (t is! Map) return null;
      final text = t['text'];
      final at = t['at'];
      if (text is! String || text.isEmpty) return null;
      if (at != null && (at is! String || DateTime.tryParse(at) == null)) {
        return null;
      }
      times.add(MeaningTime(text, at: at as String?));
    }
    return MessageMeaning(intent: intent, urgency: urgency, times: times);
  }

  @override
  bool operator ==(Object other) =>
      other is MessageMeaning &&
      other.intent == intent &&
      other.urgency == urgency &&
      const ListEquality<MeaningTime>().equals(other.times, times);

  @override
  int get hashCode => Object.hash(
    intent,
    urgency,
    const ListEquality<MeaningTime>().hash(times),
  );

  @override
  String toString() => 'MessageMeaning(${toJson()})';
}
