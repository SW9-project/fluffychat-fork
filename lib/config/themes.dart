// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/personalization/accessibility_scope.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

abstract class FluffyThemes {
  static const double columnWidth = 380.0;

  static const double maxTimelineWidth = columnWidth * 2;

  static const double navRailWidth = 80.0;

  static bool isColumnModeByWidth(double width) =>
      width > columnWidth * 2 + navRailWidth;

  static bool isColumnMode(BuildContext context) =>
      isColumnModeByWidth(MediaQuery.sizeOf(context).width);

  static bool isThreeColumnMode(BuildContext context) =>
      MediaQuery.sizeOf(context).width > FluffyThemes.columnWidth * 3.5;

  static LinearGradient backgroundGradient(BuildContext context, int alpha) {
    final colorScheme = Theme.of(context).colorScheme;
    return LinearGradient(
      begin: Alignment.topCenter,
      colors: [
        colorScheme.primaryContainer.withAlpha(alpha),
        colorScheme.secondaryContainer.withAlpha(alpha),
        colorScheme.tertiaryContainer.withAlpha(alpha),
        colorScheme.primaryContainer.withAlpha(alpha),
      ],
    );
  }

  static const Duration animationDuration = Duration(milliseconds: 250);
  static const Curve animationCurve = Curves.easeInOut;

