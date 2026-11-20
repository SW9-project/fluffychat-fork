// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

import 'accessibility_settings.dart';
import 'model/app_change.dart';
import 'model/personalization_tools.dart';
import 'model/tool_call_interpreter.dart';

/// Strings for the settings the fine-tuned model can change, next to
/// `PersonalizationL10n`: what the Assist tab says about a call, and the
/// labels, contrast, spacing and theme settings.
///
/// The words the app sends to the model are English in every language,
/// because the model learned English: see [quickReplies].
class AppearanceL10n {
  final String labelBack;
  final String labelSearch;
  final String labelMenu;
  final String labelEmoji;
  final String labelAttach;
  final String labelMicrophone;
  final String labelSend;
  final Map<AccessibilityToggle, String> toggleTitles;
  final Map<AccessibilityToggle, String> toggleDescriptions;
  final String textGroup;
  final String buttonsGroup;
  final String chatTextTitle;
  final String chatTextDescription;
  final String chatTextNormal;

  /// Puts a size back on top of [parent], such as the text size.
  final String Function(String parent) matchParent;
  final String themeTitle;
  final Map<ThemeMode, String> themeModes;

  /// The functions `ask_clarification` offers, as the user sees them.
  final Map<String, String> functionTitles;
  final String clarifyMany;
  final String clarifyOne;
  final String Function(String? chat) whichChat;
  final String noChats;
  final String notAvailable;
  final String noAction;
  final String alreadySet;
  final String sameAsOtherSide;
  final String applied;
  final String changeFailed;

  /// The words of a quick reply, by what the app sends to the model.
  final Map<String, String> replyLabels;
  final String Function(ScaleCategory target, bool bigger) textSize;
  final String Function(String chat, bool bigger) chatTextSize;
  final String Function(AccessibleButton? button, bool bigger) buttonSize;
  final String Function(bool more) spacing;
  final String Function(bool bigger) avatarSize;
  final String Function(AccessibilityToggle toggle, bool on) toggle;
  final String Function(ThemeMode mode) theme;
  final String Function(String? setting) reset;

  /// What a size is of, such as "all text", for [sizeTo].
  final String Function(ScaleCategory category) sizeTarget;
  final String Function(String chat) chatText;

  /// The size words of [PersonalizationTools.sizeWords], as the user sees
  /// them.
  final Map<String, String> sizeLabels;
  final String Function(String what, String size) sizeTo;
  final String Function(bool more) lineSpacing;
  final String Function(AppChange change, String? chat) appChange;

  /// The question of an `AssistNeedsDetail`, by its parameter.
  final Map<String, String> detailQuestions;

  /// One of its options: a side or a color.
  final String Function(String option) detailOption;

  const AppearanceL10n._({
    required this.labelBack,
    required this.labelSearch,
    required this.labelMenu,
    required this.labelEmoji,
    required this.labelAttach,
    required this.labelMicrophone,
    required this.labelSend,
    required this.toggleTitles,
    required this.toggleDescriptions,
    required this.textGroup,
    required this.buttonsGroup,
    required this.chatTextTitle,
    required this.chatTextDescription,
    required this.chatTextNormal,
    required this.matchParent,
    required this.themeTitle,
    required this.themeModes,
    required this.functionTitles,
    required this.clarifyMany,
    required this.clarifyOne,
    required this.whichChat,
    required this.noChats,
    required this.notAvailable,
    required this.noAction,
    required this.alreadySet,
    required this.sameAsOtherSide,
    required this.applied,
    required this.changeFailed,
    required this.replyLabels,
    required this.textSize,
    required this.chatTextSize,
    required this.buttonSize,
    required this.spacing,
    required this.avatarSize,
    required this.toggle,
    required this.theme,
    required this.reset,
    required this.sizeTarget,
    required this.chatText,
    required this.sizeLabels,
    required this.sizeTo,
    required this.lineSpacing,
    required this.appChange,
    required this.detailQuestions,
    required this.detailOption,
  });

