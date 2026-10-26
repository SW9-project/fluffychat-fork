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
  final String assistIntro;
  final String assistUnavailable;
  final String assistSetupInfo;
  final String openAccessibilitySettings;
  final String askSetup;
  final String Function(int percent) askSettingUp;
  final String askFailed;
  final String tryAgain;
  final String askHint;
  final String ask;
  final String noSuggestion;
  final String Function(String category) alreadyAtLimit;
  final String applyChange;
  final String noThanks;
  final String notChanged;
  final String changeUndone;
  final String thinking;
  final String previewNow;
  final String previewSuggested;
  final String meaningQuestion;
  final String meaningInformation;
  final String meaningRequest;
  final String meaningUrgent;
  final String meaningRemove;
  final String meaningTitle;
  final String meaningAnnotate;
  final String meaningAnnotateDescription;
  final String meaningShowIntent;
  final String meaningShowUrgency;
  final String meaningHighlightTimes;
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
    required this.assistIntro,
    required this.assistUnavailable,
    required this.assistSetupInfo,
    required this.openAccessibilitySettings,
    required this.askSetup,
    required this.askSettingUp,
    required this.askFailed,
    required this.tryAgain,
    required this.askHint,
    required this.ask,
    required this.noSuggestion,
    required this.alreadyAtLimit,
    required this.applyChange,
    required this.noThanks,
    required this.notChanged,
    required this.changeUndone,
    required this.thinking,
    required this.previewNow,
    required this.previewSuggested,
    required this.meaningQuestion,
    required this.meaningInformation,
    required this.meaningRequest,
    required this.meaningUrgent,
    required this.meaningRemove,
    required this.meaningTitle,
    required this.meaningAnnotate,
    required this.meaningAnnotateDescription,
    required this.meaningShowIntent,
    required this.meaningShowUrgency,
    required this.meaningHighlightTimes,
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
    assistIntro:
        'Tell me what is hard to use, and I suggest a change you can try. '
        'This runs only on your phone.',
    assistUnavailable:
        "The assistant can't run on this phone. You can still change the "
        'sizes yourself.',
    assistSetupInfo:
        'The assistant needs to be set up once. It runs only on this phone.',
    openAccessibilitySettings: 'Open accessibility settings',
    askSetup: 'Set up',
    askSettingUp: _askSettingUpEn,
    askFailed: 'The assistant could not be set up.',
    tryAgain: 'Try again',
    askHint: 'For example: the buttons are too small',
    ask: 'Ask',
    noSuggestion: "I don't have a suggestion for that.",
    alreadyAtLimit: _alreadyAtLimitEn,
    applyChange: 'Apply',
    noThanks: 'No thanks',
    notChanged: 'Nothing was changed.',
    changeUndone: 'The change was undone.',
    thinking: 'Thinking…',
    previewNow: 'Now',
    previewSuggested: 'Suggested',
    meaningQuestion: 'Question',
    meaningInformation: 'Information',
    meaningRequest: 'Request',
    meaningUrgent: 'Urgent',
    meaningRemove: 'Send without meaning',
    meaningTitle: 'Message meaning',
    meaningAnnotate: 'Add meaning to my messages',
    meaningAnnotateDescription:
        'Before sending, you see whether your message is a question, a '
        'request or urgent, and which times it mentions. You can change it.',
    meaningShowIntent: 'Mark questions and requests',
    meaningShowUrgency: 'Mark urgent messages',
    meaningHighlightTimes: 'Highlight times and dates',
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
    assistIntro:
        'Fortæl mig, hvad der er svært at bruge, så foreslår jeg en ændring, '
        'du kan prøve. Det kører kun på din telefon.',
    assistUnavailable:
        'Assistenten kan ikke køre på denne telefon. Du kan stadig selv '
        'ændre størrelserne.',
    assistSetupInfo:
        'Assistenten skal klargøres én gang. Den kører kun på denne telefon.',
    openAccessibilitySettings: 'Åbn tilgængelighedsindstillinger',
    askSetup: 'Klargør',
    askSettingUp: _askSettingUpDa,
    askFailed: 'Assistenten kunne ikke klargøres.',
    tryAgain: 'Prøv igen',
    askHint: 'For eksempel: knapperne er for små',
    ask: 'Spørg',
    noSuggestion: 'Det har jeg ikke et forslag til.',
    alreadyAtLimit: _alreadyAtLimitDa,
    applyChange: 'Anvend',
    noThanks: 'Nej tak',
    notChanged: 'Intet blev ændret.',
    changeUndone: 'Ændringen blev fortrudt.',
    thinking: 'Tænker…',
    previewNow: 'Nu',
    previewSuggested: 'Forslag',
    meaningQuestion: 'Spørgsmål',
    meaningInformation: 'Information',
    meaningRequest: 'Anmodning',
    meaningUrgent: 'Haster',
    meaningRemove: 'Send uden betydning',
    meaningTitle: 'Beskeders betydning',
    meaningAnnotate: 'Tilføj betydning til mine beskeder',
    meaningAnnotateDescription:
        'Før du sender, ser du, om din besked er et spørgsmål, en anmodning '
        'eller haster, og hvilke tidspunkter den nævner. Du kan ændre det.',
    meaningShowIntent: 'Markér spørgsmål og anmodninger',
    meaningShowUrgency: 'Markér beskeder, der haster',
    meaningHighlightTimes: 'Fremhæv tidspunkter og datoer',
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
