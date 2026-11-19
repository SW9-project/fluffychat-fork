// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/personalization/accessibility_scope.dart';
import 'package:fluffychat/personalization/accessibility_settings.dart';
import 'package:flutter/foundation.dart';
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

  /// iOS and macOS follow Apple's design, every other platform Material 3
  /// Expressive.
  static bool isCupertinoPlatform(TargetPlatform platform) =>
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

  static ThemeData buildTheme(
    BuildContext context,
    Brightness brightness, [
    Color? seed,
  ]) {
    final isLight = brightness == Brightness.light;
    final seedColor = seed ?? Color(AppSettings.colorSchemeSeedInt.value);
    final cupertino = isCupertinoPlatform(defaultTargetPlatform);
    // Android builds its palettes from the wallpaper in the tonal spot
    // variant, so the app looks like the system around it.
    var colorScheme = cupertino
        ? _cupertinoColorScheme(seedColor, brightness)
        : ColorScheme.fromSeed(brightness: brightness, seedColor: seedColor);
    // The theme color tints accents only; the light background stays white.
    if (isLight) {
      colorScheme = colorScheme.copyWith(
        surface: Colors.white,
        surfaceContainerLowest: Colors.white,
        surfaceBright: Colors.white,
      );
    }
    final isColumnMode = FluffyThemes.isColumnMode(context);
    final a11y = AccessibilityScope.of(context);
    // High contrast: secondary text and outlines as strong as the main text,
    // and containers that stand out from the background.
    if (a11y.highContrast) {
      colorScheme = colorScheme.copyWith(
        onSurfaceVariant: colorScheme.onSurface,
        outline: colorScheme.onSurface,
        outlineVariant: colorScheme.onSurface.withAlpha(160),
        surfaceContainerLow: isLight
            ? const Color(0xFFEDEDED)
            : const Color(0xFF26323F),
        surfaceContainer: isLight
            ? const Color(0xFFE3E3E3)
            : const Color(0xFF2E3B4A),
        surfaceContainerHigh: isLight
            ? const Color(0xFFD9D9D9)
            : const Color(0xFF364556),
        surfaceContainerHighest: isLight
            ? const Color(0xFFCFCFCF)
            : const Color(0xFF3F4F62),
      );
    }
    final dividerColor = a11y.highContrast
        ? colorScheme.onSurface.withAlpha(128)
        : colorScheme.outlineVariant;
    // Spacing: Material's density moves controls apart or together, from
    // -2 (half the space) to +4 (twice the space).
    final density = ((a11y.spacingScale - 1) * 4).clamp(
      VisualDensity.minimumDensity,
      VisualDensity.maximumDensity,
    );
    final theme = ThemeData(
      visualDensity: VisualDensity(horizontal: density, vertical: density),
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      dividerColor: dividerColor,
      dividerTheme: DividerThemeData(
        color: dividerColor,
        thickness: cupertino ? 0.5 : 1,
      ),
      // Material keeps its own tonal, rounded square buttons. Both grow with
      // the icon, keeping the Material 3 padding around it: 16 for regular
      // buttons and 8 for small ones.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: cupertino ? colorScheme.primary : null,
        foregroundColor: cupertino ? colorScheme.onPrimary : null,
        shape: cupertino ? const CircleBorder() : null,
        iconSize: a11y.icon(),
        sizeConstraints: BoxConstraints.tight(Size.square(a11y.icon() + 32)),
        smallSizeConstraints: BoxConstraints.tight(
          Size.square(a11y.icon() + 16),
        ),
      ),
      // Material 3 Expressive menus: a rounded tonal card with inset items.
      popupMenuTheme: cupertino
          ? null
          : PopupMenuThemeData(
              color: colorScheme.surfaceContainerLow,
              surfaceTintColor: Colors.transparent,
              elevation: 3,
              menuPadding: const EdgeInsets.all(4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
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
      // Back and close buttons carry their label under the icon.
      actionIconTheme: a11y.buttonLabels
          ? ActionIconThemeData(
              backButtonIconBuilder: (context) => LabeledIcon(
                icon: Icon(
                  cupertino && !kIsWeb
                      ? Icons.arrow_back_ios_new_rounded
                      : Icons.arrow_back,
                ),
                label: MaterialLocalizations.of(context).backButtonTooltip,
              ),
              closeButtonIconBuilder: (context) => LabeledIcon(
                icon: const Icon(Icons.close),
                label: MaterialLocalizations.of(context).closeButtonTooltip,
              ),
            )
          : null,
      appBarTheme: AppBarTheme(
        // Room for the labels under the buttons of the bar.
        toolbarHeight:
            a11y.buttonBox(isColumnMode ? 72 : (cupertino ? 52 : 64)) +
            AccessibilityButtonLabel.heightOf(context),
        centerTitle: cupertino,
        leadingWidth: a11y.buttonBox(56, AccessibleButton.back),
        // The leading icon is the back button on most pages.
        iconTheme: IconThemeData(
          color: colorScheme.onSurface,
          size: a11y.icon(24, AccessibleButton.back),
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
      // iOS has no ripple: touches only highlight.
      splashFactory: cupertino ? NoSplash.splashFactory : null,
      // iOS buttons: plain, gray, tinted and filled capsules (UIButton
      // configurations) for text, outlined, elevated and filled buttons.
      textButtonTheme: cupertino
          ? TextButtonThemeData(style: _cupertinoButton(colorScheme))
          : null,
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: cupertino
            ? _cupertinoButton(colorScheme, background: const Color(0x1F767680))
            : OutlinedButton.styleFrom(
                side: BorderSide(width: 1, color: colorScheme.primary),
              ),
      ),
      filledButtonTheme: cupertino
          ? FilledButtonThemeData(
              style: _cupertinoButton(
                colorScheme,
                background: colorScheme.primary,
                foreground: colorScheme.onPrimary,
              ),
            )
          : null,
      progressIndicatorTheme: ProgressIndicatorThemeData(
        // ignore: deprecated_member_use
        year2023: false,
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
        style: cupertino
            ? _cupertinoButton(
                colorScheme,
                background: colorScheme.primary.withAlpha(38),
              ).copyWith(
                padding: const WidgetStatePropertyAll(EdgeInsets.all(16)),
              )
            : ElevatedButton.styleFrom(
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
          fontSize: a11y.appBarTitle(cupertino ? 17 : 22),
          fontWeight: cupertino ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }

  /// A UIKit button: a flat capsule that dims while pressed and turns gray
  /// when disabled. Without [background] it is a plain text button.
  static ButtonStyle _cupertinoButton(
    ColorScheme colorScheme, {
    Color? background,
    Color? foreground,
  }) {
    final fg = foreground ?? colorScheme.primary;
    final fgColor = WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? colorScheme.onSurface.withAlpha(77)
          : states.contains(WidgetState.pressed)
          ? fg.withValues(alpha: fg.a * 0.4)
          : fg,
    );
    return ButtonStyle(
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      side: const WidgetStatePropertyAll(BorderSide.none),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      textStyle: WidgetStatePropertyAll(
        TextStyle(
          fontSize: 17,
          fontWeight: background == null ? FontWeight.w400 : FontWeight.w600,
        ),
      ),
      foregroundColor: fgColor,
      iconColor: fgColor,
      backgroundColor: background == null
          ? null
          : WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? const Color(0x1F767680)
                  : states.contains(WidgetState.pressed)
                  ? background.withValues(alpha: background.a * 0.7)
                  : background,
            ),
    );
  }

  /// The system colors of iOS, tinted with the accent color like UIKit apps.
  static ColorScheme _cupertinoColorScheme(Color seed, Brightness brightness) {
    final isLight = brightness == Brightness.light;
    // The accent is used as it is, only clamped to stay readable.
    final seedHsl = HSLColor.fromColor(seed);
    final tint = seedHsl
        .withLightness(
          seedHsl.lightness.clamp(isLight ? 0.3 : 0.5, isLight ? 0.56 : 0.65),
        )
        .toColor();
    return ColorScheme.fromSeed(
      brightness: brightness,
      seedColor: seed,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    ).copyWith(
      primary: tint,
      onPrimary: ThemeData.estimateBrightnessForColor(tint) == Brightness.dark
          ? Colors.white
          : Colors.black,
      // systemBackground, label and secondaryLabel.
      surface: isLight ? Colors.white : Colors.black,
      onSurface: isLight ? Colors.black : Colors.white,
      onSurfaceVariant: isLight
          ? const Color(0xFF8A8A8E)
          : const Color(0xFF8D8D93),
      // systemGray6 to systemGray4.
      surfaceContainerLowest: isLight ? Colors.white : Colors.black,
      surfaceContainerLow: isLight
          ? const Color(0xFFF2F2F7)
          : const Color(0xFF1C1C1E),
      surfaceContainer: isLight
          ? const Color(0xFFF2F2F7)
          : const Color(0xFF1C1C1E),
      surfaceContainerHigh: isLight
          ? const Color(0xFFE5E5EA)
          : const Color(0xFF2C2C2E),
      surfaceContainerHighest: isLight
          ? const Color(0xFFD1D1D6)
          : const Color(0xFF3A3A3C),
      // separator and systemRed.
      outlineVariant: isLight
          ? const Color(0xFFC6C6C8)
          : const Color(0xFF38383A),
      error: isLight ? const Color(0xFFFF3B30) : const Color(0xFFFF453A),
      onError: Colors.white,
      surfaceTint: Colors.transparent,
    );
  }
}

extension on Brightness {
  Brightness get reversed =>
      this == Brightness.dark ? Brightness.light : Brightness.dark;
}

/// Colors of the chat timeline: tinted bubbles in the style of Messages on
/// iOS and of Google Messages on Android.
extension BubbleColorTheme on ThemeData {
  bool get cupertinoStyle => FluffyThemes.isCupertinoPlatform(platform);

  Color? get _customOwn => extension<CustomBubbleColor>()?.own;
  Color? get _customOther => extension<CustomBubbleColor>()?.other;

  /// Bubbles use [own] and [other] when set, see [CustomBubbleColor].
  ThemeData withBubbleColors(Color? own, Color? other) {
    // Both sides in one color would hide who sent what.
    if (other != null && other.toARGB32() == own?.toARGB32()) other = null;
    if (own == null && other == null) return this;
    return copyWith(
      extensions: [
        ...extensions.values,
        CustomBubbleColor(own: own, other: other),
      ],
    );
  }

  static Color _textOn(Color background) =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.light
      ? Colors.black
      : Colors.white;

  /// Background of own messages.
  Color get bubbleColor =>
      _customOwn ??
      (cupertinoStyle ? colorScheme.primary : colorScheme.primaryContainer);

  Color get onBubbleColor => _customOwn != null
      ? _textOn(_customOwn!)
      : cupertinoStyle
      ? colorScheme.onPrimary
      : colorScheme.onPrimaryContainer;

  /// Time, checkmarks and reply bars inside of own messages.
  Color get bubbleAccentColor => onBubbleColor.withAlpha(180);

  /// Background of messages from other users.
  Color get otherBubbleColor =>
      _customOther ?? colorScheme.surfaceContainerHigh;

  /// Text of messages from other users.
  Color get onOtherBubbleColor =>
      _customOther != null ? _textOn(_customOther!) : colorScheme.onSurface;

  /// Time inside of messages from other users.
  Color get otherBubbleAccentColor => _customOther != null
      ? onOtherBubbleColor.withAlpha(180)
      : colorScheme.onSurfaceVariant;

  /// Links and replies inside of messages from other users.
  Color get bubbleLinkColor => colorScheme.primary;

  /// Date chips and state events in the timeline.
  Color get serviceMessageColor => colorScheme.surfaceContainer;

  Color get onServiceMessageColor => colorScheme.onSurfaceVariant;

  /// The four corners of the default chat background gradient.
  List<Color> get chatBackgroundColors => brightness == Brightness.light
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

  Color get chatBackgroundPatternColor => brightness == Brightness.light
      ? const Color(0x24000000)
      : const Color(0x0DFFFFFF);

  /// Unread counter of muted chats.
  Color get mutedBadgeColor =>
      cupertinoStyle ? colorScheme.onSurfaceVariant : colorScheme.outline;
}

/// User chosen colors of own and other people's message bubbles.
class CustomBubbleColor extends ThemeExtension<CustomBubbleColor> {
  final Color? own;
  final Color? other;
  const CustomBubbleColor({this.own, this.other});

  @override
  CustomBubbleColor copyWith({Color? own, Color? other}) =>
      CustomBubbleColor(own: own ?? this.own, other: other ?? this.other);

  @override
  CustomBubbleColor lerp(CustomBubbleColor? other, double t) =>
      CustomBubbleColor(
        own: Color.lerp(own, other?.own, t),
        other: Color.lerp(this.other, other?.other, t),
      );
}
