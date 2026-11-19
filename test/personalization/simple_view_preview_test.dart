// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui' as ui;

import 'package:fluffychat/personalization/simple_view_preview_scene.dart';
import 'package:fluffychat/personalization/simplified_interface.dart';
import 'package:fluffychat/personalization/simplified_interface_widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences store;
  late SimplifiedInterfaceController controller;
  late SimpleViewPreviewScene scene;
  var taps = 0;
  const media = MediaQueryData(
    size: Size(360, 800),
    devicePixelRatio: 1,
    textScaler: TextScaler.linear(1.6),
  );
  final theme = ThemeData.dark(useMaterial3: true);

  Widget screen(BuildContext context) {
    final state = SimplifiedInterfaceScope.maybeOf(context)!;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Real account', style: Theme.of(context).textTheme.titleLarge),
          Text('Width: ${MediaQuery.sizeOf(context).width}'),
          Text('Text: ${MediaQuery.textScalerOf(context).scale(10)}'),
          if (state.enabled)
            for (final id in state.quickAccessFor('account')) Text(id),
          if (!state.enabled || !state.preferences.cleanHome)
            const Text('Last message and time'),
          FilledButton(
            onPressed: () => taps++,
            child: const Text('Open conversation'),
          ),
        ],
      ),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
    controller = SimplifiedInterfaceController(store);
    await controller.setQuickAccess('account', ['Alice']);
    scene = SimpleViewPreviewScene(
      mediaQuery: media,
      theme: theme,
      controller: controller,
      screen: screen,
      account: 'account',
    );
    taps = 0;
  });
  tearDown(() => controller.dispose());

  Future<Uint8List> realPixels(WidgetTester tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: media,
          child: Theme(
            data: theme,
            child: SimplifiedInterfaceScope(
              controller: controller,
              child: RepaintBoundary(
                key: key,
                child: Builder(builder: screen),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
    final data = await tester.runAsync(
      () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    image!.dispose();
    return Uint8List.fromList(data!.buffer.asUint8List());
  }

  Future<Uint8List> previewPixels(
    WidgetTester tester, {
    required bool enabled,
    SimpleViewPreferences? preferences,
    List<String>? ids,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 180,
            child: SimplifiedInterfacePreview(
              enabled: enabled,
              preferences: preferences,
              selectedIds: ids,
              scene: scene,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1050));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(image.width, 360);
    expect(image.height, 800);
    final data = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    await tester.tap(find.byType(RawImage));
    await tester.pump();
    expect(taps, 0);
    return Uint8List.fromList(data!.buffer.asUint8List());
  }

  testWidgets(
    'current preview is pixel-identical to the real renderer at personalized scale',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final actual = await realPixels(tester);
      final preview = await previewPixels(tester, enabled: false);
      expect(listEquals(actual, preview), true);
      expect(controller.enabled, false);
      expect(controller.revision, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'proposed image matches applying the draft without saving it first',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final stored = {for (final key in store.getKeys()) key: store.get(key)};
      const draft = SimpleViewPreferences(
        quickAccess: SimpleQuickAccess.chosen,
        cleanHome: true,
      );
      final proposed = await previewPixels(
        tester,
        enabled: true,
        preferences: draft,
        ids: ['Bob'],
      );
      expect(controller.enabled, false);
      expect(controller.quickAccessFor('account'), ['Alice']);
      expect({for (final key in store.getKeys()) key: store.get(key)}, stored);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => controller.applyPreferences(
          draft,
          enabled: true,
          skipPreview: false,
          accountId: 'account',
          quickAccessIds: ['Bob'],
        ),
      );
      final applied = await realPixels(tester);
      expect(listEquals(proposed, applied), true);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