  static AppearanceL10n of(BuildContext context) =>
      switch (Localizations.localeOf(context).languageCode) {
        'da' => _da,
        _ => _en,
      };

  /// The answers the user can tap when `ask_clarification` offers one
  /// function and only its details are unclear. They are sent as the user's
  /// own words, in English, like the training answers ("bigger", "much
  /// bigger").
  static List<String> quickReplies(String function) => switch (function) {
    PersonalizationTools.changeTextSize ||
    PersonalizationTools.changeButtonSize ||
    PersonalizationTools.changeAvatarSize => const ['bigger', 'smaller'],
    PersonalizationTools.changeSpacing ||
    PersonalizationTools.changeLineSpacing => const [
      'more space',
      'less space',
    ],
    PersonalizationTools.setSimpleMode ||
    PersonalizationTools.setButtonLabels ||
    PersonalizationTools.setHighContrast ||
    PersonalizationTools.setReadAloud => const ['on', 'off'],
    PersonalizationTools.setWallpaper => const ['blank', 'pattern'],
    PersonalizationTools.setGesture => const [
      'the swiping',
      'double tap',
      'enter to send',
      'gifs',
    ],
    PersonalizationTools.setTheme => const ['dark', 'light', 'like my phone'],
    PersonalizationTools.resetSettings => const ['everything'],
    _ => const [],
  };

  static const _en = AppearanceL10n._(
    labelBack: 'Back',
    labelSearch: 'Search',
    labelMenu: 'Menu',
    labelEmoji: 'Emoji',
    labelAttach: 'Attach',
    labelMicrophone: 'Voice',
    labelSend: 'Send',
    toggleTitles: {
      AccessibilityToggle.buttonLabels: 'Button labels',
      AccessibilityToggle.highContrast: 'High contrast',
      AccessibilityToggle.tripleTapToRead: 'Tap three times to read aloud',
    },
    toggleDescriptions: {
      AccessibilityToggle.buttonLabels: 'Show words under button icons',
      AccessibilityToggle.highContrast: 'Stronger colors and bold text',
      AccessibilityToggle.tripleTapToRead:
          'Tap a message three times to hear it read out loud',
    },
    textGroup: 'Text in one place',
    buttonsGroup: 'One button',
    chatTextTitle: 'Text in one chat',
    chatTextDescription:
        'Chats with their own text size. Ask the assistant to add one.',
    chatTextNormal: 'Normal size',
    matchParent: _matchParentEn,
    themeTitle: 'Light or dark',
    themeModes: {
      ThemeMode.system: 'Like my phone',
      ThemeMode.light: 'Light',
      ThemeMode.dark: 'Dark',
    },
    functionTitles: {
      PersonalizationTools.changeTextSize: 'Text size',
      PersonalizationTools.changeButtonSize: 'Button size',
      PersonalizationTools.changeSpacing: 'Space between buttons',
      PersonalizationTools.setSimpleMode: 'Simple view',
      PersonalizationTools.setButtonLabels: 'Words on buttons',
      PersonalizationTools.setHighContrast: 'High contrast',
      PersonalizationTools.changeAvatarSize: 'Picture size',
      PersonalizationTools.setTheme: 'Light or dark',
      PersonalizationTools.resetSettings: 'Back to normal',
      PersonalizationTools.changeLineSpacing: 'Line spacing',
      PersonalizationTools.setReadAloud: 'Read aloud',
      PersonalizationTools.setBubbleColor: 'Bubble color',
      PersonalizationTools.setAppColor: 'App color',
      PersonalizationTools.setWallpaper: 'Chat background',
      PersonalizationTools.setGesture: 'Gestures',
    },
    clarifyMany: 'What would you like to change?',
    clarifyOne: 'How should it change?',
    whichChat: _whichChatEn,
    noChats: 'There are no chats yet.',
    notAvailable: "The simple view isn't available yet. Nothing was changed.",
    noAction:
        "That isn't something I can change. I can change the size of text, "
        'buttons and pictures, the space between buttons and lines, button '
        'labels, contrast, light or dark, reading aloud, the colors of the '
        'app and the bubbles, the chat background and gestures, and I can '
        'pin or mute a chat.',
    alreadySet: 'That is already how it is.',
    sameAsOtherSide:
        'The other side already has that color, so the bubbles would look '
        'the same. Pick another color.',
    applied: 'Changed.',
    changeFailed: "That didn't work. Nothing was changed.",
    replyLabels: {
      'bigger': 'Bigger',
      'smaller': 'Smaller',
      'more space': 'More space',
      'less space': 'Less space',
      'on': 'On',
      'off': 'Off',
      'dark': 'Dark',
      'light': 'Light',
      'like my phone': 'Like my phone',
      'everything': 'Everything',
      'blank': 'Blank',
      'pattern': 'Pattern',
      'the swiping': 'Swipe to reply',
      'double tap': 'Double tap',
      'enter to send': 'Enter to send',
      'gifs': 'GIFs',
    },
    textSize: _textSizeEn,
    chatTextSize: _chatTextSizeEn,
    buttonSize: _buttonSizeEn,
    spacing: _spacingEn,
    avatarSize: _avatarSizeEn,
    toggle: _toggleEn,
    theme: _themeEn,
    reset: _resetEn,
    sizeTarget: _sizeTargetEn,
    chatText: _chatTextEn,
    sizeLabels: {
      'small': 'Small',
      'medium': 'Medium',
      'big': 'Big',
      'very_big': 'Very big',
    },
    sizeTo: _sizeToEn,
    lineSpacing: _lineSpacingEn,
    appChange: _appChangeEn,
    detailQuestions: {
      'side': "Your bubbles or other people's?",
      'color': 'Which color?',
    },
    detailOption: _detailOptionEn,
  );

