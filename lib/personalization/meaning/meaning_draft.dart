// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

import 'meaning_rules.dart';
import 'meaning_settings.dart';
import 'message_meaning.dart';

/// The meaning of the message being written. It follows the text with
/// [MeaningRules] until the sender changes something by hand, and the sender
/// can remove it for one message.
class MeaningDraft extends ChangeNotifier {
  final TextEditingController text;
  final MeaningSettings settings;
  final DateTime Function() clock;

  MessageIntent? _intent;
  MessageUrgency? _urgency;
  final Set<String> _removedTimes = {};
  bool _removed = false;
  String _lastText = '';

  MeaningDraft(
    this.text, {
    MeaningSettings? settings,
    this.clock = DateTime.now,
  }) : settings = settings ?? MeaningSettings.instance {
    text.addListener(_onTextChanged);
    this.settings.addListener(notifyListeners);
  }

  void _onTextChanged() {
    if (text.text == _lastText) return;
    if (text.text.trim().isEmpty) _reset();
    _lastText = text.text;
    notifyListeners();
  }

  /// The meaning to send with the current text, or null when there is none:
  /// empty text, turned off in settings, or removed by the sender.
  MessageMeaning? get meaning {
    if (_removed || !settings.value.annotateOutgoing) return null;
    final current = text.text;
    if (current.trim().isEmpty) return null;
    final proposal = MeaningRules.propose(current, clock());
    return proposal.copyWith(
      intent: _intent,
      urgency: _urgency,
      times: [
        for (final t in proposal.times)
          if (!_removedTimes.contains(t.text)) t,
      ],
    );
  }

  void setIntent(MessageIntent intent) {
    _intent = intent;
    notifyListeners();
  }

  void setUrgency(MessageUrgency urgency) {
    _urgency = urgency;
    notifyListeners();
  }

  void removeTime(MeaningTime time) {
    _removedTimes.add(time.text);
    notifyListeners();
  }

  /// Sends the current message without meaning.
  void remove() {
    _removed = true;
    notifyListeners();
  }

  /// The meaning for the message being sent now. Resets the draft for the
  /// next message.
  MessageMeaning? take() {
    final result = meaning;
    _reset();
    notifyListeners();
    return result;
  }

  void _reset() {
    _intent = null;
    _urgency = null;
    _removedTimes.clear();
    _removed = false;
  }

  @override
  void dispose() {
    text.removeListener(_onTextChanged);
    settings.removeListener(notifyListeners);
    super.dispose();
  }
}
