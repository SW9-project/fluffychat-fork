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
  String get cancel => _text('Cancel', 'Cancelar', 'Annuller');
  String get save => _text('Save', 'Guardar', 'Gem');
  String get moreShort => _text('More', 'Más', 'Mere');
  String get more => _text('More options', 'Más opciones', 'Flere muligheder');
  String get sample =>
      _text('Example view', 'Vista de ejemplo', 'Eksempelvisning');
  String get samplePerson => _text(
    'A saved conversation',
    'Una conversación guardada',
    'En gemt samtale',
  );
  String get sampleHello => _text('Hello!', '¡Hola!', 'Hej!');
  String get sampleBye => _text('See you soon.', 'Hasta pronto.', 'Vi ses.');
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
    'Las conversaciones quedan a mano. Los filtros se agrupan en un menú. Puedes volver a la vista completa desde Chats.',
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

  // Setup dialog.
  String get preview => _text('Preview', 'Vista previa', 'Forhåndsvisning');
  String get next => _text('Continue', 'Continuar', 'Fortsæt');
  String get back => _text('Back', 'Atrás', 'Tilbage');
  String get apply => _text('Apply', 'Aplicar', 'Anvend');
  String get currentView =>
      _text('Current view', 'Vista actual', 'Nuværende visning');
  String get afterApplying =>
      _text('After applying', 'Después de aplicar', 'Efter ændringen');
  String get skip => _text(
    'Skip preview next time',
    'No mostrar la vista previa la próxima vez',
    'Spring forhåndsvisningen over næste gang',
  );
  String get skipHelp => _text(
    'You can change this later.',
    'Puedes cambiarlo luego.',
    'Du kan ændre det senere.',
  );
  String get contactsQuestion => _text(
    'Conversations at the top',
    'Conversaciones arriba',
    'Samtaler øverst',
  );
  String get frequent =>
      _text('My 3 most used', 'Mis 3 más usadas', 'Mine 3 mest brugte');
  String get frequentHelp => _text(
    'Based on chats opened here. Recent chats appear first.',
    'Según los chats que abras aquí. Al principio, los recientes.',
    'Ud fra de chats, du åbner her. I starten vises de seneste.',
  );
  String get chosen =>
      _text('I will choose them', 'Quiero elegirlas', 'Jeg vælger dem selv');
  String get chosenHelp => _text(
    'Choose up to 3 names.',
    'Elige hasta 3 nombres.',
    'Vælg op til 3 navne.',
  );
  String get editNames => _text('Choose names', 'Elegir nombres', 'Vælg navne');
  String get emptyNames => _text(
    'No conversations yet.',
    'Aún no hay conversaciones.',
    'Ingen samtaler endnu.',
  );
  String get none =>
      _text('No shortcuts', 'Sin accesos rápidos', 'Ingen genveje');
  String get noneHelp => _text(
    'Keep one list of conversations.',
    'Mantener una sola lista de conversaciones.',
    'Behold én liste med samtaler.',
  );
  String get homeQuestion => _text(
    'What would you like to see in the conversation list?',
    '¿Qué quieres ver en la lista de conversaciones?',
    'Hvad vil du se i samtalelisten?',
  );
  String get cleanHome => _text(
    'Names and unread messages only',
    'Solo nombres y mensajes sin leer',
    'Kun navne og ulæste beskeder',
  );
  String get cleanHelp => _text(
    'Clear cards, without message previews, dates or read receipts.',
    'Tarjetas claras, sin avances de mensajes, fechas ni marcas de lectura.',
    'Tydelige kort uden beskedforhåndsvisninger, datoer eller læsekvitteringer.',
  );
  String get detailedHome => _text(
    'Keep message previews',
    'Conservar los avances de mensajes',
    'Behold beskedforhåndsvisninger',
  );
  String get detailedHelp => _text(
    'Keep the familiar conversation details.',
    'Mantener la información habitual de las conversaciones.',
    'Behold de velkendte samtaleoplysninger.',
  );
  String get quietChat => _text(
    'A clearer, more spacious chat',
    'Chat claro y más espaciado',
    'En tydeligere chat med mere luft',
  );
  String get saved => _text(
    'Your text and button sizes stay the same.',
    'Se conservan tus tamaños de texto y botones.',
    'Dine tekst- og knapstørrelser forbliver de samme.',
  );
  String step(int number) =>
      _text('Step $number of 2', 'Paso $number de 2', 'Trin $number af 2');
}
