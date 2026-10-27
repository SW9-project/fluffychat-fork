// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

import 'accessibility_settings.dart';
import 'study/study_settings.dart';

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
  final String assistOff;
  final String studyTitle;
  final String studyCondition;
  final Map<StudyCondition, String> conditionTitles;
  final Map<StudyCondition, String> conditionDescriptions;
  final String studyChangeCondition;
  final String studyChangeConditionInfo;
  final String studyChange;
  final String cancel;
  final String studyLogging;
  final String studyLoggingDescription;
  final String studyParticipant;
  final String Function(int count) studyEvents;
  final String studySave;
  final String studySaveAndClear;
  final String studySaveAndClearConfirm;
  final String studySaveAndClearInfo;
  final String studyDelete;
  final String studyDeleteConfirm;
  final String studyDeleteInfo;
  final String studyDeleteAction;
  final String studyCleared;
  final String changeBackInSettings;
  final String studyLatest;
  final String studyNoEvents;
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
    required this.assistOff,
    required this.studyTitle,
    required this.studyCondition,
    required this.conditionTitles,
    required this.conditionDescriptions,
    required this.studyChangeCondition,
    required this.studyChangeConditionInfo,
    required this.studyChange,
    required this.cancel,
    required this.studyLogging,
    required this.studyLoggingDescription,
    required this.studyParticipant,
    required this.studyEvents,
    required this.studySave,
    required this.studySaveAndClear,
    required this.studySaveAndClearConfirm,
    required this.studySaveAndClearInfo,
    required this.studyDelete,
    required this.studyDeleteConfirm,
    required this.studyDeleteInfo,
    required this.studyDeleteAction,
    required this.studyCleared,
    required this.changeBackInSettings,
    required this.studyLatest,
    required this.studyNoEvents,
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
    assistOff:
        'The assistant is turned off. You can change the sizes yourself.',
    studyTitle: 'Study',
    studyCondition: 'Condition',
    conditionTitles: {
      StudyCondition.assist: 'Assistant',
      StudyCondition.manualOnly: 'Manual only',
    },
    conditionDescriptions: {
      StudyCondition.assist: 'The Assist tab with the on-device model.',
      StudyCondition.manualOnly:
          'The Assist tab is off. Sizes are only changed in the '
          'accessibility settings.',
    },
    studyChangeCondition: 'Change the study condition?',
    studyChangeConditionInfo:
        'The Assist tab follows the new condition the next time it opens.',
    studyChange: 'Change',
    cancel: 'Cancel',
    studyLogging: 'Record study events',
    studyLoggingDescription:
        'Turn on only after the participant has agreed. Events stay on this '
        'phone until you save the log. The log keeps what the participant '
        'types in the Assist tab, never messages.',
    studyParticipant: 'Participant code',
    studyEvents: _studyEventsEn,
    studySave: 'Save log file',
    studySaveAndClear: 'Save and clear',
    studySaveAndClearConfirm: 'Save and clear the log?',
    studySaveAndClearInfo:
        'The log is cleared only after the file is saved. Use this when a '
        'participant is done.',
    studyDelete: 'Delete log',
    studyDeleteConfirm: 'Delete the log?',
    studyDeleteInfo:
        'All recorded events on this phone are deleted and cannot be '
        'restored. Use this when a participant withdraws.',
    studyDeleteAction: 'Delete',
    studyCleared: 'The log was cleared.',
    changeBackInSettings:
        'You can also change it back in the Accessibility settings.',
    studyLatest: 'Latest events',
    studyNoEvents: 'Nothing recorded yet.',
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
    assistOff: 'Assistenten er slået fra. Du kan selv ændre størrelserne.',
    studyTitle: 'Studie',
    studyCondition: 'Betingelse',
    conditionTitles: {
      StudyCondition.assist: 'Assistent',
      StudyCondition.manualOnly: 'Kun manuelt',
    },
    conditionDescriptions: {
      StudyCondition.assist: 'Assist-fanen med modellen på telefonen.',
      StudyCondition.manualOnly:
          'Assist-fanen er slået fra. Størrelser ændres kun i '
          'tilgængelighedsindstillingerne.',
    },
    studyChangeCondition: 'Skift studiebetingelse?',
    studyChangeConditionInfo:
        'Assist-fanen følger den nye betingelse, næste gang den åbnes.',
    studyChange: 'Skift',
    cancel: 'Annuller',
    studyLogging: 'Optag studiehændelser',
    studyLoggingDescription:
        'Slå kun til, når deltageren har sagt ja. Hændelserne bliver på '
        'telefonen, indtil du gemmer loggen. Loggen gemmer, hvad deltageren '
        'skriver i Assist-fanen, men aldrig beskeder.',
    studyParticipant: 'Deltagerkode',
    studyEvents: _studyEventsDa,
    studySave: 'Gem logfil',
    studySaveAndClear: 'Gem og ryd',
    studySaveAndClearConfirm: 'Gem og ryd loggen?',
    studySaveAndClearInfo:
        'Loggen ryddes først, når filen er gemt. Brug det, når en deltager '
        'er færdig.',
    studyDelete: 'Slet loggen',
    studyDeleteConfirm: 'Slet loggen?',
    studyDeleteInfo:
        'Alle optagede hændelser på telefonen slettes og kan ikke gendannes. '
        'Brug det, hvis en deltager trækker sig.',
    studyDeleteAction: 'Slet',
    studyCleared: 'Loggen blev ryddet.',
    changeBackInSettings:
        'Du kan også ændre det tilbage i tilgængelighedsindstillingerne.',
    studyLatest: 'Seneste hændelser',
    studyNoEvents: 'Intet optaget endnu.',
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

String _studyEventsEn(int count) =>
    count == 1 ? '1 event recorded' : '$count events recorded';

String _studyEventsDa(int count) =>
    count == 1 ? '1 hændelse optaget' : '$count hændelser optaget';
