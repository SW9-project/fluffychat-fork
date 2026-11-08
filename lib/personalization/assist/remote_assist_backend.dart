// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../heuristics/heuristic.dart';
import '../model/settings_call_validator.dart';
import '../model/settings_intent_model.dart';
import 'assist_backend.dart';
import 'assist_prompt.dart';
import 'assist_result.dart';
import 'assist_validator.dart';

/// A Matrix OpenID token for the proxy, cached until shortly before it
/// expires. The token only proves who the user is; it cannot read or send
/// messages, so the proxy never holds anything that could act as the user.
class OpenIdTokenSource {
  /// Asks the homeserver for a new token and returns it with its lifetime.
  final Future<({String token, Duration expiresIn})> Function() request;
  final DateTime Function() now;

  OpenIdTokenSource(this.request, {DateTime Function()? now})
    : now = now ?? DateTime.now;

  String? _token;
  DateTime? _expires;

  Future<String> get() async {
    final token = _token;
    final expires = _expires;
    if (token != null && expires != null && now().isBefore(expires)) {
      return token;
    }
    final fresh = await request();
    _token = fresh.token;
    // A minute early, so a token never expires on its way to the proxy.
    _expires = now().add(fresh.expiresIn - const Duration(minutes: 1));
    return fresh.token;
  }

  void invalidate() {
    _token = null;
    _expires = null;
  }
}

/// The online assistant: asks our proxy, which forwards to a free-tier LLM.
///
/// This class is the only place that builds the proxy request, from an
/// [AssistRequest] alone. It sends the system prompt from
/// `assets/assist/heuristics.md`, the current setting values, the tool
/// schemas from the settings registry and the user's Assist text (plus at
/// most one earlier question and answer). Matrix IDs, room aliases, links
/// and e-mail addresses are removed from the text first. Nothing else from
/// the app is sent.
class RemoteAssistBackend extends AssistBackend {
  final Uri endpoint;
  final OpenIdTokenSource token;
  final List<Heuristic> Function() heuristics;
  final Future<AssistPromptTemplate> Function() loadTemplate;
  final http.Client _client;
  final Duration timeout;

