// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import '../model/personalization_tools.dart';
import '../model/settings_intent_model.dart';

/// The turns the Assist tab sends with each request, in the three shapes the
/// model was trained on (`training/README.md`, Conversations):
///
/// - **answer**: after `ask_clarification`, the user's choice goes back as
///   that call's response and the model answers in the same turn.
/// - **adjust**: after an applied change, the next request carries that
///   exchange with `{"status": "applied"}` and the reply [appliedReply].
/// - **correct**: the same after a declined change, with
///   `{"status": "declined"}` and [declinedReply].
///
/// The model saw exactly one earlier exchange, so only the last answered one
/// is kept. An exchange that ended without a change to answer (no call,
/// `no_action`, nothing to change) leaves nothing for the next request.
class AssistConversation {
  static const appliedReply = 'Done.';
  static const declinedReply = 'Okay, nothing changed.';

  List<ModelTurn> _earlier = const [];
  final List<ModelTurn> _current = [];

  /// The turns of the exchange in progress, after the earlier one.
  List<ModelTurn> get turns => [..._earlier, ..._current];

  /// Whether the model's last call waits for the user's choice.
  bool get awaitsAnswer {
    final last = _current.lastOrNull;
    return last is CallTurn &&
        last.call.name == PersonalizationTools.askClarification;
  }

  /// Starts an exchange with what the user typed, and returns the turns to
  /// send.
  List<ModelTurn> ask(String text) {
    _current
      ..clear()
      ..add(UserTurn(text));
    return turns;
  }

  /// The model made [call].
  void called(ProposedCall call) => _current.add(CallTurn(call));

  /// The user's answer to `ask_clarification`: a function name for a tapped
  /// option, or their own words. Returns the turns to send.
  List<ModelTurn> answer(String answer) {
    if (!awaitsAnswer) throw StateError('No question to answer');
    _current.add(
      ResponseTurn(PersonalizationTools.askClarification, {'answer': answer}),
    );
    return turns;
  }

  /// The user applied or declined the change of the model's last call. That
  /// exchange becomes the one the next request carries: the user's first
  /// words and the call that was answered.
  void resolved({required bool applied}) {
    final user = _current.whereType<UserTurn>().firstOrNull;
    final last = _current.lastOrNull;
    if (user == null || last is! CallTurn) return ended();
    _earlier = [
      user,
      last,
      ResponseTurn(last.call.name, {
        'status': applied ? 'applied' : 'declined',
      }),
      ReplyTurn(applied ? appliedReply : declinedReply),
    ];
    _current.clear();
  }

  /// The user undid the change the earlier exchange applied: for the model it
  /// was declined.
  void undone() {
    if (_current.isNotEmpty || _earlier.length != 4) return;
    final call = (_earlier[1] as CallTurn).call;
    _earlier = [
      _earlier[0],
      _earlier[1],
      ResponseTurn(call.name, {'status': 'declined'}),
      const ReplyTurn(declinedReply),
    ];
  }

  /// The exchange ended with nothing for the user to answer.
  void ended() {
    _earlier = const [];
    _current.clear();
  }
}
