// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:material_ui/material_ui.dart' show Colors, ThemeMode;

import '../accessibility_settings.dart';
import '../suggestions/suggestion.dart';
import 'app_change.dart';
import 'personalization_tools.dart';
import 'settings_intent_model.dart';

typedef F = PersonalizationTools;

enum RejectionReason {
  /// The model answered without calling a function.
  noCall,

  /// The function is not one the model was trained on.
  unknownFunction,

  /// The arguments are missing or have the wrong type or value.
  invalidArguments,
}

/// Why a valid call changes nothing.
enum UnchangedReason {
  /// The size is already at its minimum or maximum.
  atLimit,

  /// The setting is already as asked, or already normal for a reset.
  alreadySet,

  /// The bubbles of the other side already have the color.
  sameAsOtherSide,
}

/// What the Assist tab does with one call of the model.
sealed class AssistResult {
  const AssistResult();
}

/// A change to show with a preview and apply on confirmation.
class AssistProposal extends AssistResult {
  final ProposedCall call;
  final SettingsChange change;

  const AssistProposal(this.call, this.change);
}

/// The model asks the user to choose among [options], functions from
/// [PersonalizationTools.changeFunctions].
class AssistClarification extends AssistResult {
  final ProposedCall call;
  final List<String> options;

  const AssistClarification(this.call, this.options);
}

/// A change of an app setting to show with a preview and apply on
/// confirmation.
class AssistAppProposal extends AssistResult {
  final ProposedCall call;
  final AppChange change;

  const AssistAppProposal(this.call, this.change);
}

/// The call is valid but lacks a detail the app asks for: [parameter] is
/// `side` or `color`, and [options] are the values to choose from.
class AssistNeedsDetail extends AssistResult {
  final ProposedCall call;
  final String parameter;
  final List<String> options;

  /// The chat the change is for, once it is known.
  final String? roomId;

  const AssistNeedsDetail(this.call, this.parameter, this.options, this.roomId);
}

/// A change for one chat, but the app has to ask which chat: none was named,
/// or the name matches no chat or several. See
/// [ToolCallInterpreter.forChat].
class AssistNeedsChat extends AssistResult {
  final ProposedCall call;

  /// The name or username the user wrote, if any.
  final String? chatName;

  const AssistNeedsChat(this.call, this.chatName);
}

/// A valid call that changes nothing.
class AssistUnchanged extends AssistResult {
  final ProposedCall call;
  final UnchangedReason reason;

  /// The size at its limit, for [UnchangedReason.atLimit].
  final ScaleCategory? category;

  const AssistUnchanged(this.call, this.reason, [this.category]);
}

/// The simple view: not a settings change, so the Assist tab hands it to the
/// simplified interface, which confirms it with its own preview.
class AssistNotAvailable extends AssistResult {
  final ProposedCall call;

  const AssistNotAvailable(this.call);
}

/// The model decided the request is not about the app's look: `no_action`.
class AssistNoAction extends AssistResult {
  final ProposedCall call;

  const AssistNoAction(this.call);
}

/// No call, an unknown function or unusable arguments. The app never invents
/// a change in this case.
class AssistNoSuggestion extends AssistResult {
  final RejectionReason reason;
  final ProposedCall? call;

  const AssistNoSuggestion(this.reason, [this.call]);
}

/// Turns the model's calls into checked changes of [settings] and [theme].
///
/// Every argument is checked against `assets/personalization_tools.json`:
/// unknown functions, unknown enum values and missing required arguments are
/// rejected, never guessed. Steps outside 1 to 3 are clamped, and sizes are
/// clamped to their range. Nothing here applies anything.
class ToolCallInterpreter {
  final PersonalizationTools tools;
  final AccessibilitySettings settings;
  final ThemeMode theme;

  const ToolCallInterpreter({
    required this.tools,
    required this.settings,
    required this.theme,
  });

