// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/widgets.dart';

class SimplifiedInterfaceL10n {
  final String language;
  const SimplifiedInterfaceL10n(this.language);
  factory SimplifiedInterfaceL10n.of(BuildContext context) =>
      SimplifiedInterfaceL10n(Localizations.localeOf(context).languageCode);

  String _text(String en, String es, String da) => switch (language) {
    'es' => es,
    'da' => da,
    _ => en,
  };

  String get simpleView =>
      _text('Simple view', 'Vista sencilla', 'Enkel visning');
  String get fullView => _text('Full view', 'Vista completa', 'Fuld visning');
  String get enabled => _text(
    'On · fewer options on screen',
    'Activada · menos opciones a la vista',
    'Til · færre valg på skærmen',
  );
  String get disabled => _text(
    'Off · all options available',
    'Desactivada · todas las opciones',
    'Fra · alle valgmuligheder',
  );
  String get quickAccess =>
      _text('Quick access', 'Accesos rápidos', 'Hurtig adgang');
  String get choose =>
      _text('Choose conversations', 'Elegir conversaciones', 'Vælg samtaler');
  String get edit => _text('Change', 'Cambiar', 'Rediger');
  String get chooseInfo => _text(
    'Choose up to 3 conversations you use often. Their order stays the same.',
    'Elige hasta 3 conversaciones que uses a menudo. Su orden se mantiene.',
    'Vælg op til 3 samtaler, du ofte bruger. Rækkefølgen bevares.',
  );
  String get empty => _text(
    'Start a conversation to add it here.',
    'Inicia una conversación para añadirla aquí.',
    'Start en samtale for at tilføje den her.',
  );
  String get open =>
      _text('Open conversation', 'Abrir conversación', 'Åbn samtale');
  String get search =>
      _text('Search conversations', 'Buscar conversaciones', 'Søg i samtaler');
  String get others =>
      _text('Other conversations', 'Otras conversaciones', 'Andre samtaler');
  String get conversations =>
      _text('Conversations', 'Conversaciones', 'Samtaler');
  String get filter => _text('Filter', 'Filtrar', 'Filtrer');
  String get cancel => _text('Cancel', 'Cancelar', 'Annuller');
  String get save => _text('Save', 'Guardar', 'Gem');
  String get moreShort => _text('More', 'M\u00e1s', 'Mere');
  String get more => _text('More options', 'Más opciones', 'Flere muligheder');
  String get voice => _text('Voice message', 'Mensaje de voz', 'Talebesked');
  String get photo =>
      _text('Photo or file', 'Foto o archivo', 'Foto eller fil');
  String get send => _text('Send', 'Enviar', 'Send');
  String get sample =>
      _text('Example view', 'Vista de ejemplo', 'Eksempelvisning');
  String get samplePerson => _text(
    'A saved conversation',
    'Una conversación guardada',
    'En gemt samtale',
  );
  String get turnOn => _text(
    'Try simple view?',
    '¿Probar la vista sencilla?',
    'Prøv enkel visning?',
  );
  String get turnOff => _text(
    'Return to full view?',
    '¿Volver a la vista completa?',
    'Gå tilbage til fuld visning?',
  );
  String get proposalInfo => _text(
    'Keep conversations and everyday actions easy to find. Filters are grouped in one menu. You can switch back on the Chats screen.',
    'Las conversaciones quedan a mano. Los filtros se agrupan en un men\u00fa. Puedes volver a la vista completa desde Chats.',
    'Behold samtaler og daglige handlinger tæt på. Filtre er samlet i en menu. Du kan skifte tilbage fra Chats.',
  );
  String get unchanged => _text(
    'The view has not changed.',
    'La vista no ha cambiado.',
    'Visningen er ikke ændret.',
  );
  String get alreadySelected => _text(
    'This view is already selected.',
    'Esta vista ya está seleccionada.',
    'Denne visning er allerede valgt.',
  );
  String get stale => _text(
    'The view changed after this suggestion. Ask again to make a new change.',
    'La vista ha cambiado desde esta propuesta. Pide otra para hacer un cambio nuevo.',
    'Visningen er ændret siden forslaget. Spørg igen for at ændre den.',
  );
  String unread(int count) =>
      _text('$count unread', '$count sin leer', '$count ulæste');
}
