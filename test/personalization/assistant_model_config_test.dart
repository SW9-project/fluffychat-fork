// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/personalization/model/assistant_model_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile and host configurations select the same model weights', () {
    final manifest =
        jsonDecode(File('assets/models/model.json').readAsStringSync()) as Map;
    expect(manifest['id'], AssistantModelConfig.id);
    expect(manifest['filename'], AssistantModelConfig.fileName);
    expect(manifest['sha256'], AssistantModelConfig.sha256);
    expect(manifest['sizeBytes'], AssistantModelConfig.sizeBytes);
  });
}