  static const _textTargets = {
    'all': ScaleCategory.text,
    'messages': ScaleCategory.messageText,
    'chat_list': ScaleCategory.chatListText,
    'titles': ScaleCategory.titleText,
    'message_input': ScaleCategory.inputText,
  };

  static const _buttons = {
    'send': AccessibleButton.send,
    'attach': AccessibleButton.attach,
    'emoji': AccessibleButton.emoji,
    'microphone': AccessibleButton.microphone,
    'back': AccessibleButton.back,
    'search': AccessibleButton.search,
    'menu': AccessibleButton.menu,
    'navigation': AccessibleButton.navigation,
  };

  static const _textCategories = [
    ScaleCategory.text,
    ScaleCategory.messageText,
    ScaleCategory.chatListText,
    ScaleCategory.titleText,
    ScaleCategory.inputText,
  ];

  static final _buttonCategories = [
    ScaleCategory.button,
    ScaleCategory.touchTarget,
    for (final b in AccessibleButton.values) b.category,
  ];

  /// The ARGB of each color the functions name, except `default`.
  static final colorValues = {
    'red': Colors.red.toARGB32(),
    'pink': Colors.pink.toARGB32(),
    'purple': Colors.purple.toARGB32(),
    'indigo': Colors.indigo.toARGB32(),
    'blue': Colors.blue.toARGB32(),
    'cyan': Colors.cyan.toARGB32(),
    'teal': Colors.teal.toARGB32(),
    'green': Colors.green.toARGB32(),
    'lime': Colors.lime.toARGB32(),
    'yellow': Colors.yellow.toARGB32(),
    'amber': Colors.amber.toARGB32(),
    'orange': Colors.orange.toARGB32(),
    'brown': Colors.brown.toARGB32(),
    'grey': Colors.blueGrey.toARGB32(),
  };

  static const _gestures = {
    'swipe_to_reply': AppSetting.swipeToReply,
    'double_tap_to_react': AppSetting.doubleTapToReact,
    'send_on_enter': AppSetting.sendOnEnter,
    'autoplay_gifs': AppSetting.autoplayGifs,
  };

  /// [roomId] is the chat of a call that was answered with
  /// [AssistNeedsChat].
  AssistResult interpret(ProposedCall? call, {String? roomId}) {
    if (call == null) return const AssistNoSuggestion(RejectionReason.noCall);
    if (!tools.declares(call.name)) {
      return AssistNoSuggestion(RejectionReason.unknownFunction, call);
    }
    for (final required in tools.requiredOf(call.name)) {
      if (call.args[required] == null) return _invalid(call);
    }
    try {
      return switch (call.name) {
        F.changeTextSize => _textSize(call),
        F.changeButtonSize => _buttonSize(call),
        F.changeSpacing => _scale(
          call,
          [ScaleCategory.spacing],
          'more',
          'less',
        ),
        F.changeLineSpacing => _scale(
          call,
          [ScaleCategory.lineSpacing],
          'more',
          'less',
        ),
        F.changeAvatarSize => _scale(
          call,
          [ScaleCategory.avatar],
          'bigger',
          'smaller',
        ),
        F.setReadAloud => _toggle(call, AccessibilityToggle.tripleTapToRead),
        F.setBubbleColor => _bubbleColor(call, roomId),
        F.setAppColor => _appColor(call),
        F.setWallpaper => _wallpaper(call, roomId),
        F.setGesture => _gesture(call),
        F.pinChat => _chatToggle(call, roomId, AppSetting.pinned),
        F.muteChat => _chatToggle(call, roomId, AppSetting.muted),
        F.setButtonLabels => _toggle(call, AccessibilityToggle.buttonLabels),
        F.setHighContrast => _toggle(call, AccessibilityToggle.highContrast),
        F.setTheme => _theme(call),
        F.resetSettings => _reset(call),
        F.setSimpleMode => AssistNotAvailable(call),
        F.askClarification => _clarification(call),
        F.noAction => AssistNoAction(call),
        _ => AssistNoSuggestion(RejectionReason.unknownFunction, call),
      };
    } on _Invalid {
      return _invalid(call);
    }
  }