  static const _da = AppearanceL10n._(
    labelBack: 'Tilbage',
    labelSearch: 'Søg',
    labelMenu: 'Menu',
    labelEmoji: 'Emoji',
    labelAttach: 'Vedhæft',
    labelMicrophone: 'Tale',
    labelSend: 'Send',
    toggleTitles: {
      AccessibilityToggle.buttonLabels: 'Knaptekster',
      AccessibilityToggle.highContrast: 'Høj kontrast',
      AccessibilityToggle.tripleTapToRead: 'Tryk tre gange for oplæsning',
    },
    toggleDescriptions: {
      AccessibilityToggle.buttonLabels: 'Vis ord under knappernes ikoner',
      AccessibilityToggle.highContrast: 'Stærkere farver og fed tekst',
      AccessibilityToggle.tripleTapToRead:
          'Tryk tre gange på en besked for at få den læst højt',
    },
    textGroup: 'Tekst ét sted',
    buttonsGroup: 'Én knap',
    chatTextTitle: 'Tekst i én chat',
    chatTextDescription:
        'Chats med deres egen tekststørrelse. Bed assistenten om at tilføje en.',
    chatTextNormal: 'Normal størrelse',
    matchParent: _matchParentDa,
    themeTitle: 'Lys eller mørk',
    themeModes: {
      ThemeMode.system: 'Som min telefon',
      ThemeMode.light: 'Lys',
      ThemeMode.dark: 'Mørk',
    },
    functionTitles: {
      PersonalizationTools.changeTextSize: 'Tekststørrelse',
      PersonalizationTools.changeButtonSize: 'Knapstørrelse',
      PersonalizationTools.changeSpacing: 'Afstand mellem knapper',
      PersonalizationTools.setSimpleMode: 'Enkel visning',
      PersonalizationTools.setButtonLabels: 'Ord på knapper',
      PersonalizationTools.setHighContrast: 'Høj kontrast',
      PersonalizationTools.changeAvatarSize: 'Billedstørrelse',
      PersonalizationTools.setTheme: 'Lys eller mørk',
      PersonalizationTools.resetSettings: 'Tilbage til normal',
      PersonalizationTools.changeLineSpacing: 'Linjeafstand',
      PersonalizationTools.setReadAloud: 'Læs højt',
      PersonalizationTools.setBubbleColor: 'Boblefarve',
      PersonalizationTools.setAppColor: 'Appfarve',
      PersonalizationTools.setWallpaper: 'Chatbaggrund',
      PersonalizationTools.setGesture: 'Bevægelser',
    },
    clarifyMany: 'Hvad vil du gerne ændre?',
    clarifyOne: 'Hvordan skal det ændres?',
    whichChat: _whichChatDa,
    noChats: 'Der er ingen chats endnu.',
    notAvailable: 'Den enkle visning findes ikke endnu. Intet blev ændret.',
    noAction:
        'Det kan jeg ikke ændre. Jeg kan ændre størrelsen på tekst, knapper '
        'og billeder, afstanden mellem knapper og linjer, knaptekster, '
        'kontrast, lys eller mørk, oplæsning, farverne på appen og boblerne, '
        'chatbaggrunden og bevægelser, og jeg kan fastgøre en chat eller slå '
        'lyden fra.',
    alreadySet: 'Sådan er det allerede.',
    sameAsOtherSide:
        'De andre bobler har allerede den farve, så boblerne ville se ens ud. '
        'Vælg en anden farve.',
    applied: 'Ændret.',
    changeFailed: 'Det lykkedes ikke. Intet blev ændret.',
    replyLabels: {
      'bigger': 'Større',
      'smaller': 'Mindre',
      'more space': 'Mere afstand',
      'less space': 'Mindre afstand',
      'on': 'Til',
      'off': 'Fra',
      'dark': 'Mørk',
      'light': 'Lys',
      'like my phone': 'Som min telefon',
      'everything': 'Alt',
      'blank': 'Ensfarvet',
      'pattern': 'Mønster',
      'the swiping': 'Stryg for at svare',
      'double tap': 'Dobbelttryk',
      'enter to send': 'Send med Enter',
      'gifs': "GIF'er",
    },
    textSize: _textSizeDa,
    chatTextSize: _chatTextSizeDa,
    buttonSize: _buttonSizeDa,
    spacing: _spacingDa,
    avatarSize: _avatarSizeDa,
    toggle: _toggleDa,
    theme: _themeDa,
    reset: _resetDa,
    sizeTarget: _sizeTargetDa,
    chatText: _chatTextDa,
    sizeLabels: {
      'small': 'Lille',
      'medium': 'Mellem',
      'big': 'Stor',
      'very_big': 'Meget stor',
    },
    sizeTo: _sizeToDa,
    lineSpacing: _lineSpacingDa,
    appChange: _appChangeDa,
    detailQuestions: {
      'side': 'Dine bobler eller de andres?',
      'color': 'Hvilken farve?',
    },
    detailOption: _detailOptionDa,
  );
}

