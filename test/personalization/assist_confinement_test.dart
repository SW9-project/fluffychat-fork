// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The LLM is confined to the Assist widget: only the Assist tab creates a
/// backend, only the backends talk to a model, and only the Groq backend
/// knows the API key and Groq's address.
void main() {
  final files = {
    for (final f in Directory('lib').listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart'))
        f.path.replaceAll(r'\', '/'): f.readAsStringSync(),
  };
  const page = 'lib/pages/assistant/assistant_page.dart';
  const assistDir = 'lib/personalization/assist/';
  const groq = '${assistDir}groq_assist_backend.dart';

  List<String> matching(RegExp pattern) => [
    for (final MapEntry(:key, :value) in files.entries)
      if (pattern.hasMatch(value)) key,
  ];

  test('only the Assist tab and its folder use the backends', () {
    final users = matching(
      RegExp(
        r'''import\s+['"][^'"]*(groq_assist_backend|hybrid_assist_backend|local_gemma_backend|assist_chat_format)\.dart''',
      ),
    );
    expect(users, isNotEmpty);
    for (final path in users) {
      expect(path == page || path.startsWith(assistDir), isTrue, reason: path);
    }
  });

  test('only the Assist tab creates a backend or the on-device model', () {
    for (final constructor in [
      'GroqAssistBackend(',
      'HybridAssistBackend(',
      'LocalGemmaBackend(',
      'FunctionGemmaModel(',
    ]) {
      final callers = matching(RegExp(RegExp.escape(constructor)))
          .where((p) => !p.startsWith(assistDir))
          .where(
            (p) => p != 'lib/personalization/model/function_gemma_model.dart',
          );
      expect(callers, everyElement(page), reason: constructor);
    }
  });

  test('only the Groq backend reads the key and knows the address', () {
    expect(matching(RegExp(r'GROQ_API_KEY')), [groq]);
    expect(matching(RegExp(r'String\.fromEnvironment\(.GROQ_')), [groq]);
    expect(matching(RegExp(r'api\.groq\.com')), [groq]);
  });

  test('no proxy backend is left in the app', () {
    expect(matching(RegExp(r'ASSIST_PROXY_URL|assistProxyUrl')), isEmpty);
  });

  test('only function_gemma_model.dart imports the on-device runtime', () {
    expect(matching(RegExp(r'package:flutter_edge_ai')), [
      'lib/personalization/model/function_gemma_model.dart',
    ]);
  });
}
