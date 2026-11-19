// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// A slider that is the native `UISlider` on iOS 26+, with its Liquid Glass
/// thumb and tick marks (see `GlassSliderFactory` in `LiquidGlassView.swift`),
/// and a [Slider.adaptive] elsewhere.
class GlassSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final SemanticFormatterCallback? semanticFormatterCallback;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  const GlassSlider({
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
    this.semanticFormatterCallback,
    this.onChangeStart,
    this.onChangeEnd,
    super.key,
  });

  /// More ticks than this would crowd the track, so the slider snaps without
  /// showing them.
  static const maxTicks = 21;

  @override
  State<GlassSlider> createState() => _GlassSliderState();
}

class _GlassSliderState extends State<GlassSlider> {
  MethodChannel? _channel;

  Map<String, Object?> _params(BuildContext context) {
    final theme = Theme.of(context);
    final divisions = widget.divisions;
    final value = widget.value.clamp(widget.min, widget.max);
    return {
      'value': value,
      'min': widget.min,
      'max': widget.max,
      'ticks': divisions != null && divisions < GlassSlider.maxTicks
          ? divisions + 1
          : 0,
      'enabled': widget.onChanged != null,
      'valueLabel':
          widget.semanticFormatterCallback?.call(value) ?? widget.label,
      'tintColor': theme.colorScheme.primary.toARGB32(),
      'isDark': theme.brightness == Brightness.dark,
    };
  }

  /// The native slider snaps to its ticks; without them it is snapped here.
  double _snap(double value) {
    final divisions = widget.divisions;
    if (divisions == null || divisions == 0) return value;
    final step = (widget.max - widget.min) / divisions;
    return (widget.min + ((value - widget.min) / step).round() * step).clamp(
      widget.min,
      widget.max,
    );
  }

  Future<void> _handle(MethodCall call) async {
    if (!mounted) return;
    switch (call.method) {
      case 'changeStart':
        widget.onChangeStart?.call(widget.value);
      case 'changed':
        final value = _snap((call.arguments as num).toDouble());
        if (value != widget.value) widget.onChanged?.call(value);
      case 'changeEnd':
        widget.onChangeEnd?.call(widget.value);
    }
  }

  void _update() => _channel?.invokeMethod('update', _params(context));

  @override
  void didUpdateWidget(GlassSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  // The theme, such as dark mode.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformInfos.supportsLiquidGlass) {
      return Slider.adaptive(
        value: widget.value,
        min: widget.min,
        max: widget.max,
        divisions: widget.divisions,
        label: widget.label,
        semanticFormatterCallback: widget.semanticFormatterCallback,
        onChanged: widget.onChanged,
        onChangeStart: widget.onChangeStart,
        onChangeEnd: widget.onChangeEnd,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        height: 48,
        child: UiKitView(
          viewType: 'fluffychat/glass_slider',
          creationParams: _params(context),
          creationParamsCodec: const StandardMessageCodec(),
          // Vertical drags still scroll the page.
          gestureRecognizers: {Factory(HorizontalDragGestureRecognizer.new)},
          onPlatformViewCreated: (id) =>
              _channel = MethodChannel('fluffychat/glass_slider/$id')
                ..setMethodCallHandler(_handle),
        ),
      ),
    );
  }
}