String _whichChatEn(String? chat) => chat == null
    ? 'Which chat?'
    : 'I found no single chat called “$chat”. Which chat?';

String _whichChatDa(String? chat) => chat == null
    ? 'Hvilken chat?'
    : 'Jeg fandt ikke én chat, der hedder “$chat”. Hvilken chat?';

String _sizeTargetEn(ScaleCategory category) => switch (category) {
  ScaleCategory.text => 'all text',
  ScaleCategory.messageText => 'the text in messages',
  ScaleCategory.chatListText => 'the text in the chat list',
  ScaleCategory.titleText => 'the titles',
  ScaleCategory.inputText => 'the text you type',
  ScaleCategory.button || ScaleCategory.touchTarget => 'all buttons',
  ScaleCategory.sendButton => 'the send button',
  ScaleCategory.attachButton => 'the attach button',
  ScaleCategory.emojiButton => 'the emoji button',
  ScaleCategory.microphoneButton => 'the microphone button',
  ScaleCategory.backButton => 'the back button',
  ScaleCategory.searchButton => 'the search button',
  ScaleCategory.menuButton => 'the menu button',
  ScaleCategory.navigationButton => 'the tabs at the bottom',
  ScaleCategory.spacing => 'the space between buttons',
  ScaleCategory.lineSpacing => 'the space between lines',
  ScaleCategory.avatar => 'profile pictures',
};