  static ThemeData buildTheme(
    BuildContext context,
    Brightness brightness, [
    Color? seed,
  ]) {
    final isLight = brightness == Brightness.light;
    final seedColor = seed ?? Color(AppSettings.colorSchemeSeedInt.value);
    // Telegram uses the accent color as it is instead of a tonal variant of
    // it, so we only clamp the lightness to keep it readable.
    final seedHsl = HSLColor.fromColor(seedColor);
    final primary = seedHsl
        .withLightness(
          seedHsl.lightness.clamp(isLight ? 0.3 : 0.5, isLight ? 0.56 : 0.65),
        )
        .toColor();
    final colorScheme =
        ColorScheme.fromSeed(
          brightness: brightness,
          seedColor: seedColor,
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
        ).copyWith(
          primary: primary,
          onPrimary:
              ThemeData.estimateBrightnessForColor(primary) == Brightness.dark
              ? Colors.white
              : Colors.black,
          surface: isLight ? Colors.white : const Color(0xFF17212B),
          onSurface: isLight ? Colors.black : Colors.white,
          onSurfaceVariant: isLight
              ? const Color(0xFF707579)
              : const Color(0xFF7F91A4),
          surfaceContainerLowest: isLight
              ? Colors.white
              : const Color(0xFF131C25),
          surfaceContainerLow: isLight
              ? const Color(0xFFF7F7F7)
              : const Color(0xFF1B2631),
          surfaceContainer: isLight
              ? const Color(0xFFF1F1F1)
              : const Color(0xFF1E2A36),
          surfaceContainerHigh: isLight
              ? const Color(0xFFEBEBEB)
              : const Color(0xFF242F3D),
          surfaceContainerHighest: isLight
              ? const Color(0xFFE4E4E4)
              : const Color(0xFF2B3949),
          surfaceTint: Colors.transparent,
        );
    final isColumnMode = FluffyThemes.isColumnMode(context);
    final a11y = AccessibilityScope.of(context);
    final dividerColor = isLight
        ? const Color(0xFFE6E6E6)
        : const Color(0xFF0E1621);
    final theme = ThemeData(
      visualDensity: VisualDensity.standard,
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      dividerColor: dividerColor,
      dividerTheme: DividerThemeData(color: dividerColor, thickness: 0.5),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: const StadiumBorder(),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          iconColor: colorScheme.onSurface,
          disabledIconColor: colorScheme.onSurface,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: colorScheme.onSurface.withAlpha(128),
        selectionHandleColor: colorScheme.secondary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
        ),
        contentPadding: const EdgeInsets.all(12),
      ),
      chipTheme: ChipThemeData(
        showCheckmark: false,
        backgroundColor: colorScheme.surfaceContainer,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        ),
      ),
      appBarTheme: AppBarTheme(
        toolbarHeight: a11y.buttonBox(isColumnMode ? 72 : 56),
        leadingWidth: a11y.buttonBox(56),
        iconTheme: IconThemeData(
          color: colorScheme.onSurface,
          size: a11y.icon(),
        ),
        actionsIconTheme: IconThemeData(
          color: colorScheme.onSurfaceVariant,
          size: a11y.icon(),
        ),
        surfaceTintColor: colorScheme.surface,
        backgroundColor: colorScheme.surface,
        scrolledUnderElevation: 0,
        actionsPadding: isColumnMode
            ? const EdgeInsets.symmetric(horizontal: 16.0)
            : null,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: brightness.reversed,
          statusBarBrightness: brightness,
          systemNavigationBarIconBrightness: brightness.reversed,
          systemNavigationBarColor: colorScheme.surface,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(width: 1, color: colorScheme.primary),
          shape: RoundedRectangleBorder(
            side: BorderSide(color: colorScheme.primary),
            borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        strokeCap: StrokeCap.round,
        color: colorScheme.primary,
        refreshBackgroundColor: colorScheme.primaryContainer,
      ),
      snackBarTheme: isColumnMode
          ? const SnackBarThemeData(
              showCloseIcon: true,
              behavior: SnackBarBehavior.floating,
              width: FluffyThemes.columnWidth * 1.5,
            )
          : const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.secondaryContainer,
          foregroundColor: colorScheme.onSecondaryContainer,
          elevation: 0,
          padding: const EdgeInsets.all(16),
          textStyle: const TextStyle(fontSize: 16),
        ),
      ),
    );
    return theme.copyWith(
      appBarTheme: theme.appBarTheme.copyWith(
        titleTextStyle: theme.textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
          fontSize: 19,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

extension on Brightness {
  Brightness get reversed =>
      this == Brightness.dark ? Brightness.light : Brightness.dark;
}

/// Telegram like colors for the chat timeline.
extension BubbleColorTheme on ThemeData {
  bool get _isLight => brightness == Brightness.light;

  /// Background of own messages.
  Color get bubbleColor =>
      _isLight ? const Color(0xFFEFFDDE) : const Color(0xFF2B5278);

  Color get onBubbleColor => _isLight ? Colors.black : Colors.white;

  /// Time, checkmarks and reply bars inside of own messages.
  Color get bubbleAccentColor =>
      _isLight ? const Color(0xFF4FAE4E) : const Color(0xFF8CC3F2);

  /// Background of messages from other users.
  Color get otherBubbleColor =>
      _isLight ? Colors.white : const Color(0xFF182533);

  /// Time inside of messages from other users.
  Color get otherBubbleAccentColor =>
      _isLight ? const Color(0xFFA1AAB3) : const Color(0xFF6D7F8F);

  /// Links and replies inside of messages.
  Color get bubbleLinkColor =>
      _isLight ? colorScheme.primary : colorScheme.primaryFixedDim;

  /// Date chips and state events on top of the chat background.
  Color get serviceMessageColor =>
      _isLight ? const Color(0x4D000000) : const Color(0xCC1E2C3A);

  /// The four corners of the default chat background gradient.
  List<Color> get chatBackgroundColors => _isLight
      ? const [
          Color(0xFFDBDDBB),
          Color(0xFF6BA587),
          Color(0xFFD5D88D),
          Color(0xFF88B884),
        ]
      : const [
          Color(0xFF0E1621),
          Color(0xFF13202E),
          Color(0xFF111C27),
          Color(0xFF0E1621),
        ];

  Color get chatBackgroundPatternColor =>
      _isLight ? const Color(0x24000000) : const Color(0x0DFFFFFF);

  /// Unread counter of muted chats.
  Color get mutedBadgeColor =>
      _isLight ? const Color(0xFFC4C9CC) : const Color(0xFF3E546A);
}