  /// The change for the chat with [roomId], for a call that was answered with
  /// [AssistNeedsChat]. Text size changes only that chat's text.
  AssistResult forChat(ProposedCall call, String roomId) {
    if (call.name != F.changeTextSize) return interpret(call, roomId: roomId);
    try {
      // Steps of the whole message size, as the chat's slider shows it.
      final from = settings.messageScale(roomId);
      const range = AccessibilitySettings.chatTextRange;
      final size = _size(call, range);
      final to = range.normalize(
        size ?? from + _sign(call, 'bigger', 'smaller') * _amount(call, range),
      );
      if (to == from) return _unchanged(call, range);
      final below = settings.effective(ScaleCategory.messageText);
      return AssistProposal(
        call,
        SettingsChange(
          from: settings,
          to: settings.withChatText(roomId, to / below),
        ),
      );
    } on _Invalid {
      return _invalid(call);
    }
  }

  AssistResult _textSize(ProposedCall call) {
    final chat = _string(call, 'chat');
    final scope = _enum(call, 'scope');
    // A named chat always means that chat, also when the scope is left out.
    if (scope == 'one_chat' || (chat != null && chat.isNotEmpty)) {
      return AssistNeedsChat(call, chat?.isEmpty ?? true ? null : chat);
    }
    final target = _textTargets[_enum(call, 'target')]!;
    return _scale(call, [target], 'bigger', 'smaller');
  }

  AssistResult _buttonSize(ProposedCall call) {
    final button = _enum(call, 'button');
    // All buttons: the icons and the area that reacts to a tap. One button:
    // its own icon, and its box grows with it.
    return _scale(
      call,
      button == 'all'
          ? [ScaleCategory.button, ScaleCategory.touchTarget]
          : [_buttons[button]!.category],
      'bigger',
      'smaller',
    );
  }

  AssistResult _scale(
    ProposedCall call,
    List<ScaleCategory> categories,
    String up,
    String down,
  ) {
    var next = settings;
    for (final c in categories) {
      // Steps of the whole size, as the slider shows it. An exact size wins
      // over the direction.
      final size = _size(call, c);
      next = next.withEffective(
        c,
        size ??
            settings.effective(c) + _sign(call, up, down) * _amount(call, c),
      );
    }
    if (next == settings) return _unchanged(call, categories.first);
    return AssistProposal(call, SettingsChange(from: settings, to: next));
  }

  /// An exact size is already set; a step goes no further.
  AssistUnchanged _unchanged(ProposedCall call, ScaleCategory category) =>
      AssistUnchanged(
        call,
        call.args['size'] == null
            ? UnchangedReason.atLimit
            : UnchangedReason.alreadySet,
        category,
      );

  AssistResult _toggle(ProposedCall call, AccessibilityToggle toggle) {
    final enabled = _bool(call, 'enabled');
    if (settings.isOn(toggle) == enabled) {
      return AssistUnchanged(call, UnchangedReason.alreadySet);
    }
    return AssistProposal(
      call,
      SettingsChange(from: settings, to: settings.withToggle(toggle, enabled)),
    );
  }

  AssistResult _theme(ProposedCall call) {
    final mode = switch (_enum(call, 'mode')) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    if (mode == theme) return AssistUnchanged(call, UnchangedReason.alreadySet);
    return AssistProposal(
      call,
      SettingsChange(
        from: settings,
        to: settings,
        themeFrom: theme,
        themeTo: mode,
      ),
    );
  }