String _sizeTargetDa(ScaleCategory category) => switch (category) {
  ScaleCategory.text => 'al tekst',
  ScaleCategory.messageText => 'teksten i beskeder',
  ScaleCategory.chatListText => 'teksten i chatlisten',
  ScaleCategory.titleText => 'titlerne',
  ScaleCategory.inputText => 'den tekst, du skriver',
  ScaleCategory.button || ScaleCategory.touchTarget => 'alle knapper',
  ScaleCategory.sendButton => 'send-knappen',
  ScaleCategory.attachButton => 'vedhæft-knappen',
  ScaleCategory.emojiButton => 'emoji-knappen',
  ScaleCategory.microphoneButton => 'mikrofonknappen',
  ScaleCategory.backButton => 'tilbage-knappen',
  ScaleCategory.searchButton => 'søgeknappen',
  ScaleCategory.menuButton => 'menuknappen',
  ScaleCategory.navigationButton => 'fanerne nederst',
  ScaleCategory.spacing => 'afstanden mellem knapperne',
  ScaleCategory.lineSpacing => 'afstanden mellem linjerne',
  ScaleCategory.avatar => 'profilbilleder',
};

String _textSizeEn(ScaleCategory target, bool bigger) =>
    'Make ${_sizeTargetEn(target)} ${bigger ? 'bigger' : 'smaller'}?';

String _textSizeDa(ScaleCategory target, bool bigger) =>
    'Gøre ${_sizeTargetDa(target)} ${bigger ? 'større' : 'mindre'}?';

String _chatTextEn(String chat) => 'the text in the chat with $chat';

String _chatTextDa(String chat) => 'teksten i chatten med $chat';

String _chatTextSizeEn(String chat, bool bigger) =>
    'Make ${_chatTextEn(chat)} ${bigger ? 'bigger' : 'smaller'}?';

String _chatTextSizeDa(String chat, bool bigger) =>
    'Gøre ${_chatTextDa(chat)} ${bigger ? 'større' : 'mindre'}?';

String _buttonSizeEn(AccessibleButton? button, bool bigger) =>
    'Make ${_sizeTargetEn(button?.category ?? ScaleCategory.button)} '
    '${bigger ? 'bigger' : 'smaller'}?';

String _buttonSizeDa(AccessibleButton? button, bool bigger) =>
    'Gøre ${_sizeTargetDa(button?.category ?? ScaleCategory.button)} '
    '${bigger ? 'større' : 'mindre'}?';

String _sizeToEn(String what, String size) => 'Set $what to $size?';

String _sizeToDa(String what, String size) => 'Sætte $what til $size?';

String _lineSpacingEn(bool more) =>
    more ? 'Put more space between lines?' : 'Put the lines closer together?';

String _lineSpacingDa(bool more) => more
    ? 'Give mere afstand mellem linjerne?'
    : 'Sætte linjerne tættere sammen?';

const _colorsEn = {
  'red': 'red',
  'pink': 'pink',
  'purple': 'purple',
  'indigo': 'indigo',
  'blue': 'blue',
  'cyan': 'cyan',
  'teal': 'teal',
  'green': 'green',
  'lime': 'lime',
  'yellow': 'yellow',
  'amber': 'amber',
  'orange': 'orange',
  'brown': 'brown',
  'grey': 'grey',
};

