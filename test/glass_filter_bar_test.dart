// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later


import 'package:fluffychat/pages/chat_list/glass_filter_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('GlassFilterBar builds its UiKitView without assertions', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (call) async => null,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: GlassFilterBar(
          labels: const ['All', 'Unread'],
          selectedIndex: 0,
          onSelected: (_) {},
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
