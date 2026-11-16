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
          .dependOnInheritedWidgetOfExactType<_SettingsOverride>()
          ?.settings ??
      context
          .dependOnInheritedWidgetOfExactType<_AccessibilityInherited>()
          ?.notifier
          ?.settings ??
      AccessibilitySettings.defaults;

  /// [child] sees [settings] instead of the live ones, such as one side of a
  /// preview. Changing settings below it still changes the live ones.
  static Widget withSettings({
    required AccessibilitySettings settings,
    required Widget child,
  }) => _SettingsOverride(settings: settings, child: child);

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

class _SettingsOverride extends InheritedWidget {
  final AccessibilitySettings settings;

  const _SettingsOverride({required this.settings, required super.child});

  @override
  bool updateShouldNotify(_SettingsOverride oldWidget) =>
      settings != oldWidget.settings;
}

class _AccessibilityInherited
    extends InheritedNotifier<AccessibilityController> {
  const _AccessibilityInherited({
    required super.notifier,
    required super.child,
  });
}

/// Multiplies the inherited text scale, which includes the system font size,
/// with the user's text scale, and makes all text bold in high contrast.
///
/// With [category], only that category's scale applies, on top of what is
/// already inherited: for example the chat list's own text size.
class AccessibilityTextScale extends StatelessWidget {
  final Widget child;
  final ScaleCategory category;

  /// A chat's own text scale applies on top, see
  /// [AccessibilitySettings.chatTextScale].
  final String? roomId;

  const AccessibilityTextScale({
    required this.child,
    this.category = ScaleCategory.text,
    this.roomId,
    super.key,
  });

  /// [base] multiplied by [factor], keeping nonlinear system scaling.
  static TextScaler multiply(TextScaler base, double factor) =>
      factor == 1.0 ? base : _MultipliedTextScaler(base, factor);

  /// The text scaler for text typed into the message input: the system scale
  /// times the user's input text scale. The inherited scaler already includes
  /// the user's text scale, so that is swapped for the input text scale.
  static TextScaler inputTextScaler(BuildContext context) {
    final settings = AccessibilityScope.of(context);
    return multiply(
      MediaQuery.textScalerOf(context),
      settings.inputTextScale / settings.textScale,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = AccessibilityScope.of(context);
    final textScale = roomId == null
        ? settings.onTop(category)
        : settings.messageScale(roomId) / settings.textScale;
    // Bold text is set once, at the top.
    final bold = category == ScaleCategory.text && settings.highContrast;
    if (textScale == 1.0 && !bold) return child;
    final data = MediaQuery.of(context);
    return MediaQuery(
      data: data.copyWith(
        textScaler: multiply(data.textScaler, textScale),
        boldText: data.boldText || bold,
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
/// of every [IconButton] and [PopupMenuButton] below it. With [button], that
/// button's own scale applies on top.
class AccessibilityIconButtons extends StatelessWidget {
  final Widget child;
  final AccessibleButton? button;

  const AccessibilityIconButtons({required this.child, this.button, super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AccessibilityScope.of(context);
    // 40 is the default minimum size of a Material 3 icon button.
    final style = IconButton.styleFrom(
      minimumSize: Size.square(40 * settings.touchTargetScale),
    );
    return IconTheme.merge(
      data: IconThemeData(size: settings.icon(24, button)),
      child: IconButtonTheme(
        data: IconButtonThemeData(
          style: style.merge(IconButtonTheme.of(context).style),
        ),
        child: child,
      ),
    );
  }
}

/// Shows [label] under [child], a button, while button labels are on.
class AccessibilityButtonLabel extends StatelessWidget {
  final String label;
  final Widget child;

  /// The label's color, by default the icon color around it.
  final Color? color;

  const AccessibilityButtonLabel({
    required this.label,
    required this.child,
    this.color,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (!AccessibilityScope.of(context).buttonLabels) return child;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: .min,
      children: [
        child,
        // The button already has the label as its tooltip and semantics.
        ExcludeSemantics(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color ?? theme.colorScheme.onSurfaceVariant,
              height: 1.0,
            ),
          ),
        ),
      ],
    );
  }
}
