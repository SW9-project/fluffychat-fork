// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import '../heuristics/heuristic.dart';
import '../model/settings_call_validator.dart';
import 'assist_backend.dart';
import 'assist_prompt.dart';
import 'assist_result.dart';
import 'assist_validator.dart';
import 'prompt_redactor.dart';

/// The OpenAI chat-completions format, shared by every online assistant so
/// that a new backend (for example one behind our own proxy again) sends and
/// reads exactly the same thing.
///
/// [body] is the only place a request is put together. It reads nothing but
/// the [AssistPrompt] (system text and tools from the settings registry) and
/// the closed [AssistRequest], and runs every piece of user text through a
/// [PromptRedactor]. Messages, rooms and contacts cannot get in.
abstract final class AssistChatFormat {
  /// Added to the system prompt when an answer is asked for again after a
  /// malformed tool call. It is fixed text and carries nothing about the user.
  static const retryHint =
      'Your last answer had a tool call that could not be used. Call exactly '
      'one of the tools above with valid arguments, or answer in one short '
      'sentence.';

  /// Messages, tools and `tool_choice`. Backends add their own model
  /// parameters on top.
  static Map<String, Object?> body(
    AssistPrompt prompt,
    AssistRequest request,
    PromptRedactor redactor, {
    bool retry = false,
  }) => {
    'messages': [
      {
        'role': 'system',
        'content': retry ? '${prompt.system}\n\n$retryHint' : prompt.system,
      },
      if (request.previous case final previous?) ...[
        {'role': 'user', 'content': redactor.redact(previous.prompt)},
        {'role': 'assistant', 'content': redactor.redact(previous.reply)},
      ],
      {'role': 'user', 'content': redactor.redact(request.prompt)},
    ],
    'tools': [for (final tool in prompt.tools) tool.toJson()],
    'tool_choice': 'auto',
  };

  /// The tool calls in an assistant message, as the API returned them.
  static List<AssistToolCall> toolCalls(Map message) => [
    for (final call in (message['tool_calls'] as List? ?? const []))
      if (call is Map && call['function'] is Map)
        AssistToolCall(
          '${(call['function'] as Map)['name'] ?? ''}',
          (call['function'] as Map)['arguments'],
        ),
  ];

  /// Checks an assistant message with our own code: tool calls go through
  /// [AssistValidator], a text answer becomes an [AssistMessage], and
  /// anything else is no suggestion.
  static AssistResult interpret(
    Map message, {
    required AssistPrompt prompt,
    required AssistPromptTemplate template,
    required List<Heuristic> heuristics,
    required AssistRequest request,
  }) {
    final calls = toolCalls(message);
    if (calls.isNotEmpty) {
      return AssistValidator.validate(
        calls,
        tools: prompt.tools,
        template: template,
        heuristics: heuristics,
        settings: request.settings,
      );
    }
    if (cleanReply(message['content']) case final text?) {
      return AssistMessage(text);
    }
    return const AssistNoSuggestion(RejectionReason.noCall);
  }

  /// A tool call that could not be used at all, as opposed to a fine call
  /// that changes nothing. Worth asking the model once more.
  static bool isMalformed(AssistResult result) => switch (result) {
    AssistNoSuggestion(
      reason: RejectionReason.invalidArguments ||
          RejectionReason.unknownFunction ||
          RejectionReason.unknownHeuristic,
    ) =>
      true,
    _ => false,
  };

  static const replyMaxLength = 400;

  /// The model's text answer as plain text, or null when there is none.
  static String? cleanReply(Object? raw) {
    if (raw is! String) return null;
    var text = raw
        .replaceAll(RegExp(r'[*_`#>]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) return null;
    if (text.length > replyMaxLength) {
      text = '${text.substring(0, replyMaxLength - 1).trimRight()}…';
    }
    return text;
  }
}
