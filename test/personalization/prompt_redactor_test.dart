// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/personalization/assist/prompt_redactor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String redact(String text, [List<String> names = const []]) =>
      PromptRedactor(knownNames: () => names).redact(text);

  test('removes Matrix IDs, links and e-mail addresses', () {
    expect(
      redact(
        'Like in the chat with @anna:example.org in #family:example.org '
        'and !abc123:example.org, see https://example.org/x or '
        'mxc://example.org/abc, mail anna@example.org',
      ),
      'Like in the chat with [id] in [id] and [id], see [link] or [link], '
      'mail [email]',
    );
    expect(
      redact('Make the text bigger! At 10:30 #1'),
      'Make the text bigger! At 10:30 #1',
    );
  });

  test('removes known names, whole words only, ignoring case', () {
    expect(
      redact('When ANNA writes, and in Hannah’s chat, the text is small', [
        'Anna',
      ]),
      'When [name] writes, and in Hannah’s chat, the text is small',
    );
  });

  test('a multi-word name goes as a whole and word by word', () {
    const names = ['Anna Jensen', 'Familien Østergård'];
    expect(
      redact('Anna  Jensen and anna, and familien østergård', names),
      '[name] and [name], and [name]',
    );
  });

  test('handles Danish letters at word edges', () {
    expect(
      redact('Søren skriver med små bogstaver, Sørensen også', ['Søren']),
      '[name] skriver med små bogstaver, Sørensen også',
    );
  });

  test('keeps screen and common words that are part of a name', () {
    const names = ['Text group', 'The Smiths', 'Familie chat'];
    expect(
      redact('Make the text in the group chat bigger, like the Smiths', names),
      'Make the text in the group chat bigger, like [name]',
    );
    expect(
      redact('Teksten i familie chat er for lille', names),
      'Teksten i [name] er for lille',
    );
  });

  test('a short name counts only as a whole name', () {
    expect(redact('Bo says the buttons are small', ['Bo']), contains('[name]'));
    expect(redact('Bo says hi', ['Bo Li']), 'Bo says hi');
  });

  test('names with punctuation or emoji still match their words', () {
    expect(
      redact('Mormor ❤️ wrote and Ole-Bent too', ['Mormor ❤️', 'Ole-Bent']),
      '[name] ❤️ wrote and [name] too',
    );
  });

  test('no names means only the ID rules apply', () {
    expect(redact('Anna writes', ['', '   ', '❤️']), 'Anna writes');
  });

  test('reads the names on every call', () {
    final names = <String>[];
    final redactor = PromptRedactor(knownNames: () => names);
    expect(redactor.redact('Anna'), 'Anna');
    names.add('Anna');
    expect(redactor.redact('Anna'), '[name]');
  });
}
