// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The LLM is confined to the Assist widget: only the Assist tab creates a
/// backend, and only the backends talk to a model.
void main() {
  final files = {
    for (final f in Directory('lib').listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart'))
        f.path.replaceAll(r'\', '/'): f.readAsStringSync(),
  };
  const page = 'lib/pages/assistant/assistant_page.dart';
  const assistDir = 'lib/personalization/assist/';

  List<String> matching(RegExp pattern) => [
    for (final MapEntry(:key, :value) in files.entries)
      if (pattern.hasMatch(value)) key,
  ];

  test('only the Assist tab and its folder use the backends', () {
    final users = matching(
      RegExp(
        r'''import\s+['"][^'"]*(remote_assist_backend|hybrid_assist_backend|local_gemma_backend)\.dart''',
      ),
    );
    for (final path in users) {
      expect(path == page || path.startsWith(assistDir), isTrue, reason: path);
    }
  });

  test('only the Assist tab creates a backend or the on-device model', () {
    for (final constructor in [
      'RemoteAssistBackend(',
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

  test('only the remote backend talks to the proxy', () {
    expect(matching(RegExp(r'ASSIST_PROXY_URL')), [
      '${assistDir}remote_assist_backend.dart',
    ]);
  });

  test('only function_gemma_model.dart imports the on-device runtime', () {
    expect(matching(RegExp(r'package:flutter_edge_ai')), [
      'lib/personalization/model/function_gemma_model.dart',
    ]);
  });
}
