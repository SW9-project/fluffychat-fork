// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import 'accessibility_scope.dart';
import 'simple_view_conversations.dart';
import 'simple_view_preview_scene.dart';
import 'simple_view_setup.dart';
import 'simplified_interface.dart';
import 'simplified_interface_l10n.dart';

class SimplifiedInterfaceSwitch extends StatelessWidget {
  const SimplifiedInterfaceSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = SimplifiedInterfaceScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();
    final text = SimplifiedInterfaceL10n.of(context);
    final theme = Theme.of(context);
    final sizes = AccessibilityScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(text.simpleView, style: theme.textTheme.bodyMedium),
          ),
          // Only while on: changing choices must not switch the view as a side effect.
          if (controller.enabled)
            TextButton(
              key: const Key('simple_personalize'),
              style: TextButton.styleFrom(
                minimumSize: Size(sizes.touchTarget(48), sizes.buttonBox(48)),
              ),
              onPressed: () => requestSimpleViewChange(
                context,
                controller,
                true,
                personalize: true,
              ),
              child: Text(text.edit),
            ),
          Semantics(
            label: text.simpleView,
            child: Switch.adaptive(
              key: const Key('simplified_interface_switch'),
              value: controller.enabled,
              onChanged: (value) =>
                  requestSimpleViewChange(context, controller, value),
            ),
          ),
        ],
      ),
    );
  }
}

/// A passive, full-screen rendering of the actual Chats page. It uses the
/// original viewport and theme, then scales the whole screen as one image.
class SimplifiedInterfacePreview extends StatefulWidget {
  final bool enabled;
  final SimpleViewPreferences? preferences;
  final List<String>? selectedIds;
  final SimpleViewPreviewScene? scene;

  const SimplifiedInterfacePreview({
    required this.enabled,
    this.preferences,
    this.selectedIds,
    this.scene,
    super.key,
  });

  @override
  State<SimplifiedInterfacePreview> createState() =>
      _SimplifiedInterfacePreviewState();
}

class _SimplifiedInterfacePreviewState
    extends State<SimplifiedInterfacePreview> {
  SimplifiedInterfaceController? _preview;
  final _boundary = GlobalKey();
  Timer? _captureTimer;
  ui.Image? _image;
  bool _scheduled = false;
  int _generation = 0;

  void _scheduleImage(double pixelRatio) {
    if (_scheduled) return;
    _scheduled = true;
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      // Let avatars load and fade in before freezing this frame. Until then
      // the live renderer is shown, so waiting costs nothing visible.
      _captureTimer = Timer(const Duration(seconds: 1), () async {
        final boundary = _boundary.currentContext?.findRenderObject();
        if (boundary is! RenderRepaintBoundary) return;
        ui.Image image;
        try {
          image = await boundary.toImage(pixelRatio: pixelRatio);
        } catch (_) {
          // Keep the real passive renderer if capture is unsupported.
          return;
        }
        if (!mounted || generation != _generation) {
          image.dispose();
          return;
        }
        setState(() => _image = image);
      });
    });
  }

  @override
  void didUpdateWidget(covariant SimplifiedInterfacePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled == widget.enabled &&
        identical(oldWidget.preferences, widget.preferences) &&
        identical(oldWidget.scene, widget.scene) &&
        listEquals(oldWidget.selectedIds, widget.selectedIds)) {
      return;
    }
    _generation++;
    _captureTimer?.cancel();
    _image?.dispose();
    _image = null;
    _scheduled = false;
    _preview?.dispose();
    _preview = null;
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    _image?.dispose();
    _preview?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scene =
        widget.scene ??
        SimpleViewConversations.fromContext(
          context,
        )?.createPreview?.call(context);
    if (scene == null) {
      return Text(
        Localizations.localeOf(context).languageCode == 'es'
            ? 'Vista previa no disponible.'
            : 'Preview unavailable.',
      );
    }
    final viewport = scene.mediaQuery.size;
    if (_image case final image?) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AspectRatio(
          aspectRatio: image.width / image.height,
          child: RawImage(
            image: image,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      );
    }
    _scheduleImage(scene.mediaQuery.devicePixelRatio.clamp(1, 3));
    _preview ??= SimplifiedInterfaceController.preview(
      scene.controller,
      enabled: widget.enabled,
      preferences: widget.preferences ?? scene.controller.preferences,
      account: scene.account,
      selectedIds: widget.selectedIds,
    );
    Widget screen = MediaQuery(
      data: scene.mediaQuery,
      child: Theme(
        data: scene.theme,
        child: SimplifiedInterfaceScope(
          key: ObjectKey(_preview),
          controller: _preview,
          child: Builder(builder: scene.screen),
        ),
      ),
    );
    if (scene.accessibility case final accessibility?) {
      screen = AccessibilityScope(controller: accessibility, child: screen);
    }
    return Semantics(
      image: true,
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          // Full width, and only as tall as the screen's content needs.
          child: SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: viewport.width,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: scene.fitsContent
                        ? double.infinity
                        : viewport.height,
                  ),
                  child: AbsorbPointer(
                    child: FocusScope(
                      canRequestFocus: false,
                      child: HeroMode(
                        enabled: false,
                        child: RepaintBoundary(key: _boundary, child: screen),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
