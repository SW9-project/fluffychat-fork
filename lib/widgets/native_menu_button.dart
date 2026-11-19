// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// An iOS-only native `UIMenu` over [child], see `NativeMenuButton.swift`.
/// [onSelected] gets the index into [titles].
class NativeMenuButton extends StatelessWidget {
  final String label;
  final List<String> titles;

  /// SF Symbol names, one per title.
  final List<String> symbols;

  /// Indices of items shown in red, such as leave.
  final List<int> destructive;
  final ValueChanged<int> onSelected;
  final Widget child;

  const NativeMenuButton({
    required this.label,
    required this.titles,
    required this.symbols,
    required this.onSelected,
    required this.child,
    this.destructive = const [],
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final params = {
      'label': label,
      'titles': titles,
      'symbols': symbols,
      'destructive': destructive,
      'isDark': Theme.of(context).brightness == Brightness.dark,
      // The app's text size, system Dynamic Type included, relative to the
      // 17pt body text.
      'textScale': MediaQuery.textScalerOf(context).scale(17) / 17,
    };
    return Stack(
      alignment: Alignment.center,
      children: [
        child,
        Positioned.fill(
          child: UiKitView(
            // A new key recreates the view, which reads its parameters once.
            key: ValueKey(const DeepCollectionEquality().hash(params)),
            viewType: 'fluffychat/menu_button',
            creationParams: params,
            creationParamsCodec: const StandardMessageCodec(),
            gestureRecognizers: {Factory(EagerGestureRecognizer.new)},
            onPlatformViewCreated: (id) =>
                MethodChannel(
                  'fluffychat/menu_button/$id',
                ).setMethodCallHandler((call) async {
                  if (call.method != 'selected' || !context.mounted) return;
                  onSelected(call.arguments as int);
                }),
          ),
        ),
      ],
    );
  }
}
