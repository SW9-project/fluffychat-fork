// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import type { EvalCase } from './lib.js';

/**
 * Generated evaluation requests: vague and specific complaints in English and
 * Danish, the "too big" direction, off-topic requests and requests for
 * things the app cannot change. `expect` lists every setting that would be a
 * reasonable answer.
 */

const buttons = ['button_scale', 'touch_target_scale'];

export const cases: EvalCase[] = [
  // English: settings
  { id: 'en-buttons-hit', lang: 'en', kind: 'setting', prompt: "I can't hit the buttons", expect: buttons, direction: 'up' },
  { id: 'en-letters-small', lang: 'en', kind: 'setting', prompt: 'the letters are too small', expect: ['text_scale'], direction: 'up' },
  { id: 'en-wrong-thing', lang: 'en', kind: 'setting', prompt: 'I keep pressing the wrong thing', expect: buttons, direction: 'up' },
  { id: 'en-who-wrote', lang: 'en', kind: 'setting', prompt: "I can't see who sent the message", expect: ['avatar_scale'], direction: 'up' },
  { id: 'en-typing', lang: 'en', kind: 'setting', prompt: "When I type I can't read my own words", expect: ['input_text_scale', 'text_scale'], direction: 'up' },
  { id: 'en-pictures-tiny', lang: 'en', kind: 'setting', prompt: 'The little pictures of people are tiny', expect: ['avatar_scale'], direction: 'up' },
  { id: 'en-send-small', lang: 'en', kind: 'setting', prompt: 'The send button is so small that I miss it', expect: buttons, direction: 'up' },
  { id: 'en-icons-larger', lang: 'en', kind: 'setting', prompt: 'Can you make the icons larger?', expect: ['button_scale'], direction: 'up' },
  {
    id: 'en-too-big', lang: 'en', kind: 'setting',
    prompt: 'The writing is far too big now, I have to scroll all the time',
    expect: ['text_scale'], direction: 'down', settings: { text_scale: 1.6 },
  },
  {
    id: 'en-text-smaller', lang: 'en', kind: 'setting',
    prompt: 'make the text a bit smaller please',
    expect: ['text_scale'], direction: 'down', settings: { text_scale: 1.4 },
  },
  // English: vague
  { id: 'en-eyes-bad', lang: 'en', kind: 'vague', prompt: 'My eyes are not so good anymore', expect: ['text_scale', 'button_scale', 'avatar_scale', 'input_text_scale'], direction: 'up' },
  { id: 'en-too-small', lang: 'en', kind: 'vague', prompt: "It's too small", expect: ['text_scale', 'button_scale', 'avatar_scale', 'input_text_scale', 'touch_target_scale'], direction: 'up' },

  // Danish: settings
  { id: 'da-buttons-hit', lang: 'da', kind: 'setting', prompt: 'Jeg kan ikke ramme knapperne', expect: buttons, direction: 'up' },
  { id: 'da-letters-small', lang: 'da', kind: 'setting', prompt: 'Bogstaverne er for små', expect: ['text_scale'], direction: 'up' },
  { id: 'da-wrong-thing', lang: 'da', kind: 'setting', prompt: 'Jeg kommer hele tiden til at trykke forkert', expect: buttons, direction: 'up' },
  { id: 'da-who-wrote', lang: 'da', kind: 'setting', prompt: 'Jeg kan ikke se, hvem der har skrevet', expect: ['avatar_scale'], direction: 'up' },
  { id: 'da-typing', lang: 'da', kind: 'setting', prompt: 'Teksten jeg selv skriver er svær at læse', expect: ['input_text_scale', 'text_scale'], direction: 'up' },
  { id: 'da-avatars', lang: 'da', kind: 'setting', prompt: 'Profilbillederne er alt for små', expect: ['avatar_scale'], direction: 'up' },
  { id: 'da-icons-larger', lang: 'da', kind: 'setting', prompt: 'Gør ikonerne større', expect: ['button_scale'], direction: 'up' },
  { id: 'da-buttons-see', lang: 'da', kind: 'setting', prompt: 'Knapperne er svære at se', expect: ['button_scale'], direction: 'up' },
  {
    id: 'da-too-big', lang: 'da', kind: 'setting',
    prompt: 'Teksten er blevet alt for stor',
    expect: ['text_scale'], direction: 'down', settings: { text_scale: 1.6 },
  },
  {
    id: 'da-text-smaller', lang: 'da', kind: 'setting',
    prompt: 'Kan du gøre skriften lidt mindre?',
    expect: ['text_scale'], direction: 'down', settings: { text_scale: 1.3 },
  },
  // Danish: vague
  { id: 'da-eyes-bad', lang: 'da', kind: 'vague', prompt: 'Jeg ser dårligt', expect: ['text_scale', 'button_scale', 'avatar_scale', 'input_text_scale'], direction: 'up' },
  { id: 'da-too-small', lang: 'da', kind: 'vague', prompt: 'Det er for småt', expect: ['text_scale', 'button_scale', 'avatar_scale', 'input_text_scale', 'touch_target_scale'], direction: 'up' },

  // Out of range: should still pick text, and the value gets clamped.
  { id: 'en-ten-times', lang: 'en', kind: 'setting', prompt: 'Make the text ten times bigger', expect: ['text_scale'], direction: 'up' },

  // Off-topic
  { id: 'en-weather', lang: 'en', kind: 'offtopic', prompt: "What's the weather like tomorrow?" },
  { id: 'da-message-daughter', lang: 'da', kind: 'offtopic', prompt: 'Skriv til min datter, at jeg kommer klokken tre' },
  { id: 'en-joke', lang: 'en', kind: 'offtopic', prompt: 'Tell me a joke' },

  // Impossible: no setting for it
  { id: 'en-read-aloud', lang: 'en', kind: 'impossible', prompt: 'Read my messages out loud to me' },
  { id: 'en-dark-mode', lang: 'en', kind: 'impossible', prompt: 'Switch the app to dark mode' },
  { id: 'da-brighter', lang: 'da', kind: 'impossible', prompt: 'Gør skærmen lysere' },
];
