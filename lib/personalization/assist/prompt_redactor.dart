// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Removes from the Assist text anything that could point to a person or a
/// room before it leaves the phone:
///
/// - Matrix user, room and event IDs and aliases become `[id]`
/// - links become `[link]` and e-mail addresses `[email]`
/// - the names of the user's rooms and contacts, and the user's own name,
///   become `[name]`
///
/// [knownNames] is read on every call, so a new chat is covered at once. The
/// names are only compared with the text here; they are never sent.
///
/// Matching is whole-word and ignores case, so "anna" in "Hannah" is kept.
/// A multi-word name is also matched word by word ("Anna" from "Anna
/// Jensen"), except words shorter than three letters and the everyday and
/// screen words in [_keep]. A room called "Text group" therefore cannot
/// blank out "make the text bigger". This can still remove a word that is
/// both a name and a normal word, such as "Mor" when a contact is called so.
class PromptRedactor {
  final Iterable<String> Function() knownNames;

  const PromptRedactor({this.knownNames = _noNames});

  static Iterable<String> _noNames() => const [];

  static final _matrixId = RegExp(
    r'[@#!+$][A-Za-z0-9._=/+\-]+:[A-Za-z0-9.\-]*[A-Za-z0-9](?::\d+)?',
  );
  static final _link = RegExp(
    r'\b(?:https?://|mxc://|matrix:|www\.)\S*[^\s.,;:!?)\]]',
    caseSensitive: false,
  );
  static final _email = RegExp(r'\b[\w.+\-]+@[\w\-]+\.[\w.\-]+\b');
  static final _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);

  /// Shorter words than this are kept unless they are a whole name.
  static const minWordLength = 3;

  /// Words that stay even when they are part of a name: our own placeholders,
  /// the words people use to describe the screen, and common English and
  /// Danish words.
  static const _keep = {
    // Placeholders
    'id', 'link', 'email', 'name',
    // The screen
    'text', 'tekst', 'teksten', 'skrift', 'skriften', 'letters', 'bogstaver',
    'font', 'button', 'buttons', 'knap', 'knappen', 'knapper', 'knapperne',
    'icon', 'icons', 'ikon', 'ikoner', 'ikonerne', 'picture', 'pictures',
    'photo', 'photos', 'billede', 'billeder', 'billederne', 'profilbillede',
    'profilbilleder', 'avatar', 'avatars', 'size', 'størrelse', 'screen',
    'skærm', 'skærmen', 'big', 'bigger', 'large', 'larger', 'small', 'smaller',
    'tiny', 'stor', 'store', 'større', 'lille', 'små', 'mindre', 'chat',
    'chats', 'group', 'groups', 'gruppe', 'gruppen', 'grupper', 'room',
    'rooms', 'message', 'messages', 'besked', 'beskeder', 'beskederne', 'app',
    // Common words
    'the', 'and', 'for', 'with', 'from', 'all', 'our', 'you', 'not', 'are',
    'can', 'too', 'very', 'more', 'less', 'old', 'new', 'friends', 'family',
    'home', 'work', 'club', 'team', 'news', 'den', 'det', 'der', 'som', 'har',
    'med', 'til', 'fra', 'kan', 'ikke', 'meget', 'mere', 'alle',
    'vores', 'jeg', 'mig', 'min', 'mit', 'mine', 'familie', 'familien',
    'venner', 'vennerne', 'hjem', 'arbejde', 'klub', 'klubben', 'nyheder',
  };

  String redact(String text) {
    var result = text
        .replaceAll(_link, '[link]')
        .replaceAll(_email, '[email]')
        .replaceAll(_matrixId, '[id]');
    final names = namePattern(knownNames());
    if (names != null) result = result.replaceAll(names, '[name]');
    return result;
  }

  /// One pattern for every name and name word, longest first so a full name
  /// wins over its parts. Null when there is nothing to look for.
  static RegExp? namePattern(Iterable<String> names) {
    final alternatives = <String>{};
    for (final name in names) {
      final words = [for (final m in _word.allMatches(name)) m[0]!];
      if (words.isEmpty) continue;
      final whole = words.join(' ');
      if (words.length > 1 || !_keep.contains(whole.toLowerCase())) {
        // Any spacing or punctuation between the words of a full name.
        alternatives.add(words.join(r'[^\p{L}\p{N}]+'));
      }
      for (final word in words) {
        if (word.length >= minWordLength &&
            !_keep.contains(word.toLowerCase())) {
          alternatives.add(word);
        }
      }
    }
    if (alternatives.isEmpty) return null;
    // Words are letters and digits only, so they need no escaping.
    final sorted = alternatives.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    return RegExp(
      '(?<![\\p{L}\\p{N}])(?:${sorted.join('|')})(?![\\p{L}\\p{N}])',
      unicode: true,
      caseSensitive: false,
    );
  }
}
