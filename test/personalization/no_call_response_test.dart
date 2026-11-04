// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_test/flutter_test.dart';

/// A session that answers the way LiteRT-LM does on the phone: the text and
/// the raw JSON, one document per chunk (seen on a Samsung S22).
class _Session extends InferenceModelSession with RawSdkResponseSession {
  final List<String> chunks;
  String? _raw;

  _Session(this.chunks);

  @override
  String? get lastRawResponse => _raw;

  @override
  Future<String> getResponse() async {
    _raw = chunks
        .map(
          (c) => '{"role":"assistant","content":[{"type":"text","text":"$c"}]}',
        )
        .join();
    return chunks.join();
  }

  @override
  Future<void> addQueryChunk(Message message) async {}

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // The sentence the pilot model is trained to write when no function fits.
  // It must reach the app as plain text, not as a failed attempt at a call.
  test('"No matching function." comes back as text, not an error', () async {
    final chat = InferenceChat(
      sessionCreator: () async =>
          _Session(const ['No', ' matching', ' function', '.']),
      maxTokens: 1024,
      supportsFunctionCalls: true,
      tools: const [
        Tool(
          name: 'heuristic_text_zoom',
          description: 'Make the text bigger.',
          parameters: {
            'type': 'object',
            'properties': <String, Object?>{},
            'required': <String>[],
          },
        ),
      ],
      modelType: ModelType.functionGemma,
      fileType: ModelFileType.litertlm,
    );
    await chat.initSession();
    await chat.addQueryChunk(const Message(text: 'x', isUser: true));

    final response = await chat.generateChatResponse();

    expect(response, isA<TextResponse>());
    expect((response as TextResponse).token, 'No matching function.');
  });
}
