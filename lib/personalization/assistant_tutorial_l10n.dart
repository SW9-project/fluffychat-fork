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
    'Assistant helps you change text, buttons and the layout. You review each change before applying it.',
    'Assistant te ayuda a cambiar el texto, los botones y la interfaz. Tú revisas cada cambio antes de aplicarlo.',
    'Assistant hjælper med tekst, knapper og layout. Du ser hver ændring, før du anvender den.',
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
  String askBody(String ask, String apply, String undo) => _text(
    'Type what you need, or use the microphone. Tap $ask, review the preview, then $apply. $undo takes you back.',
    'Escribe qué necesitas o usa el micrófono. Pulsa $ask, revisa la vista previa y elige $apply. $undo permite volver atrás.',
    'Skriv, hvad du har brug for, eller brug mikrofonen. Tryk $ask, se forhåndsvisningen, og vælg $apply. $undo fører dig tilbage.',
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
    'You can choose the same changes yourself. Tap $settings at the bottom right, then $accessibility.',
    'También puedes elegir los cambios tú. Pulsa $settings abajo a la derecha y entra en $accessibility.',
    'Du kan også vælge ændringerne selv. Tryk $settings nederst til højre og derefter $accessibility.',
  );
  String get bottomBar =>
      _text('Bottom bar', 'Barra inferior', 'Nederste bjælke');
  String get practice =>
      _text('Try an example', 'Prueba un ejemplo', 'Prøv et eksempel');
  String get practiceHint => _text(
    'Practice only. Your settings stay the same.',
    'Es una práctica. Tus ajustes se mantienen.',
    'Kun en øvelse. Dine indstillinger bevares.',
  );
  String get sample => _text('Your message', 'Tu mensaje', 'Din besked');
  String get currentSize =>
      _text('Current text size', 'Tamaño actual', 'Nuværende tekststørrelse');
  String get largerSize =>
      _text('Larger text', 'Texto más grande', 'Større tekst');
  String get exampleApplied => _text(
    'The example text is bigger.',
    'El texto del ejemplo es más grande.',
    'Eksempelteksten er større.',
  );
  String get exampleUndone => _text(
    'Back to the original size.',
    'De vuelta al tamaño original.',
    'Tilbage til den oprindelige størrelse.',
  );
  String replayHint(String settings) => _text(
    'You can replay this guide from $settings.',
    'Puedes repetir esta guía desde $settings.',
    'Du kan se vejledningen igen i $settings.',
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
