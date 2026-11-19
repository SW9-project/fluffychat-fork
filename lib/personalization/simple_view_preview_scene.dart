// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

import 'accessibility_controller.dart';
import 'simplified_interface.dart';

/// The real Chats renderer and its original viewport, captured before the dialog.
class SimpleViewPreviewScene {
  final MediaQueryData mediaQuery;
  final ThemeData theme;
  final SimplifiedInterfaceController controller;
  final AccessibilityController? accessibility;
  final WidgetBuilder screen;
  final String account;

  /// The screen sizes itself to its content, so it is shown whole, not cut at
  /// one viewport height.
  final bool fitsContent;

  const SimpleViewPreviewScene({
    required this.mediaQuery,
    required this.theme,
    required this.controller,
    required this.screen,
    required this.account,
    this.accessibility,
    this.fitsContent = false,
  });
}
