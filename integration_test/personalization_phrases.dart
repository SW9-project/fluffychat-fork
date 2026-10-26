// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// One test phrase for the on-device model.
///
/// [accept] lists the calls that count as correct, as
/// `function name: direction`. An empty list means the model must not
/// propose any valid change, so only a rejection is correct.
class Phrase {
  final String language;
  final String text;
  final List<String> accept;

  const Phrase(this.language, this.text, this.accept);
}

/// Phrases for the Phase 3 check and the Phase 5 harness. The team can extend
/// this list; keep English and Danish balanced.
const phrases = [
  // English
  Phrase('en', 'The buttons are too small', ['adjust_button_size: bigger']),
  Phrase('en', "I can't read the messages, the text is tiny", [
    'adjust_text_size: bigger',
  ]),
  Phrase('en', 'Make the text bigger please', ['adjust_text_size: bigger']),
  Phrase('en', 'The letters are much too big', ['adjust_text_size: smaller']),
  Phrase('en', 'I keep pressing the wrong button', [
    'adjust_touch_target_size: bigger',
    'adjust_button_size: bigger',
  ]),
  Phrase('en', 'My finger keeps missing the send button', [
    'adjust_touch_target_size: bigger',
    'adjust_button_size: bigger',
  ]),
  Phrase('en', 'I cannot see who wrote, the pictures are too small', [
    'adjust_avatar_size: bigger',
  ]),
  Phrase('en', 'The profile pictures are huge', [
    'adjust_avatar_size: smaller',
  ]),
  Phrase('en', 'What I type in the message box is too small', [
    'adjust_input_text_size: bigger',
  ]),
  Phrase('en', 'The icons are hard to see', ['adjust_button_size: bigger']),
  Phrase('en', "What's the weather tomorrow?", []),
  Phrase('en', 'Send a message to Anna', []),
  // Danish
  Phrase('da', 'Knapperne er for små', ['adjust_button_size: bigger']),
  Phrase('da', 'Teksten er for lille, jeg kan ikke læse beskederne', [
    'adjust_text_size: bigger',
  ]),
  Phrase('da', 'Gør skriften større', ['adjust_text_size: bigger']),
  Phrase('da', 'Skriften er alt for stor', ['adjust_text_size: smaller']),
  Phrase('da', 'Jeg rammer hele tiden den forkerte knap', [
    'adjust_touch_target_size: bigger',
    'adjust_button_size: bigger',
  ]),
  Phrase('da', 'Billederne af folk er for små', ['adjust_avatar_size: bigger']),
  Phrase('da', 'Det jeg skriver i beskedfeltet er for småt', [
    'adjust_input_text_size: bigger',
  ]),
  Phrase('da', 'Ikonerne er svære at se', ['adjust_button_size: bigger']),
  Phrase('da', 'Hvad er klokken?', []),
  Phrase('da', 'Ring til min datter', []),
];
