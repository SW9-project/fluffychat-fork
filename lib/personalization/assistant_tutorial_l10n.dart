// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

class AssistantTutorialL10n {
  final String language;
  const AssistantTutorialL10n(this.language);
  factory AssistantTutorialL10n.of(BuildContext context) =>
      AssistantTutorialL10n(Localizations.localeOf(context).languageCode);

  String _text(String en, String es, String da) => switch (language) {
    'es' => es,
    'da' => da,
    _ => en,
  };

  String get title =>
      _text('Meet Assistant', 'Conoce Assistant', 'Mød Assistant');
  String get skip => _text('Skip', 'Omitir', 'Spring over');
  String get next => _text('Next', 'Siguiente', 'Næste');
  String get done => _text('Got it', 'Entendido', 'Forstået');
  String step(int number) =>
      _text('Step $number of 3', 'Paso $number de 3', 'Trin $number af 3');
  String get welcome => _text(
    'Make the app easier for you',
    'Una app más fácil para ti',
    'Gør appen lettere for dig',
  );
  String get welcomeBody => _text(
    'Assistant helps you change text, buttons and more. You choose what changes.',
    'Assistant te ayuda a cambiar el texto, los botones y más. Tú decides qué cambiar.',
    'Assistant hjælper dig med at ændre tekst, knapper og mere. Du bestemmer ændringerne.',
  );
  String get setup => _text(
    'If you see Set up, tap it once to get started.',
    'Si aparece Set up, púlsalo una vez para empezar.',
    'Tryk på Klargør, hvis knappen vises, for at komme i gang.',
  );
  String get ask => _text(
    'Ask, review, apply',
    'Pide, revisa y aplica',
    'Spørg, se og anvend',
  );
  String get askBody => _text(
    'Write what you need and tap Ask. Check the preview, then choose Apply. Undo reverses the last change.',
    'Escribe qué necesitas y pulsa Ask. Revisa la vista previa y elige Apply. Undo deshace el último cambio.',
    'Skriv, hvad du har brug for, og tryk Spørg. Se forhåndsvisningen, og vælg Anvend. Fortryd ophæver den seneste ændring.',
  );
  String get example => _text(
    'Make the text bigger',
    'Haz el texto más grande',
    'Gør teksten større',
  );
  String manual(String settings) => _text(
    'You can also use $settings',
    'También puedes usar $settings',
    'Du kan også bruge $settings',
  );
  String manualBody(String settings, String accessibility) => _text(
    'Prefer to choose yourself? Find $settings in the bottom bar, then open $accessibility. You can change things without Assistant.',
    '¿Prefieres elegir los ajustes tú? Abre $settings en la barra inferior y entra en $accessibility. Puedes cambiar las cosas sin Assistant.',
    'Vil du hellere vælge selv? Find $settings i den nederste bjælke, og åbn $accessibility. Du kan ændre ting uden Assistant.',
  );
  String get openSettings => _text(
    'Open accessibility settings',
    'Abrir ajustes de accesibilidad',
    'Åbn tilgængelighedsindstillinger',
  );
  String get replay => _text(
    'Assistant tutorial',
    'Tutorial de Assistant',
    'Vejledning til Assistant',
  );
  String get showNow => _text('View tutorial', 'Ver tutorial', 'Se vejledning');
  String get showNext => _text(
    'Show on next Assistant visit',
    'Mostrar al volver a abrir Assistant',
    'Vis næste gang Assistant åbnes',
  );
  String get showNextHelp => _text(
    'Turn on to see the tutorial next time.',
    'Actívalo para ver el tutorial la próxima vez.',
    'Slå til for at se vejledningen næste gang.',
  );
}