const _colorsDa = {
  'red': 'rød',
  'pink': 'lyserød',
  'purple': 'lilla',
  'indigo': 'indigo',
  'blue': 'blå',
  'cyan': 'cyan',
  'teal': 'blågrøn',
  'green': 'grøn',
  'lime': 'limegrøn',
  'yellow': 'gul',
  'amber': 'ravgul',
  'orange': 'orange',
  'brown': 'brun',
  'grey': 'grå',
};

/// The color word of an ARGB [value], or null for the default color.
String? _color(Map<String, String> words, Object? value) {
  for (final MapEntry(:key, value: argb)
      in ToolCallInterpreter.colorValues.entries) {
    if (argb == value) return words[key];
  }
  return null;
}

String _capitalized(String word) =>
    word.isEmpty ? word : word[0].toUpperCase() + word.substring(1);

String _detailOptionEn(String option) => switch (option) {
  'mine' => 'Mine',
  'theirs' => "Other people's",
  _ => _capitalized(_colorsEn[option] ?? option),
};

String _detailOptionDa(String option) => switch (option) {
  'mine' => 'Mine',
  'theirs' => 'De andres',
  _ => _capitalized(_colorsDa[option] ?? option),
};

String _appChangeEn(AppChange change, String? chat) {
  final where = chat == null ? 'in all chats' : 'in the chat with $chat';
  final on = change.value == true;
  final color = _color(_colorsEn, change.value) ?? 'the normal color';
  return switch (change.setting) {
    AppSetting.pinned => '${on ? 'Pin' : 'Unpin'} the chat with $chat?',
    AppSetting.muted => '${on ? 'Mute' : 'Unmute'} the chat with $chat?',
    AppSetting.ownBubbleColor => 'Make your bubbles $where $color?',
    AppSetting.otherBubbleColor => "Make other people's bubbles $where $color?",
    AppSetting.appColor => 'Make the app $color?',
    AppSetting.wallpaper => switch (change.value) {
      'none' => 'Use a blank background $where?',
      'pattern' => 'Use the pattern background $where?',
      _ => 'Use the normal background $where?',
    },
    AppSetting.swipeToReply =>
      'Turn ${on ? 'on' : 'off'} swiping a message to reply?',
    AppSetting.doubleTapToReact =>
      'Turn ${on ? 'on' : 'off'} tapping a message twice to react?',
    AppSetting.sendOnEnter =>
      'Turn ${on ? 'on' : 'off'} sending with the Enter key?',
    AppSetting.autoplayGifs =>
      'Turn ${on ? 'on' : 'off'} playing GIFs by themselves?',
  };
}

String _appChangeDa(AppChange change, String? chat) {
  final where = chat == null ? 'i alle chats' : 'i chatten med $chat';
  final on = change.value == true;
  final word = _color(_colorsDa, change.value);
  final color = word == null ? 'den normale farve' : 'farven $word';
  final onOff = on ? 'til' : 'fra';
  return switch (change.setting) {
    AppSetting.pinned => '${on ? 'Fastgøre' : 'Frigøre'} chatten med $chat?',
    AppSetting.muted =>
      'Slå lyden ${on ? 'fra' : 'til'} for chatten med $chat?',
    AppSetting.ownBubbleColor => 'Give dine bobler $where $color?',
    AppSetting.otherBubbleColor => 'Give de andres bobler $where $color?',
    AppSetting.appColor => 'Give appen $color?',
    AppSetting.wallpaper => switch (change.value) {
      'none' => 'Bruge en ensfarvet baggrund $where?',
      'pattern' => 'Bruge mønsterbaggrunden $where?',
      _ => 'Bruge den normale baggrund $where?',
    },
    AppSetting.swipeToReply => 'Slå svar ved at stryge $onOff?',
    AppSetting.doubleTapToReact => 'Slå reaktion ved dobbelttryk $onOff?',
    AppSetting.sendOnEnter => 'Slå send med Enter-tasten $onOff?',
    AppSetting.autoplayGifs => "Slå automatisk afspilning af GIF'er $onOff?",
  };
}

