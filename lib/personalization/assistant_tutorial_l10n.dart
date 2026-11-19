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
  String trySend(String ask) => _text(
    'The example is already in the box below. Tap $ask (the arrow) to send it.',
    'El ejemplo ya está en el cuadro de abajo. Pulsa $ask (la flecha) para enviarlo.',
    'Eksemplet står allerede i feltet nedenfor. Tryk $ask (pilen) for at sende det.',
  );
  String tryApply(String apply, String noThanks) => _text(
    'This is a preview of the change; nothing has changed yet. Tap $apply to keep it, or $noThanks to discard it.',
    'Esto es una vista previa del cambio; todavía no ha cambiado nada. Pulsa $apply para aplicarlo o $noThanks para descartarlo.',
    'Dette er en forhåndsvisning af ændringen; intet er ændret endnu. Tryk $apply for at beholde den, eller $noThanks for at kassere den.',
  );
  String tryDeclined(String next) => _text(
    'The change was discarded, so nothing changed. Tap $next to continue.',
    'El cambio se descartó, así que no ha cambiado nada. Pulsa $next para continuar.',
    'Ændringen blev kasseret, så intet er ændret. Tryk $next for at fortsætte.',
  );
  String tryUndo(String undo) => _text(
    'The change is on now. Tap $undo to go back.',
    'El cambio ya está activo. Pulsa $undo para volver atrás.',
    'Ændringen er slået til nu. Tryk $undo for at gå tilbage.',
  );
  String tryDone(String next) => _text(
    'Everything is back as before. Tap $next to continue.',
    'Todo ha vuelto a como estaba. Pulsa $next para continuar.',
    'Alt er som før igen. Tryk $next for at fortsætte.',
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
  String get replayHint => _text(
    'You can replay this guide with the ? button at the top of Assistant.',
    'Puedes repetir esta guía con el botón ? de la parte superior de Assistant.',
    'Du kan se vejledningen igen med ?-knappen øverst i Assistant.',
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
}
