// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

import 'accessibility_settings.dart';
import 'model/personalization_tools.dart';

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
  final String applied;

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
    required this.applied,
    required this.replyLabels,
    required this.textSize,
    required this.chatTextSize,
    required this.buttonSize,
    required this.spacing,
    required this.avatarSize,
    required this.toggle,
    required this.theme,
    required this.reset,
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
    PersonalizationTools.changeSpacing => const ['more space', 'less space'],
    PersonalizationTools.setSimpleMode ||
    PersonalizationTools.setButtonLabels ||
    PersonalizationTools.setHighContrast => const ['on', 'off'],
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
    },
    toggleDescriptions: {
      AccessibilityToggle.buttonLabels: 'Show words under button icons',
      AccessibilityToggle.highContrast: 'Stronger colors and bold text',
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
    },
    clarifyMany: 'What would you like to change?',
    clarifyOne: 'How should it change?',
    whichChat: _whichChatEn,
    noChats: 'There are no chats yet.',
    notAvailable: "The simple view isn't available yet. Nothing was changed.",
    noAction:
        "That isn't something I can change. I can change the size of text, "
        'buttons and pictures, the spacing, button labels, contrast, and '
        'light or dark.',
    alreadySet: 'That is already how it is.',
    applied: 'Changed.',
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
    },
    textSize: _textSizeEn,
    chatTextSize: _chatTextSizeEn,
    buttonSize: _buttonSizeEn,
    spacing: _spacingEn,
    avatarSize: _avatarSizeEn,
    toggle: _toggleEn,
    theme: _themeEn,
    reset: _resetEn,
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
    },
    toggleDescriptions: {
      AccessibilityToggle.buttonLabels: 'Vis ord under knappernes ikoner',
      AccessibilityToggle.highContrast: 'Stærkere farver og fed tekst',
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
    },
    clarifyMany: 'Hvad vil du gerne ændre?',
    clarifyOne: 'Hvordan skal det ændres?',
    whichChat: _whichChatDa,
    noChats: 'Der er ingen chats endnu.',
    notAvailable: 'Den enkle visning findes ikke endnu. Intet blev ændret.',
    noAction:
        'Det kan jeg ikke ændre. Jeg kan ændre størrelsen på tekst, knapper '
        'og billeder, afstanden, knaptekster, kontrast og lys eller mørk.',
    alreadySet: 'Sådan er det allerede.',
    applied: 'Ændret.',
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
    },
    textSize: _textSizeDa,
    chatTextSize: _chatTextSizeDa,
    buttonSize: _buttonSizeDa,
    spacing: _spacingDa,
    avatarSize: _avatarSizeDa,
    toggle: _toggleDa,
    theme: _themeDa,
    reset: _resetDa,
  );
}

String _whichChatEn(String? chat) => chat == null
    ? 'Which chat?'
    : 'I found no single chat called “$chat”. Which chat?';

String _whichChatDa(String? chat) => chat == null
    ? 'Hvilken chat?'
    : 'Jeg fandt ikke én chat, der hedder “$chat”. Hvilken chat?';

String _textSizeEn(ScaleCategory target, bool bigger) {
  final what = switch (target) {
    ScaleCategory.messageText => 'the text in messages',
    ScaleCategory.chatListText => 'the text in the chat list',
    ScaleCategory.titleText => 'the titles',
    ScaleCategory.inputText => 'the text you type',
    _ => 'all text',
  };
  return 'Make $what ${bigger ? 'bigger' : 'smaller'}?';
}

String _textSizeDa(ScaleCategory target, bool bigger) {
  final what = switch (target) {
    ScaleCategory.messageText => 'teksten i beskeder',
    ScaleCategory.chatListText => 'teksten i chatlisten',
    ScaleCategory.titleText => 'titlerne',
    ScaleCategory.inputText => 'den tekst, du skriver',
    _ => 'al tekst',
  };
  return 'Gøre $what ${bigger ? 'større' : 'mindre'}?';
}

String _chatTextSizeEn(String chat, bool bigger) =>
    'Make the text in the chat with $chat ${bigger ? 'bigger' : 'smaller'}?';

String _chatTextSizeDa(String chat, bool bigger) =>
    'Gøre teksten i chatten med $chat ${bigger ? 'større' : 'mindre'}?';

String _buttonSizeEn(AccessibleButton? button, bool bigger) {
  final what = switch (button) {
    null => 'all buttons',
    AccessibleButton.send => 'the send button',
    AccessibleButton.attach => 'the attach button',
    AccessibleButton.emoji => 'the emoji button',
    AccessibleButton.microphone => 'the microphone button',
    AccessibleButton.back => 'the back button',
    AccessibleButton.search => 'the search button',
    AccessibleButton.menu => 'the menu button',
    AccessibleButton.navigation => 'the tabs at the bottom',
  };
  return 'Make $what ${bigger ? 'bigger' : 'smaller'}?';
}

String _buttonSizeDa(AccessibleButton? button, bool bigger) {
  final what = switch (button) {
    null => 'alle knapper',
    AccessibleButton.send => 'send-knappen',
    AccessibleButton.attach => 'vedhæft-knappen',
    AccessibleButton.emoji => 'emoji-knappen',
    AccessibleButton.microphone => 'mikrofonknappen',
    AccessibleButton.back => 'tilbage-knappen',
    AccessibleButton.search => 'søgeknappen',
    AccessibleButton.menu => 'menuknappen',
    AccessibleButton.navigation => 'fanerne nederst',
  };
  return 'Gøre $what ${bigger ? 'større' : 'mindre'}?';
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
};

String _toggleDa(AccessibilityToggle toggle, bool on) => switch (toggle) {
  AccessibilityToggle.buttonLabels =>
    on ? 'Vise ord under knappernes ikoner?' : 'Skjule ordene under knapperne?',
  AccessibilityToggle.highContrast =>
    on ? 'Slå høj kontrast til?' : 'Slå høj kontrast fra?',
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
  'button_labels' => 'Hide the words under buttons again?',
  'high_contrast' => 'Turn off high contrast?',
  _ => 'Put all accessibility settings back to normal? Light or dark stays.',
};

String _resetDa(String? setting) => switch (setting) {
  'text_size' => 'Sætte tekststørrelsen tilbage til normal?',
  'button_size' => 'Sætte knapstørrelsen tilbage til normal?',
  'spacing' => 'Sætte afstanden tilbage til normal?',
  'avatar_size' => 'Sætte billedstørrelsen tilbage til normal?',
  'button_labels' => 'Skjule ordene under knapperne igen?',
  'high_contrast' => 'Slå høj kontrast fra?',
  _ =>
    'Sætte alle tilgængelighedsindstillinger tilbage til normal? Lys eller '
        'mørk bliver.',
};
