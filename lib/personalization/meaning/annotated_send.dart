// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:html_unescape/html_unescape.dart';
import 'package:matrix/matrix.dart';
// The SDK's own markdown renderer, so annotated messages are formatted
// exactly like the ones Room.sendTextEvent sends. It is not exported.
// ignore: implementation_imports
import 'package:matrix/src/utils/markdown.dart';

import 'message_meaning.dart';

/// Builds the content of a text message the way `Room.sendTextEvent` does
/// (body, mentions, formatted body) and adds the sender's [meaning] next to
/// `body` under [MessageMeaning.namespace].
///
/// The meaning is part of the content, so in an encrypted room it is
/// encrypted with the body. It never goes into `m.relates_to` or room state,
/// which stay in plaintext.
Map<String, Object?> buildAnnotatedTextContent(
  Room room,
  String message, {
  MessageMeaning? meaning,
  Event? inReplyTo,
}) {
  final content = <String, Object?>{
    'msgtype': MessageTypes.Text,
    'body': message,
  };

  // Mentions, as in Room.sendTextEvent.
  var potentialMentions =
      message
          .split('@')
          .map(
            (text) => text.startsWith('[')
                ? '@${text.split(']').first}]'
                : '@${text.split(RegExp(r'\s+')).first}',
          )
          .toList()
        ..removeAt(0);
  final hasRoomMention = potentialMentions.remove('@room');
  potentialMentions =
      potentialMentions
          .map(
            (mention) => mention.isValidMatrixIdStrict(strictDomainCheck: true)
                ? mention
                : room.getMention(mention),
          )
          .nonNulls
          .toSet()
          .toList()
        ..remove(room.client.userID);
  if (inReplyTo != null) potentialMentions.add(inReplyTo.senderId);
  if (hasRoomMention || potentialMentions.isNotEmpty) {
    content['m.mentions'] = {
      if (hasRoomMention) 'room': true,
      if (potentialMentions.isNotEmpty) 'user_ids': potentialMentions,
    };
  }

  // Formatted body, as in Room.sendTextEvent.
  final html = markdown(
    message,
    getEmotePacks: () => room.getImagePacksFlat(ImagePackUsage.emoticon),
    getMention: room.getMention,
    convertLinebreaks: room.client.convertLinebreaksInFormatting,
    enableLatex: room.client.enableLatexMarkdown,
  );
  if (HtmlUnescape().convert(html.replaceAll(RegExp(r'<br />\n?'), '\n')) !=
      message) {
    content['format'] = 'org.matrix.custom.html';
    content['formatted_body'] = html;
  }

  if (meaning != null) content[MessageMeaning.namespace] = meaning.toJson();
  return content;
}

/// Sends a text message with the sender's [meaning]. For an edit
/// ([editEventId]), the SDK copies the whole content, meaning included, into
/// `m.new_content`, so the edit carries its own meaning.
Future<String?> sendAnnotatedText(
  Room room,
  String message, {
  MessageMeaning? meaning,
  Event? inReplyTo,
  String? editEventId,
  String? threadRootEventId,
  String? threadLastEventId,
}) => room.sendEvent(
  buildAnnotatedTextContent(
    room,
    message,
    meaning: meaning,
    inReplyTo: inReplyTo,
  ),
  inReplyTo: inReplyTo,
  editEventId: editEventId,
  threadRootEventId: threadRootEventId,
  threadLastEventId: threadLastEventId,
);
