// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:material_ui/material_ui.dart';

/// A group of settings tiles. On iOS an inset rounded card with dividers, on
/// Android every tile in its own rounded container with small gaps between
/// them, like the system settings of Android 16 and newer.
class SettingsSection extends StatelessWidget {
  final List<Widget> children;

  /// Where the iOS separators start, at the text of the tiles.
  final double dividerIndent;

  const SettingsSection({
    required this.children,
    this.dividerIndent = 56,
    super.key,
  });

  /// The page behind the sections.
  static Color backgroundColor(ThemeData theme) => theme.cupertinoStyle
      ? theme.brightness == Brightness.light
            ? theme.colorScheme.surfaceContainerLow
            : theme.colorScheme.surface
      : theme.colorScheme.surfaceContainer;

  static Color _tileColor(ThemeData theme) => theme.cupertinoStyle
      ? theme.brightness == Brightness.light
            ? theme.colorScheme.surface
            : theme.colorScheme.surfaceContainerLow
      : theme.colorScheme.surfaceBright;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _tileColor(theme);
    final last = children.length - 1;

    if (theme.cupertinoStyle) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(26),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (i, child) in children.indexed) ...[
                child,
                if (i < last) Divider(height: 0.5, indent: dividerIndent),
              ],
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        spacing: 2,
        children: [
          for (final (i, child) in children.indexed)
            Material(
              color: color,
              clipBehavior: Clip.antiAlias,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(i == 0 ? 24 : 4),
                bottom: Radius.circular(i == last ? 24 : 4),
              ),
              child: child,
            ),
        ],
      ),
    );
  }
}

/// The title above a group of settings in a [SettingsList]. Small and grey
/// on iOS, a bold tile in the secondary color with Material.
class SettingsHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const SettingsHeader(this.title, {this.subtitle, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = this.subtitle;
    if (!theme.cupertinoStyle) {
      return ListTile(
        title: Text(
          title,
          style: TextStyle(
            color: theme.colorScheme.secondary,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: subtitle == null ? null : Text(subtitle),
      );
    }
    final style = theme.textTheme.bodySmall?.copyWith(
      fontSize: 13,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 6),
      child: Column(
        crossAxisAlignment: .start,
        children: [
          Text(title, style: style),
          if (subtitle != null) Text(subtitle, style: style),
        ],
      ),
    );
  }
}

/// The tiles of a settings page. On iOS every [SettingsHeader] and every
/// [Divider] in [children] starts a new [SettingsSection], with Material the
/// children stay one plain list.
class SettingsList extends StatelessWidget {
  final List<Widget> children;

  /// Of the Material list only.
  final CrossAxisAlignment crossAxisAlignment;

  const SettingsList({
    required this.children,
    this.crossAxisAlignment = .center,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (!Theme.of(context).cupertinoStyle) {
      return Column(crossAxisAlignment: crossAxisAlignment, children: children);
    }
    final groups = <(SettingsHeader?, List<Widget>)>[(null, [])];
    for (final child in children) {
      if (child is SettingsHeader) {
        groups.add((child, []));
      } else if (child is Divider) {
        groups.add((null, []));
      } else {
        groups.last.$2.add(child);
      }
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          for (final (header, tiles) in groups)
            if (tiles.isNotEmpty || header != null) ...[
              ?header,
              if (tiles.isNotEmpty)
                SettingsSection(dividerIndent: 16, children: tiles),
            ],
        ],
      ),
    );
  }
}

/// A settings icon: on iOS white in a colored rounded square like in the
/// Settings app, with Material just the outlined icon.
class SettingsIcon extends StatelessWidget {
  final IconData material;
  final IconData cupertino;
  final Color color;

  const SettingsIcon(this.material, this.cupertino, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    if (!Theme.of(context).cupertinoStyle) return Icon(material);
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(color, context),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(cupertino, size: 19, color: Colors.white),
    );
  }
}

/// The chevron of iOS at the end of tiles which open a page.
Widget? settingsChevron(ThemeData theme) => theme.cupertinoStyle
    ? Icon(
        Icons.chevron_right,
        color: theme.colorScheme.onSurfaceVariant.withAlpha(128),
      )
    : null;
