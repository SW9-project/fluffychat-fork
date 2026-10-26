// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

import 'accessibility_settings.dart';

/// Strings for the personalization feature, kept apart from FluffyChat's ARB
/// files so upstream merges do not regenerate the l10n code.
class PersonalizationL10n {
  final String accessibility;
  final String accessibilityDescription;
  final String preview;
  final String previewMessage;
  final String previewReply;
  final String previewChatName;
  final String typeMessage;
  final String undo;
  final String reset;
  final String suggestion;
  final String apply;
  final String notNow;
  final String dontSuggestAgain;
  final String Function(String category, String value) changedTo;
  final String askTitle;
  final String askDescription;
  final String askSetup;
  final String Function(int percent) askSettingUp;
  final String askFailed;
  final String tryAgain;
  final String askHint;
  final String ask;
  final String didNotCatchThat;
  final String Function(String category) alreadyAtLimit;
  final String Function(String text) youWrote;
  final Map<ScaleCategory, String> categoryTitles;
  final Map<ScaleCategory, String> categoryDescriptions;

  const PersonalizationL10n._({
    required this.accessibility,
    required this.accessibilityDescription,
    required this.preview,
    required this.previewMessage,
    required this.previewReply,
    required this.previewChatName,
    required this.typeMessage,
    required this.undo,
    required this.reset,
    required this.suggestion,
    required this.apply,
    required this.notNow,
    required this.dontSuggestAgain,
    required this.changedTo,
    required this.askTitle,
    required this.askDescription,
    required this.askSetup,
    required this.askSettingUp,
    required this.askFailed,
    required this.tryAgain,
    required this.askHint,
    required this.ask,
    required this.didNotCatchThat,
    required this.alreadyAtLimit,
    required this.youWrote,
    required this.categoryTitles,
    required this.categoryDescriptions,
  });

  static PersonalizationL10n of(BuildContext context) =>
      switch (Localizations.localeOf(context).languageCode) {
        'da' => _da,
        _ => _en,
      };

  static const _en = PersonalizationL10n._(
    accessibility: 'Accessibility',
    accessibilityDescription: 'Make text, buttons and pictures bigger.',
    preview: 'Preview',
    previewMessage: 'Hi! Are we still meeting tomorrow at 10?',
    previewReply: 'Yes, see you then!',
    previewChatName: 'Anna',
    typeMessage: 'Write a message',
    undo: 'Undo',
    reset: 'Reset',
    suggestion: 'Suggestion',
    apply: 'Yes, change it',
    notNow: 'Not now',
    dontSuggestAgain: "Don't suggest this again",
    changedTo: _changedToEn,
    askTitle: 'Tell the app what is hard',
    askDescription:
        'Write what bothers you, and the app suggests a change. '
        'This runs only on your phone.',
    askSetup: 'Set up',
    askSettingUp: _askSettingUpEn,
    askFailed: 'The assistant could not be set up.',
    tryAgain: 'Try again',
    askHint: 'For example: the buttons are too small',
    ask: 'Ask',
    didNotCatchThat:
        "I didn't catch that. You can also change the sizes with the "
        'sliders below.',
    alreadyAtLimit: _alreadyAtLimitEn,
    youWrote: _youWroteEn,
    categoryTitles: {
      ScaleCategory.text: 'Text size',
      ScaleCategory.inputText: 'Typing text size',
      ScaleCategory.button: 'Button size',
      ScaleCategory.touchTarget: 'Touch area',
      ScaleCategory.avatar: 'Picture size',
    },
    categoryDescriptions: {
      ScaleCategory.text: 'Size of all text in the app',
      ScaleCategory.inputText: 'Size of the text you type in a message',
      ScaleCategory.button: 'Size of icons on buttons',
      ScaleCategory.touchTarget: 'How large the area you can tap is',
      ScaleCategory.avatar: 'Size of profile pictures',
    },
  );

  static const _da = PersonalizationL10n._(
    accessibility: 'Tilgængelighed',
    accessibilityDescription: 'Gør tekst, knapper og billeder større.',
    preview: 'Forhåndsvisning',
    previewMessage: 'Hej! Ses vi stadig i morgen kl. 10?',
    previewReply: 'Ja, vi ses!',
    previewChatName: 'Anna',
    typeMessage: 'Skriv en besked',
    undo: 'Fortryd',
    reset: 'Nulstil',
    suggestion: 'Forslag',
    apply: 'Ja, skift den',
    notNow: 'Ikke nu',
    dontSuggestAgain: 'Foreslå ikke dette igen',
    changedTo: _changedToDa,
    askTitle: 'Fortæl appen, hvad der er svært',
    askDescription:
        'Skriv, hvad der generer dig, så foreslår appen en ændring. '
        'Det kører kun på din telefon.',
    askSetup: 'Klargør',
    askSettingUp: _askSettingUpDa,
    askFailed: 'Assistenten kunne ikke klargøres.',
    tryAgain: 'Prøv igen',
    askHint: 'For eksempel: knapperne er for små',
    ask: 'Spørg',
    didNotCatchThat:
        'Det forstod jeg ikke. Du kan også ændre størrelserne med '
        'skyderne herunder.',
    alreadyAtLimit: _alreadyAtLimitDa,
    youWrote: _youWroteDa,
    categoryTitles: {
      ScaleCategory.text: 'Tekststørrelse',
      ScaleCategory.inputText: 'Størrelse på skrivetekst',
      ScaleCategory.button: 'Knapstørrelse',
      ScaleCategory.touchTarget: 'Trykområde',
      ScaleCategory.avatar: 'Billedstørrelse',
    },
    categoryDescriptions: {
      ScaleCategory.text: 'Størrelsen på al tekst i appen',
      ScaleCategory.inputText:
          'Størrelsen på den tekst, du skriver i en besked',
      ScaleCategory.button: 'Størrelsen på ikoner på knapper',
      ScaleCategory.touchTarget: 'Hvor stort området er, som du kan trykke på',
      ScaleCategory.avatar: 'Størrelsen på profilbilleder',
    },
  );
}

String _changedToEn(String category, String value) =>
    '$category is now × $value';

String _changedToDa(String category, String value) =>
    '$category er nu × $value';

String _askSettingUpEn(int percent) => 'Setting up… $percent%';

String _askSettingUpDa(int percent) => 'Klargør… $percent%';

String _alreadyAtLimitEn(String category) =>
    '$category cannot change any further that way.';

String _alreadyAtLimitDa(String category) =>
    '$category kan ikke ændres mere i den retning.';

String _youWroteEn(String text) => 'You wrote: “$text”';

String _youWroteDa(String text) => 'Du skrev: “$text”';
