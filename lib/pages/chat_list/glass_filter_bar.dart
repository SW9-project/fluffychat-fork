// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// The chat list filters as native Liquid Glass buttons in one platform
/// view, see `GlassFilterBar` in `LiquidGlassView.swift`. iOS 26+ only.
class GlassFilterBar extends StatefulWidget {
  final List<String> labels;

  /// Null when no filter matches, e.g. while a tag is being removed.
  final int? selectedIndex;
  final ValueChanged<int> onSelected;

  const GlassFilterBar({
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  static const String _viewType = 'fluffychat/glass_filter_bar';

  /// Horizontal drags and taps go to the native row, vertical drags still
  /// scroll the chat list.
  static final Set<Factory<OneSequenceGestureRecognizer>> _gestureRecognizers =
      {
        // Explicit types: inferred ones would both be the set's type.
        Factory<HorizontalDragGestureRecognizer>(
          HorizontalDragGestureRecognizer.new,
        ),
        Factory<TapGestureRecognizer>(TapGestureRecognizer.new),
      };

  @override
  State<GlassFilterBar> createState() => _GlassFilterBarState();
}

class _GlassFilterBarState extends State<GlassFilterBar> {
  MethodChannel? _channel;
  Map<String, Object?>? _sentState;

  Map<String, Object?> _state() {
    final theme = Theme.of(context);
    return {
      'labels': widget.labels,
      'selectedIndex': widget.selectedIndex,
      'tintColor': theme.colorScheme.primary.toARGB32(),
      'isDark': theme.brightness == Brightness.dark,
    };
  }

  void _sendState() {
    final channel = _channel;
    if (channel == null) return;
    final state = _state();
    if (const DeepCollectionEquality().equals(state, _sentState)) return;
    _sentState = state;
    channel.invokeMethod('update', state);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sendState();
  }

  @override
  void didUpdateWidget(GlassFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sendState();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  void _onPlatformViewCreated(int id) {
    _channel = MethodChannel('${GlassFilterBar._viewType}/$id')
      ..setMethodCallHandler((call) async {
        if (call.method != 'selected') return;
        final index = call.arguments as int;
        if (index < widget.labels.length) widget.onSelected(index);
      });
    _sendState();
  }

  @override
  Widget build(BuildContext context) => UiKitView(
    viewType: GlassFilterBar._viewType,
    creationParams: _state(),
    creationParamsCodec: const StandardMessageCodec(),
    onPlatformViewCreated: _onPlatformViewCreated,
    gestureRecognizers: GlassFilterBar._gestureRecognizers,
  );
}
