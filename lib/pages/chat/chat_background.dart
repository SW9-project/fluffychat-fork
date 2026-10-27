// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';
import 'dart:ui' as ui;

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/utils/chat_wallpaper.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// Fills the available space with the given [wallpaper]. Draws nothing for
/// [ChatWallpaperType.none] so that the background of the page stays blank.
class ChatWallpaperBackground extends StatelessWidget {
  final ChatWallpaper wallpaper;
  final bool isThumbnail;

  const ChatWallpaperBackground({
    required this.wallpaper,
    this.isThumbnail = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final url = wallpaper.url;
    return switch (wallpaper.type) {
      ChatWallpaperType.none => const SizedBox.expand(),
      ChatWallpaperType.pattern => const ChatBackground(),
      ChatWallpaperType.image => LayoutBuilder(
        builder: (context, constraints) => Opacity(
          opacity: wallpaper.opacity,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: wallpaper.blur,
              sigmaY: wallpaper.blur,
            ),
            child: MxcImage(
              key: ValueKey('$url-$isThumbnail'),
              cacheKey: isThumbnail ? null : url.toString(),
              uri: url,
              fit: BoxFit.cover,
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              isThumbnail: isThumbnail,
              placeholder: (_) => const SizedBox.expand(),
            ),
          ),
        ),
      ),
    };
  }
}

/// Chat wallpaper pattern in the style of Telegram: A soft four color
/// gradient with a pattern of small doodles on top.
class ChatBackground extends StatelessWidget {
  const ChatBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RepaintBoundary(
      child: CustomPaint(
        painter: _ChatBackgroundPainter(
          colors: theme.chatBackgroundColors,
          patternColor: theme.chatBackgroundPatternColor,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _ChatBackgroundPainter extends CustomPainter {
  final List<Color> colors;
  final Color patternColor;

  _ChatBackgroundPainter({required this.colors, required this.patternColor});

  static const double _cellSize = 72;

  static const List<IconData> _doodles = [
    Icons.chat_bubble_outline,
    Icons.star_border,
    Icons.favorite_border,
    Icons.music_note_outlined,
    Icons.camera_alt_outlined,
    Icons.emoji_emotions_outlined,
    Icons.cake_outlined,
    Icons.pets_outlined,
    Icons.local_cafe_outlined,
    Icons.flight_outlined,
    Icons.beach_access_outlined,
    Icons.brush_outlined,
    Icons.headphones_outlined,
    Icons.lightbulb_outline,
    Icons.send_outlined,
    Icons.mail_outline,
    Icons.rocket_launch_outlined,
    Icons.sports_esports_outlined,
    Icons.eco_outlined,
    Icons.cloud_outlined,
    Icons.nightlight_outlined,
    Icons.anchor_outlined,
    Icons.icecream_outlined,
    Icons.local_florist_outlined,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Bilinear gradient between the four corner colors:
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [colors[0], colors[1]],
        ).createShader(rect),
    );
    canvas.saveLayer(rect, Paint());
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [colors[2], colors[3]],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    canvas.restore();

    // Doodle pattern. Seeded so it stays the same on every repaint:
    final painters = {
      for (final icon in _doodles)
        icon: TextPainter(
          textDirection: TextDirection.ltr,
          text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(
              fontFamily: icon.fontFamily,
              package: icon.fontPackage,
              fontSize: 26,
              color: patternColor,
            ),
          ),
        )..layout(),
    };
    final random = Random(42);
    for (var y = 0.0; y < size.height; y += _cellSize) {
      for (var x = 0.0; x < size.width; x += _cellSize) {
        final painter = painters[_doodles[random.nextInt(_doodles.length)]]!;
        final center = Offset(
          x + _cellSize / 2 + (random.nextDouble() - 0.5) * _cellSize * 0.4,
          y + _cellSize / 2 + (random.nextDouble() - 0.5) * _cellSize * 0.4,
        );
        final scale = 0.75 + random.nextDouble() * 0.5;
        canvas
          ..save()
          ..translate(center.dx, center.dy)
          ..rotate((random.nextDouble() - 0.5) * pi / 2)
          ..scale(scale);
        painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
        canvas.restore();
      }
    }
    for (final painter in painters.values) {
      painter.dispose();
    }
  }

  @override
  bool shouldRepaint(_ChatBackgroundPainter oldDelegate) =>
      oldDelegate.patternColor != patternColor ||
      !listEquals(oldDelegate.colors, colors);
}
