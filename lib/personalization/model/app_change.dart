// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// The app settings the assistant can change besides accessibility settings.
enum AppSetting {
  ownBubbleColor,
  otherBubbleColor,
  appColor,
  wallpaper,
  swipeToReply,
  doubleTapToReact,
  sendOnEnter,
  autoplayGifs,
  pinned,
  muted,
}

/// One checked change of an [AppSetting], not yet applied.
class AppChange {
  final AppSetting setting;

  /// The chat it is for, or null when it is for every chat.
  final String? roomId;

  /// An `int?` ARGB for colors (null is the default color), a `String?` for
  /// the wallpaper (`'none'`, `'pattern'`, null is the chat's default), and a
  /// `bool` for everything else.
  final Object? value;

  const AppChange(this.setting, this.roomId, this.value);

  @override
  bool operator ==(Object other) =>
      other is AppChange &&
      other.setting == setting &&
      other.roomId == roomId &&
      other.value == value;

  @override
  int get hashCode => Object.hash(setting, roomId, value);

  @override
  String toString() => 'AppChange($setting, $roomId, $value)';
}
