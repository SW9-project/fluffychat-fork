// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Which Material button is shown off iOS. On iOS [text] is a plain
/// `UIButton`, [outlined] and [elevated] are glass and [filled] is
/// prominent glass.
enum NativeButtonStyle { text, outlined, elevated, filled }

/// A labelled button that is a native `UIButton` on iOS 26+ (see
/// `NativeButtonFactory` in `LiquidGlassView.swift`) and the Material button
/// of [style] elsewhere. Gets its intrinsic size unless the parent forces one.
class NativeButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final NativeButtonStyle style;

  /// Shown off iOS.
  final IconData? icon;

  /// The SF Symbol shown on iOS, like `square.and.pencil`.
  final String? symbol;

  /// The native tint, the primary color by default.
  final Color? tint;

  /// Only used off iOS.
  final ButtonStyle? materialStyle;

  const NativeButton({
    required this.label,
    required this.onPressed,
    this.style = NativeButtonStyle.text,
    this.icon,
    this.symbol,
    this.tint,
    this.materialStyle,
    super.key,
  });

  @override
  State<NativeButton> createState() => _NativeButtonState();
}

class _NativeButtonState extends State<NativeButton> {
  MethodChannel? _channel;
  Size? _size;

  double _fontSize(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(17);

  Map<String, Object?> _params(BuildContext context) {
    final theme = Theme.of(context);
    return {
      'label': widget.label,
      'symbol': widget.symbol,
      'style': switch (widget.style) {
        NativeButtonStyle.text => 'plain',
        NativeButtonStyle.outlined || NativeButtonStyle.elevated => 'glass',
        NativeButtonStyle.filled => 'prominent',
      },
      'enabled': widget.onPressed != null,
      'fontSize': _fontSize(context),
      'tintColor': (widget.tint ?? theme.colorScheme.primary).toARGB32(),
      'isDark': theme.brightness == Brightness.dark,
    };
  }

  /// The native button answers with its intrinsic size.
  Future<void> _update() async {
    final channel = _channel;
    if (channel == null) return;
    final size = await channel.invokeListMethod<num>(
      'update',
      _params(context),
    );
    if (size == null || !mounted) return;
    final newSize = Size(size[0].toDouble(), size[1].toDouble());
    if (newSize != _size) setState(() => _size = newSize);
  }

  /// Until the native size arrives.
  Size _estimate(BuildContext context) {
    final fontSize = _fontSize(context);
    final painter = TextPainter(
      text: TextSpan(
        text: widget.label,
        style: TextStyle(fontSize: fontSize),
      ),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final width =
        painter.width + 32 + (widget.symbol != null ? fontSize + 6 : 0);
    final height = painter.height + 14;
    painter.dispose();
    return Size(width, height);
  }

  @override
  void didUpdateWidget(NativeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  // The theme, such as dark mode, and the text size.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformInfos.supportsLiquidGlass) return _material();
    final size = _size ?? _estimate(context);
    return SizedBox(
      width: size.width,
      height: size.height,
      child: UiKitView(
        viewType: 'fluffychat/native_button',
        creationParams: _params(context),
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (id) {
          _channel = MethodChannel('fluffychat/native_button/$id')
            ..setMethodCallHandler((call) async {
              if (call.method == 'pressed' && mounted) widget.onPressed?.call();
            });
          _update();
        },
      ),
    );
  }

  Widget _material() {
    final label = Text(
      widget.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final icon = widget.icon == null ? null : Icon(widget.icon);
    final onPressed = widget.onPressed;
    final style = widget.materialStyle;
    return switch (widget.style) {
      NativeButtonStyle.text =>
        icon == null
            ? TextButton(onPressed: onPressed, style: style, child: label)
            : TextButton.icon(
                onPressed: onPressed,
                style: style,
                icon: icon,
                label: label,
              ),
      NativeButtonStyle.outlined =>
        icon == null
            ? OutlinedButton(onPressed: onPressed, style: style, child: label)
            : OutlinedButton.icon(
                onPressed: onPressed,
                style: style,
                icon: icon,
                label: label,
              ),
      NativeButtonStyle.elevated =>
        icon == null
            ? ElevatedButton(onPressed: onPressed, style: style, child: label)
            : ElevatedButton.icon(
                onPressed: onPressed,
                style: style,
                icon: icon,
                label: label,
              ),
      NativeButtonStyle.filled =>
        icon == null
            ? FilledButton(onPressed: onPressed, style: style, child: label)
            : FilledButton.icon(
                onPressed: onPressed,
                style: style,
                icon: icon,
                label: label,
              ),
    };
  }
}
