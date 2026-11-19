// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/widgets/triple_tap_detector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<(List<String>, Finder)> pump(WidgetTester tester) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: TripleTapDetector(
            onTripleTap: () => calls.add('triple'),
            onDoubleTap: () => calls.add('double'),
            child: GestureDetector(
              onDoubleTap: () => calls.add('child double'),
              child: const ColoredBox(
                color: Colors.red,
                child: SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      ),
    );
    return (calls, find.byType(TripleTapDetector));
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.tap(f);
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('three quick taps fire once, child gestures still work', (
    tester,
  ) async {
    final (calls, box) = await pump(tester);
    for (var i = 0; i < 3; i++) {
      await tap(tester, box);
    }
    await tester.pump(kDoubleTapTimeout);
    expect(calls, ['child double', 'triple']);
  });

  testWidgets('two quick taps fire the double tap once the series ends', (
    tester,
  ) async {
    final (calls, box) = await pump(tester);
    await tap(tester, box);
    await tap(tester, box);
    expect(calls, ['child double']);
    await tester.pump(kDoubleTapTimeout);
    expect(calls, ['child double', 'double']);
  });

  testWidgets('slow taps do not fire', (tester) async {
    final (calls, box) = await pump(tester);
    for (var i = 0; i < 3; i++) {
      await tester.tap(box);
      await tester.pump(kDoubleTapTimeout * 2);
    }
    expect(calls, isEmpty);
  });

  testWidgets('a long press breaks the series', (tester) async {
    final (calls, box) = await pump(tester);
    await tap(tester, box);
    await tester.longPress(box);
    await tester.pump(const Duration(milliseconds: 100));
    await tap(tester, box);
    await tester.pump(kDoubleTapTimeout);
    expect(calls.contains('triple'), isFalse);
  });
}