String _spacingEn(bool more) => more
    ? 'Put more space between buttons?'
    : 'Put the buttons closer together?';

String _spacingDa(bool more) => more
    ? 'Give mere afstand mellem knapperne?'
    : 'Sætte knapperne tættere sammen?';

String _avatarSizeEn(bool bigger) =>
    'Make profile pictures ${bigger ? 'bigger' : 'smaller'}?';

String _avatarSizeDa(bool bigger) =>
    'Gøre profilbilleder ${bigger ? 'større' : 'mindre'}?';

String _toggleEn(AccessibilityToggle toggle, bool on) => switch (toggle) {
  AccessibilityToggle.buttonLabels =>
    on ? 'Show words under button icons?' : 'Hide the words under buttons?',
  AccessibilityToggle.highContrast =>
    on ? 'Turn on high contrast?' : 'Turn off high contrast?',
  AccessibilityToggle.tripleTapToRead =>
    on
        ? 'Read messages aloud when tapped three times?'
        : 'Stop reading messages aloud on three taps?',
};

String _toggleDa(AccessibilityToggle toggle, bool on) => switch (toggle) {
  AccessibilityToggle.buttonLabels =>
    on ? 'Vise ord under knappernes ikoner?' : 'Skjule ordene under knapperne?',
  AccessibilityToggle.highContrast =>
    on ? 'Slå høj kontrast til?' : 'Slå høj kontrast fra?',
  AccessibilityToggle.tripleTapToRead =>
    on
        ? 'Læse beskeder højt ved tre tryk?'
        : 'Stoppe oplæsning af beskeder ved tre tryk?',
};

String _themeEn(ThemeMode mode) => switch (mode) {
  ThemeMode.dark => 'Switch to a dark screen?',
  ThemeMode.light => 'Switch to a light screen?',
  ThemeMode.system => 'Follow your phone’s light or dark setting?',
};

String _themeDa(ThemeMode mode) => switch (mode) {
  ThemeMode.dark => 'Skifte til en mørk skærm?',
  ThemeMode.light => 'Skifte til en lys skærm?',
  ThemeMode.system => 'Følge telefonens indstilling for lys eller mørk?',
};

String _matchParentEn(String parent) => 'Same as $parent';

String _matchParentDa(String parent) => 'Samme som $parent';

String _resetEn(String? setting) => switch (setting) {
  'text_size' => 'Put the text size back to normal?',
  'button_size' => 'Put the button size back to normal?',
  'spacing' => 'Put the spacing back to normal?',
  'avatar_size' => 'Put the picture size back to normal?',
  'line_spacing' => 'Put the line spacing back to normal?',
  'read_aloud' => 'Stop reading messages aloud on three taps?',
  'button_labels' => 'Hide the words under buttons again?',
  'high_contrast' => 'Turn off high contrast?',
  _ => 'Put all accessibility settings back to normal? Light or dark stays.',
};

String _resetDa(String? setting) => switch (setting) {
  'text_size' => 'Sætte tekststørrelsen tilbage til normal?',
  'button_size' => 'Sætte knapstørrelsen tilbage til normal?',
  'spacing' => 'Sætte afstanden tilbage til normal?',
  'avatar_size' => 'Sætte billedstørrelsen tilbage til normal?',
  'line_spacing' => 'Sætte linjeafstanden tilbage til normal?',
  'read_aloud' => 'Stoppe oplæsning af beskeder ved tre tryk?',
  'button_labels' => 'Skjule ordene under knapperne igen?',
  'high_contrast' => 'Slå høj kontrast fra?',
  _ =>
    'Sætte alle tilgængelighedsindstillinger tilbage til normal? Lys eller '
        'mørk bliver.',
};
