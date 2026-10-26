// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:material_ui/material_ui.dart';

import 'accessibility_controller.dart';
import 'accessibility_settings.dart';

/// Provides the [AccessibilityController] to the widget tree. Widgets that
/// read [AccessibilityScope.of] rebuild when a setting changes.
class AccessibilityScope extends StatefulWidget {
  final Widget child;

  /// Only for tests. By default the controller uses [AppSettings.store].
  final AccessibilityController? controller;

  const AccessibilityScope({required this.child, this.controller, super.key});

  /// The current settings. Registers the caller for rebuilds.
  static AccessibilitySettings of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_AccessibilityInherited>()
          ?.notifier
          ?.settings ??
      AccessibilitySettings.defaults;

  /// The controller, for changing settings. Does not register for rebuilds.
  static AccessibilityController controllerOf(BuildContext context) =>
      maybeControllerOf(context)!;

  static AccessibilityController? maybeControllerOf(BuildContext context) =>
      context
          .getInheritedWidgetOfExactType<_AccessibilityInherited>()
          ?.notifier;

  @override
  State<AccessibilityScope> createState() => _AccessibilityScopeState();
}

class _AccessibilityScopeState extends State<AccessibilityScope> {
  late final AccessibilityController _controller =
      widget.controller ?? AccessibilityController(AppSettings.store);

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _AccessibilityInherited(notifier: _controller, child: widget.child);
}

class _AccessibilityInherited
    extends InheritedNotifier<AccessibilityController> {
  const _AccessibilityInherited({
    required super.notifier,
    required super.child,
  });
}

/// Multiplies the inherited text scale, which includes the system font size,
/// with the user's text scale.
class AccessibilityTextScale extends StatelessWidget {
  final Widget child;

  const AccessibilityTextScale({required this.child, super.key});

  /// [base] multiplied by [factor], keeping nonlinear system scaling.
  static TextScaler multiply(TextScaler base, double factor) =>
      factor == 1.0 ? base : _MultipliedTextScaler(base, factor);

  /// The text scaler for text typed into the message input: the app-wide
  /// scale times the user's input text scale.
  static TextScaler inputTextScaler(BuildContext context) => multiply(
    MediaQuery.textScalerOf(context),
    AccessibilityScope.of(context).inputTextScale,
  );

  @override
  Widget build(BuildContext context) {
    final textScale = AccessibilityScope.of(context).textScale;
    if (textScale == 1.0) return child;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: multiply(MediaQuery.textScalerOf(context), textScale),
      ),
      child: child,
    );
  }
}

class _MultipliedTextScaler extends TextScaler {
  final TextScaler base;
  final double factor;

  const _MultipliedTextScaler(this.base, this.factor);

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * factor;

  @override
  bool operator ==(Object other) =>
      other is _MultipliedTextScaler &&
      other.base == base &&
      other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}

/// Scales icon size (button scale) and minimum hit area (touch target scale)
/// of every [IconButton] and [PopupMenuButton] below it.
class AccessibilityIconButtons extends StatelessWidget {
  final Widget child;

  const AccessibilityIconButtons({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AccessibilityScope.of(context);
    // 40 is the default minimum size of a Material 3 icon button.
    final style = IconButton.styleFrom(
      minimumSize: Size.square(40 * settings.touchTargetScale),
    );
    return IconTheme.merge(
      data: IconThemeData(size: settings.icon()),
      child: IconButtonTheme(
        data: IconButtonThemeData(
          style: style.merge(IconButtonTheme.of(context).style),
        ),
        child: child,
      ),
    );
  }
}
