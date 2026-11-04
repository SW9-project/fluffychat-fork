// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:fluffychat/personalization/model/model_licenses.dart';
import 'package:fluffychat/personalization/model/model_release.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
// ignore: implementation_imports
import 'package:flutter_edge_ai/src/model_management/model_specs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the current model', () {
    final uri = Uri.parse(currentModel.url);

    test('comes from a release of the public models repository', () {
      expect(uri.scheme, 'https');
      expect(uri.host, 'github.com');
      expect(uri.pathSegments, hasLength(6));
      expect(uri.pathSegments.sublist(0, 4), [
        'SW9-project',
        'sw9-models',
        'releases',
        'download',
      ]);
      expect(uri.query, isEmpty);
    });

    test('its file name says which release it is from', () {
      expect(currentModel.fileName, contains(uri.pathSegments[4]));
      expect(currentModel.fileName, endsWith('.litertlm'));
    });

    test('the plugin installs it under the same file name', () {
      expect(
        InferenceModelFile.fromSource(
          ModelSource.network(currentModel.url),
        ).filename,
        currentModel.fileName,
      );
      expect(
        InferenceModelFile.fromSource(
          ModelSource.asset(currentModel.assetPath),
        ).filename,
        currentModel.fileName,
      );
    });

    test('has a real checksum and size', () {
      expect(currentModel.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(currentModel.sizeBytes, greaterThan(100000000));
      expect(currentModel.megabytes, 285);
    });

    test('the study build script can read it', () {
      final source = File(
        'lib/personalization/model/model_release.dart',
      ).readAsStringSync();
      // The same patterns as scripts/build_study_apk.sh.
      expect(
        RegExp(
          r"https://[^']+\.litertlm",
        ).allMatches(source).map((m) => m.group(0)),
        [currentModel.url],
      );
      expect(
        RegExp(r'[0-9a-f]{64}').allMatches(source).map((m) => m.group(0)),
        [currentModel.sha256],
      );
    });
  });

  test('a normal build downloads the model', () {
    expect(bundledModel, isFalse);
  });

  test('a normal build does not bundle a model file', () {
    final bundled = Directory('assets/models')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((name) => name.endsWith('.litertlm'));
    expect(
      bundled,
      isEmpty,
      reason:
          'Flutter bundles everything in assets/models/, so a file left here '
          'makes the APK hundreds of megabytes larger, and the app ignores it. '
          'scripts/build_study_apk.sh removes its copy.',
    );
  });

  group('the licenses screen', () {
    late List<LicenseEntry> entries;

    setUpAll(() async {
      LicenseRegistry.reset();
      registerModelLicenses();
      entries = await LicenseRegistry.licenses.toList();
    });

    tearDownAll(LicenseRegistry.reset);

    String textOf(LicenseEntry entry) =>
        entry.paragraphs.map((p) => p.text).join('\n');

    test('has the Gemma notice, exactly as the terms word it', () {
      expect(entries, hasLength(2));
      expect(entries.first.packages, ['FunctionGemma (SW9 model)']);
      expect(
        textOf(entries.first),
        contains(
          'Gemma is provided under and subject to the Gemma Terms of Use found '
          'at ai.google.dev/gemma/terms',
        ),
      );
    });

    test('says the model was modified, and what it was trained on', () {
      final notice = textOf(entries.first);
      expect(notice, contains('modified version of FunctionGemma'));
      expect(notice, contains('prohibited_use_policy'));
      expect(notice, contains('MASSIVE 1.1'));
      expect(notice, contains('creativecommons.org/licenses/by/4.0'));
      expect(notice, contains(currentModel.fileName));
    });

    test('has a copy of the terms, not only a link', () {
      final terms = textOf(entries.last);
      expect(terms, contains('Gemma Terms of Use'));
      expect(terms, contains('Distribution and Redistribution'));
      expect(terms, contains('FunctionGemma'));
      expect(terms.length, greaterThan(5000));
    });
  });
}