  /// `all` does not change the theme: `set_theme(system)` does that.
  AssistResult _reset(ProposedCall call) {
    final setting = _enum(call, 'setting');
    if (setting == 'simple_mode') return AssistNotAvailable(call);
    AccessibilitySettings reset(Iterable<ScaleCategory> categories) =>
        categories.fold(settings, (s, c) => s.without(c));
    final next = switch (setting) {
      'text_size' => reset(_textCategories).withoutChatText(),
      'button_size' => reset(_buttonCategories),
      'spacing' => settings.without(ScaleCategory.spacing),
      'avatar_size' => settings.without(ScaleCategory.avatar),
      'line_spacing' => settings.without(ScaleCategory.lineSpacing),
      'read_aloud' => settings.withToggle(
        AccessibilityToggle.tripleTapToRead,
        false,
      ),
      'button_labels' => settings.withToggle(
        AccessibilityToggle.buttonLabels,
        false,
      ),
      'high_contrast' => settings.withToggle(
        AccessibilityToggle.highContrast,
        false,
      ),
      _ => AccessibilitySettings.defaults,
    };
    if (next == settings) {
      return AssistUnchanged(call, UnchangedReason.alreadySet);
    }
    return AssistProposal(call, SettingsChange(from: settings, to: next));
  }

  /// Whether [call] is for one chat: `one_chat`, or a chat named, which
  /// always means that chat. False when it is for everywhere.
  bool _forOneChat(ProposedCall call) =>
      _enum(call, 'scope') == 'one_chat' ||
      (_string(call, 'chat')?.isNotEmpty ?? false);

  AssistNeedsChat _needsChat(ProposedCall call) {
    final chat = _string(call, 'chat');
    return AssistNeedsChat(call, chat == null || chat.isEmpty ? null : chat);
  }

  /// The value of an enum without a default, or null when left out.
  String? _optionalEnum(ProposedCall call, String parameter) =>
      call.args[parameter] == null ? null : _enum(call, parameter);

  AssistResult _bubbleColor(ProposedCall call, String? roomId) {
    final chat = _forOneChat(call);
    if (chat && roomId == null) return _needsChat(call);
    final room = chat ? roomId : null;
    final side = _optionalEnum(call, 'side');
    if (side == null) {
      return AssistNeedsDetail(call, 'side', const ['mine', 'theirs'], room);
    }
    final color = _optionalEnum(call, 'color');
    if (color == null) return _needsColor(call, room);
    return AssistAppProposal(
      call,
      AppChange(
        side == 'mine'
            ? AppSetting.ownBubbleColor
            : AppSetting.otherBubbleColor,
        room,
        colorValues[color],
      ),
    );
  }

  AssistNeedsDetail _needsColor(ProposedCall call, String? roomId) =>
      AssistNeedsDetail(call, 'color', colorValues.keys.toList(), roomId);

  AssistResult _appColor(ProposedCall call) {
    final color = _optionalEnum(call, 'color');
    if (color == null) return _needsColor(call, null);
    return AssistAppProposal(
      call,
      // default is the app's own color, which the Style page offers next to
      // the system one.
      AppChange(
        AppSetting.appColor,
        null,
        colorValues[color] ?? AppConfig.chatColor.toARGB32(),
      ),
    );
  }

  AssistResult _wallpaper(ProposedCall call, String? roomId) {
    final chat = _forOneChat(call);
    if (chat && roomId == null) return _needsChat(call);
    final value = switch (_enum(call, 'wallpaper')) {
      'blank' => 'none',
      'pattern' => 'pattern',
      // The chat's default is the app's wallpaper; the app's is none.
      _ => chat ? null : 'none',
    };
    return AssistAppProposal(
      call,
      AppChange(AppSetting.wallpaper, chat ? roomId : null, value),
    );
  }

  AssistResult _gesture(ProposedCall call) {
    final setting = _gestures[_enum(call, 'gesture')];
    if (setting == null) throw const _Invalid();
    return AssistAppProposal(
      call,
      AppChange(setting, null, _bool(call, 'enabled')),
    );
  }

