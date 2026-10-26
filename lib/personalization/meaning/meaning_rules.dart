// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'message_meaning.dart';

/// Proposes a [MessageMeaning] for a message the user is writing, with simple
/// English and Danish rules. No model reads the message (Phase 3b). The
/// proposal is only a starting point: the sender sees it and can change or
/// remove it before sending.
abstract final class MeaningRules {
  static MessageMeaning propose(String text, DateTime now) => MessageMeaning(
    intent: intentOf(text),
    urgency: urgencyOf(text),
    times: timesIn(text, now),
  );

  static const _requestStarts = [
    'please',
    'can you',
    'could you',
    'would you',
    'will you',
    'remember to',
    "don't forget",
    'vil du',
    'kan du',
    'kunne du',
    'venligst',
    'husk at',
    'husk ',
    'glem ikke',
  ];

  static const _questionWords = {
    'what', 'when', 'where', 'who', 'why', 'how', 'which', 'is', 'are', //
    'do', 'does', 'did', 'can', 'could', 'will', 'would', 'should', 'have',
    'has', 'hvad', 'hvornår', 'hvor', 'hvem', 'hvorfor', 'hvordan',
    'hvilken', 'hvilke', 'er', 'har', 'skal', 'kan', 'vil', 'kommer', 'ses',
  };

  static MessageIntent intentOf(String text) {
    final t = text.trim().toLowerCase();
    if (t.isEmpty) return MessageIntent.information;
    if (_requestStarts.any(t.startsWith)) return MessageIntent.request;
    if (t.endsWith('?')) return MessageIntent.question;
    final firstWord = t.split(RegExp(r'[\s,.!]+')).first;
    if (_questionWords.contains(firstWord)) return MessageIntent.question;
    return MessageIntent.information;
  }

  static final _urgent = RegExp(
    r'\b(urgent|asap|emergency|immediately|right now|haster|akut|straks|'
    r'hurtigst muligt|nødsituation)\b|!!',
    caseSensitive: false,
  );

  static MessageUrgency urgencyOf(String text) =>
      _urgent.hasMatch(text) ? MessageUrgency.high : MessageUrgency.normal;

  static const _weekdays = {
    'monday': DateTime.monday,
    'tuesday': DateTime.tuesday,
    'wednesday': DateTime.wednesday,
    'thursday': DateTime.thursday,
    'friday': DateTime.friday,
    'saturday': DateTime.saturday,
    'sunday': DateTime.sunday,
    'mandag': DateTime.monday,
    'tirsdag': DateTime.tuesday,
    'onsdag': DateTime.wednesday,
    'torsdag': DateTime.thursday,
    'fredag': DateTime.friday,
    'lørdag': DateTime.saturday,
    'søndag': DateTime.sunday,
  };

  static final _day = RegExp(
    r'\b(?:(?:on|next|på|næste)\s+)?'
    r'(today|tonight|tomorrow|day after tomorrow|'
    r'i dag|i aften|i morgen|i overmorgen|'
    '${_weekdays.keys.join('|')})'
    r'(?![\wæøå])',
    caseSensitive: false,
  );

  // "10:30", "kl. 10", "kl 10.30", "klokken 14", "at 10", "at 10:30 pm",
  // "3pm", "3 pm".
  static final _time = RegExp(
    r'\b(?:(kl\.?|klokken|at)\s*)?([01]?\d|2[0-3])(?:([:.])([0-5]\d))?'
    r'\s*(am|pm)?(?![\w:.])',
    caseSensitive: false,
  );

  static List<MeaningTime> timesIn(String text, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);

    final days = <({int start, int end, DateTime date})>[];
    for (final m in _day.allMatches(text)) {
      final word = m.group(1)!.toLowerCase();
      final DateTime date;
      switch (word) {
        case 'today' || 'tonight' || 'i dag' || 'i aften':
          date = today;
        case 'tomorrow' || 'i morgen':
          date = today.add(const Duration(days: 1));
        case 'day after tomorrow' || 'i overmorgen':
          date = today.add(const Duration(days: 2));
        default:
          final weekday = _weekdays[word]!;
          var ahead = (weekday - today.weekday) % 7;
          if (ahead == 0) ahead = 7;
          date = today.add(Duration(days: ahead));
      }
      days.add((start: m.start, end: m.end, date: date));
    }

    final clocks = <({int start, int end, int hour, int minute})>[];
    for (final m in _time.allMatches(text)) {
      final prefix = m.group(1);
      final separator = m.group(3);
      final suffix = m.group(5)?.toLowerCase();
      // A bare number is not a time: it needs a prefix, minutes after a
      // colon, or am/pm. Minutes after a dot need a prefix ("kl. 10.30"),
      // because "3.50" is more often a price.
      final hasMinutes = m.group(4) != null;
      final isTime =
          prefix != null || suffix != null || (hasMinutes && separator == ':');
      if (!isTime) continue;
      var hour = int.parse(m.group(2)!);
      final minute = hasMinutes ? int.parse(m.group(4)!) : 0;
      if (suffix == 'pm' && hour < 12) hour += 12;
      if (suffix == 'am' && hour == 12) hour = 0;
      if (hour > 23) continue;
      clocks.add((start: m.start, end: m.end, hour: hour, minute: minute));
    }

    String iso(DateTime d, [int? hour, int? minute]) {
      String two(int n) => n.toString().padLeft(2, '0');
      final date = '${d.year}-${two(d.month)}-${two(d.day)}';
      return hour == null ? date : '${date}T${two(hour)}:${two(minute!)}';
    }

    final results = <({int start, MeaningTime time})>[];
    final usedClocks = <int>{};
    for (final day in days) {
      // The closest unused clock time within a few characters of the day
      // belongs to it.
      int distance(({int start, int end, int hour, int minute}) c) =>
          min((c.start - day.end).abs(), (day.start - c.end).abs());
      var clockIndex = -1;
      for (var i = 0; i < clocks.length; i++) {
        if (usedClocks.contains(i) || distance(clocks[i]) > 12) continue;
        if (clockIndex < 0 ||
            distance(clocks[i]) < distance(clocks[clockIndex])) {
          clockIndex = i;
        }
      }
      if (clockIndex >= 0) {
        usedClocks.add(clockIndex);
        final c = clocks[clockIndex];
        final start = min(day.start, c.start);
        final end = max(day.end, c.end);
        results.add((
          start: start,
          time: MeaningTime(
            text.substring(start, end).trim(),
            at: iso(day.date, c.hour, c.minute),
          ),
        ));
      } else {
        results.add((
          start: day.start,
          time: MeaningTime(
            text.substring(day.start, day.end).trim(),
            at: iso(day.date),
          ),
        ));
      }
    }
    for (var i = 0; i < clocks.length; i++) {
      if (usedClocks.contains(i)) continue;
      final c = clocks[i];
      results.add((
        start: c.start,
        time: MeaningTime(
          text.substring(c.start, c.end).trim(),
          at: iso(today, c.hour, c.minute),
        ),
      ));
    }
    results.sort((a, b) => a.start.compareTo(b.start));
    return [for (final r in results) r.time];
  }
}