  RemoteAssistBackend({
    required this.endpoint,
    required this.token,
    required this.heuristics,
    Future<AssistPromptTemplate> Function()? loadTemplate,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : loadTemplate = loadTemplate ?? AssistPromptTemplate.load,
       _client = client ?? http.Client();

  /// The proxy URL from `--dart-define=ASSIST_PROXY_URL=...`. Empty means
  /// the online assistant is off.
  static const configuredUrl = String.fromEnvironment('ASSIST_PROXY_URL');

  /// The proxy URL from the build, else from config.json or MDM
  /// (`assistProxyUrl`). Null when none is set or it is not HTTPS.
  static Uri? configuredEndpoint() => parseEndpoint(
    configuredUrl.isNotEmpty ? configuredUrl : AppSettings.assistProxyUrl.value,
  );

  /// Parses [url] and accepts only HTTPS, or plain HTTP to this machine or
  /// the Android emulator's host for development.
  static Uri? parseEndpoint(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasAuthority) return null;
    if (uri.scheme == 'https') return uri;
    const devHosts = {'localhost', '127.0.0.1', '10.0.2.2'};
    if (uri.scheme == 'http' && devHosts.contains(uri.host)) return uri;
    return null;
  }

  static final ValueNotifier<ModelStatus> _ready = ValueNotifier(
    const ModelStatus(ModelState.ready),
  );

  @override
  ValueListenable<ModelStatus> get status => _ready;

  @override
  Future<void> prepare() async {}

  AssistPromptTemplate? _template;

  @override
  Future<AssistOutcome> ask(AssistRequest request) async {
    final template = _template ??= await loadTemplate();
    final prompt = AssistPromptBuilder.build(template, request.settings);
    final body = jsonEncode(buildBody(prompt, request));
    AssistPromptBuilder.checkBudget(AssistPrompt.estimateTokens(body));

    final watch = Stopwatch()..start();
    var response = await _post(body);
    if (response.statusCode == 401) {
      // The cached token may have been revoked; try once with a new one.
      token.invalidate();
      response = await _post(body);
    }
    watch.stop();

    final json = _decode(response.body);
    final code = (json?['error'] as Map?)?['code'];
    switch (response.statusCode) {
      case 200:
        break;
      case 429:
        throw const AssistBackendUnavailable('rate_limited', rateLimited: true);
      case 503 when code == 'ASSIST_FALLBACK':
        throw const AssistBackendUnavailable('fallback');
      default:
        throw AssistBackendUnavailable(
          code is String ? code : 'http_${response.statusCode}',
        );
    }

    final message = json?['message'];
    if (message is! Map) throw const AssistBackendUnavailable('bad_response');
    final usage = json?['usage'] as Map?;
    final assist = json?['assist'] as Map?;
    final source = AssistSource(
      AssistBackendKind.remote,
      provider: assist?['provider'] as String?,
      model: assist?['model'] as String?,
    );
    final timing = ModelTiming(
      totalMs: watch.elapsedMilliseconds,
      backend: 'remote',
      inputTokens: (usage?['prompt_tokens'] as num?)?.toInt(),
      outputTokens: (usage?['completion_tokens'] as num?)?.toInt(),
    );

    final calls = [
      for (final call in (message['tool_calls'] as List? ?? const []))
        if (call is Map && call['function'] is Map)
          AssistToolCall(
            '${(call['function'] as Map)['name'] ?? ''}',
            (call['function'] as Map)['arguments'],
          ),
    ];
    final AssistResult result;
    if (calls.isNotEmpty) {
      result = AssistValidator.validate(
        calls,
        tools: prompt.tools,
        template: template,
        heuristics: heuristics(),
        settings: request.settings,
      );
    } else if (cleanReply(message['content']) case final text?) {
      result = AssistMessage(text);
    } else {
      result = const AssistNoSuggestion(RejectionReason.noCall);
    }
    return AssistOutcome(result, source, timing: timing);
  }

  Future<http.Response> _post(String body) async {
    try {
      return await _client
          .post(
            endpoint,
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer ${await token.get()}',
            },
            body: body,
          )
          .timeout(timeout);
    } on AssistBackendUnavailable {
      rethrow;
    } catch (_) {
      // Timeouts, DNS and socket errors, and a failed token request all mean
      // the online assistant is out of reach right now.
      throw const AssistBackendUnavailable('network', network: true);
    }
  }

  static Map<String, Object?>? _decode(String body) {
    try {
      final json = jsonDecode(body);
      return json is Map<String, Object?> ? json : null;
    } on FormatException {
      return null;
    }
  }

  /// The request body. Built only from [prompt] (system text and tools from
  /// the registry) and [request]; see the class comment for what is sent.
  @visibleForTesting
  static Map<String, Object?> buildBody(
    AssistPrompt prompt,
    AssistRequest request,
  ) => {
    'messages': [
      {'role': 'system', 'content': prompt.system},
      if (request.previous case final previous?) ...[
        {'role': 'user', 'content': redact(previous.prompt)},
        {'role': 'assistant', 'content': redact(previous.reply)},
      ],
      {'role': 'user', 'content': redact(request.prompt)},
    ],
    'tools': [for (final tool in prompt.tools) tool.toJson()],
    'tool_choice': 'auto',
  };

  static final _matrixId = RegExp(
    r'[@#!+$][A-Za-z0-9._=/+\-]+:[A-Za-z0-9.\-]*[A-Za-z0-9](?::\d+)?',
  );
  static final _link = RegExp(
    r'\b(?:https?://|mxc://|matrix:|www\.)\S*[^\s.,;:!?)\]]',
    caseSensitive: false,
  );
  static final _email = RegExp(r'\b[\w.+\-]+@[\w\-]+\.[\w.\-]+\b');

  /// Removes Matrix user, room and event IDs, aliases, links and e-mail
  /// addresses, which could point to a person or a room. Names typed as
  /// plain words cannot be told apart from other words and are kept.
  static String redact(String text) => text
      .replaceAll(_link, '[link]')
      .replaceAll(_email, '[email]')
      .replaceAll(_matrixId, '[id]');

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

  @override
  void dispose() => _client.close();
}