  AssistResult _chatToggle(
    ProposedCall call,
    String? roomId,
    AppSetting setting,
  ) {
    final enabled = _bool(call, 'enabled');
    if (roomId == null) return _needsChat(call);
    return AssistAppProposal(call, AppChange(setting, roomId, enabled));
  }

  AssistResult _clarification(ProposedCall call) {
    final raw = call.args['options'];
    if (raw is! List) throw const _Invalid();
    final allowed = tools.enumOf(F.askClarification, 'options') ?? const [];
    final options = [
      for (final name in F.changeFunctions)
        if (allowed.contains(name) && raw.contains(name)) name,
    ];
    if (options.isEmpty) throw const _Invalid();
    return AssistClarification(call, options);
  }

  AssistNoSuggestion _invalid(ProposedCall call) =>
      AssistNoSuggestion(RejectionReason.invalidArguments, call);

  /// The value of a string enum, or its declared default when left out.
  /// Anything that is not one of the declared values is invalid.
  String _enum(ProposedCall call, String parameter) {
    final value = call.args[parameter] ?? tools.defaultOf(call.name, parameter);
    final allowed = tools.enumOf(call.name, parameter);
    if (value is! String || allowed == null) throw const _Invalid();
    final normalized = value.trim().toLowerCase();
    if (!allowed.contains(normalized)) throw const _Invalid();
    return normalized;
  }

  int _sign(ProposedCall call, String up, String down) {
    final direction = _enum(call, 'direction');
    if (direction == up) return 1;
    if (direction == down) return -1;
    throw const _Invalid();
  }

  /// How much a call changes [category]: one slider step for "a little"
  /// (1), one suggestion step for a plain "bigger" (2, the default), and 0.5
  /// for "a lot" (3).
  double _amount(ProposedCall call, ScaleCategory category) =>
      switch (_steps(call)) {
        1 => category.step,
        3 => 0.5,
        _ => category.suggestionStep,
      };

  /// The exact size of a call for [category], or null when it has none: a
  /// word of [PersonalizationTools.sizeWords], or a number as a factor (1.6,
  /// 1,6) or a percentage (160%). Sizes outside 0.5 to 3 are invalid, and
  /// the category clamps the rest.
  double? _size(ProposedCall call, ScaleCategory category) {
    final raw = call.args['size'];
    if (raw == null) return null;
    if (raw is! String && raw is! num) throw const _Invalid();
    final text = raw.toString().trim().toLowerCase().replaceAll(' ', '_');
    final word = F.sizeWords.indexOf(text);
    if (word >= 0) return [category.min, 1.0, 1.5, 2.0][word];
    final percent = text.endsWith('%');
    final number = num.tryParse(
      text.replaceAll('%', '').replaceAll('_', '').replaceAll(',', '.'),
    );
    if (number == null || number.isNaN) throw const _Invalid();
    final size = percent ? number / 100 : number;
    if (size < 0.5 || size > 3) throw const _Invalid();
    return size.toDouble();
  }

  /// Steps default to the declared default, accept numbers and numeric
  /// strings, and are clamped to the declared range. Anything else is
  /// invalid.
  int _steps(ProposedCall call) {
    final value = call.args['steps'] ?? tools.defaultOf(call.name, 'steps');
    final (min, max) = tools.rangeOf(call.name, 'steps') ?? (1, 3);
    final number = switch (value) {
      null => min,
      num() => value,
      String() => num.tryParse(value.trim()),
      _ => null,
    };
    if (number == null || number.isNaN) throw const _Invalid();
    return number.round().clamp(min, max);
  }

  bool _bool(ProposedCall call, String parameter) =>
      switch (call.args[parameter]) {
        true || 'true' => true,
        false || 'false' => false,
        _ => throw const _Invalid(),
      };

  String? _string(ProposedCall call, String parameter) {
    final value = call.args[parameter];
    if (value == null) return null;
    if (value is! String) throw const _Invalid();
    return value.trim();
  }
}

class _Invalid implements Exception {
  const _Invalid();
}
