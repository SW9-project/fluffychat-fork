// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// One test phrase for the on-device model.
///
/// [accept] lists the heuristic functions that count as a correct answer
/// (Phase 3b: the model only picks among the heuristics). An empty list means
/// no heuristic fits, so only "no suggestion" is correct.
class Phrase {
  final String language;
  final String text;
  final List<String> accept;

  const Phrase(this.language, this.text, this.accept);
}

const _buttons = 'heuristic_near_miss_buttons';
const _text = 'heuristic_text_zoom';

/// Phrases for the Phase 3b check and the Phase 5 harness. The team can extend
/// this list when heuristics are added; keep English and Danish balanced.
const phrases = [
  // English
  Phrase('en', 'The buttons are too small', [_buttons]),
  Phrase('en', "I can't read the messages, the text is tiny", [_text]),
  Phrase('en', 'Make the text bigger please', [_text]),
  Phrase('en', 'The letters are much too big', []),
  Phrase('en', 'I keep pressing the wrong button', [_buttons]),
  Phrase('en', 'My finger keeps missing the send button', [_buttons]),
  Phrase('en', 'I cannot see who wrote, the pictures are too small', []),
  Phrase('en', 'The profile pictures are huge', []),
  Phrase('en', 'What I type in the message box is too small', [_text]),
  Phrase('en', 'The icons are hard to see', [_buttons]),
  Phrase('en', "What's the weather tomorrow?", []),
  Phrase('en', 'Send a message to Anna', []),
  // Danish
  Phrase('da', 'Knapperne er for små', [_buttons]),
  Phrase('da', 'Teksten er for lille, jeg kan ikke læse beskederne', [_text]),
  Phrase('da', 'Gør skriften større', [_text]),
  Phrase('da', 'Skriften er alt for stor', []),
  Phrase('da', 'Jeg rammer hele tiden den forkerte knap', [_buttons]),
  Phrase('da', 'Billederne af folk er for små', []),
  Phrase('da', 'Det jeg skriver i beskedfeltet er for småt', [_text]),
  Phrase('da', 'Ikonerne er svære at se', [_buttons]),
  Phrase('da', 'Hvad er klokken?', []),
  Phrase('da', 'Ring til min datter', []),
];
