// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// A translucent surface in the style of the iOS "Liquid Glass" material. It
/// blurs and saturates the content behind it, is lit from the top and has a
/// specular highlight along its rim.
class LiquidGlass extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;

  const LiquidGlass({
    required this.child,
    required this.borderRadius,
    super.key,
  });

  static final ui.ImageFilter _backdropFilter = ui.ImageFilter.compose(
    outer: ui.ColorFilter.matrix(_saturationMatrix(1.8)),
    inner: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
  );

  static List<double> _saturationMatrix(double saturation) {
    // Luminance weights of the sRGB color space:
    const r = 0.2126, g = 0.7152, b = 0.0722;
    final inverse = 1 - saturation;
    return [
      ...[inverse * r + saturation, inverse * g, inverse * b, 0, 0],
      ...[inverse * r, inverse * g + saturation, inverse * b, 0, 0],
      ...[inverse * r, inverse * g, inverse * b + saturation, 0, 0],
      ...[0, 0, 0, 1, 0],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    return CustomPaint(
      painter: _LiquidGlassShadowPainter(
        borderRadius: borderRadius,
        isLight: isLight,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: _backdropFilter,
          child: CustomPaint(
            painter: _LiquidGlassBodyPainter(
              borderRadius: borderRadius,
              isLight: isLight,
              tint: theme.colorScheme.surface.withValues(
                alpha: isLight ? 0.6 : 0.55,
              ),
            ),
            foregroundPainter: _LiquidGlassRimPainter(
              borderRadius: borderRadius,
              isLight: isLight,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Paints the shadow only outside of the glass. Otherwise the backdrop
/// filter would pick it up and make the glass look dirty.
class _LiquidGlassShadowPainter extends CustomPainter {
  final BorderRadius borderRadius;
  final bool isLight;

  const _LiquidGlassShadowPainter({
    required this.borderRadius,
    required this.isLight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = borderRadius.toRRect(Offset.zero & size);
    canvas.save();
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect((Offset.zero & size).inflate(64))
        ..addRRect(rrect),
    );
    canvas.drawRRect(
      rrect.shift(const Offset(0, 8)),
      Paint()
        ..color = Colors.black.withValues(alpha: isLight ? 0.12 : 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
    canvas.drawRRect(
      rrect.shift(const Offset(0, 1)),
      Paint()
        ..color = Colors.black.withValues(alpha: isLight ? 0.06 : 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LiquidGlassShadowPainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.isLight != isLight;
}

class _LiquidGlassBodyPainter extends CustomPainter {
  final BorderRadius borderRadius;
  final bool isLight;
  final Color tint;

  const _LiquidGlassBodyPainter({
    required this.borderRadius,
    required this.isLight,
    required this.tint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect);
    canvas.drawRRect(rrect, Paint()..color = tint);
    // Light from the top makes the surface look convex.
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: isLight ? 0.35 : 0.08),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: isLight ? 0.12 : 0.03),
          ],
          stops: const [0, 0.55, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_LiquidGlassBodyPainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.isLight != isLight ||
      oldDelegate.tint != tint;
}

class _LiquidGlassRimPainter extends CustomPainter {
  final BorderRadius borderRadius;
  final bool isLight;

  const _LiquidGlassRimPainter({
    required this.borderRadius,
    required this.isLight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect);
    final intensity = isLight ? 1.0 : 0.45;

    // Light refracting along the inner edge of the glass.
    canvas.drawRRect(
      rrect.deflate(1.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: 0.3 * intensity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    if (isLight) {
      canvas.drawRRect(
        rrect.deflate(0.25),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5
          ..color = Colors.black.withValues(alpha: 0.06),
      );
    }
    // Specular highlights on the top left and bottom right of the rim.
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.95 * intensity),
            Colors.white.withValues(alpha: 0.2 * intensity),
            Colors.white.withValues(alpha: 0.1 * intensity),
            Colors.white.withValues(alpha: 0.6 * intensity),
          ],
          stops: const [0, 0.4, 0.6, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_LiquidGlassRimPainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.isLight != isLight;
}
