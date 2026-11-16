// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

import 'simplified_interface.dart';
import 'simplified_interface_l10n.dart';
import 'simplified_interface_widgets.dart';

class SimpleSetupL10n {
  final bool es;
  SimpleSetupL10n.of(BuildContext context)
    : es = Localizations.localeOf(context).languageCode == 'es';
  String tr(String en, String spanish) => es ? spanish : en;
  String get personalize => tr('Personalize', 'Personalizar');
  String get title => tr('Your simple view', 'Tu vista sencilla');
  String get subtitle =>
      tr('Your conversations, within reach', 'Tus conversaciones, a mano');
  String get preview =>
      tr('See the change first', 'Mira el cambio antes de aplicarlo');
  String get next => tr('Continue', 'Continuar');
  String get back => tr('Back', 'Atrás');
  String get apply => tr('Apply this view', 'Aplicar esta vista');
  String get skip => tr(
    'Do not show this preview again when I use the switch',
    'No volver a mostrar esta vista previa al usar el interruptor',
  );
  String get skipHelp => tr(
    'You can turn previews back on in Personalize. Assistant always asks before applying a suggestion.',
    'Puedes recuperar la vista previa en Personalizar. Assistant siempre pide confirmar sus propuestas.',
  );
  String get contactsQuestion => tr(
    'Which conversations would you like at the top?',
    '¿Qué conversaciones quieres tener arriba?',
  );
  String get frequent => tr('My 3 most used', 'Mis 3 más usadas');
  String get frequentHelp => tr(
    'Based on conversations you open from Chats on this device after choosing this option. Recent conversations appear until there is enough activity. No messages are read.',
    'Según las conversaciones que abras desde Chats en este dispositivo a partir de ahora. Al principio aparecerán las recientes. No se lee el contenido de los mensajes.',
  );
  String get chosen => tr('I will choose them', 'Quiero elegirlas');
  String get chosenHelp => tr(
    'Choose up to 3 conversations from Quick access. They stay in your chosen order.',
    'Elige hasta 3 conversaciones desde Accesos rápidos. Se mantiene el orden que elijas.',
  );
  String get none => tr('No shortcuts', 'Sin accesos rápidos');
  String get noneHelp => tr(
    'Keep one list of conversations.',
    'Mantener una sola lista de conversaciones.',
  );
  String get homeQuestion => tr(
    'What would you like to see in the conversation list?',
    '¿Qué quieres ver en la lista de conversaciones?',
  );
  String get cleanHome =>
      tr('Names and unread messages only', 'Solo nombres y mensajes sin leer');
  String get cleanHelp => tr(
    'Clear cards, without message previews, dates or read receipts.',
    'Tarjetas claras, sin avances de mensajes, fechas ni marcas de lectura.',
  );
  String get detailedHome =>
      tr('Keep message previews', 'Conservar los avances de mensajes');
  String get detailedHelp => tr(
    'Keep the familiar conversation details.',
    'Mantener la información habitual de las conversaciones.',
  );
  String get chatQuestion =>
      tr('How would you like the chat to look?', '¿Cómo quieres ver el chat?');
  String get quietChat => tr('A calmer chat', 'Un chat más sencillo');
  String get quietHelp => tr(
    'Plain background, less secondary information and emojis grouped with attachments. Voice and sending stay available.',
    'Fondo liso, menos información secundaria y emojis agrupados con los adjuntos. Voz y envío siguen disponibles.',
  );
  String get familiarChat =>
      tr('Keep my usual chat', 'Mantener mi chat habitual');
  String get familiarHelp => tr(
    'Keep the background and controls you already use.',
    'Conservar el fondo y los controles que ya utilizas.',
  );
  String get saved => tr(
    'Your choices are remembered. You can change them in Personalize.',
    'Tus elecciones se guardan. Puedes cambiarlas en Personalizar.',
  );
  String question(int number) =>
      tr('Question $number of 3', 'Pregunta $number de 3');
}

class _ViewChoice {
  final SimpleViewPreferences preferences;
  final bool skipPreview;
  const _ViewChoice(this.preferences, this.skipPreview);
}

/// Shared by the home switch and Assistant. Cancelling never saves answers
/// or the skip-preview checkbox. Assistant keeps its own confirmation flow.
/// Returns the revision captured at Apply, before asynchronous persistence,
/// so Undo cannot overwrite a newer manual choice. Null means no change.
Future<int?> requestSimpleViewChange(
  BuildContext context,
  SimplifiedInterfaceController controller,
  bool target, {
  bool personalize = false,
  bool previewAlreadyShown = false,
}) async {
  final needsQuestions = personalize || (target && !controller.configured);
  if (!needsQuestions && (previewAlreadyShown || controller.skipPreview)) {
    final write = controller.setEnabled(target);
    final revision = controller.revision;
    await write;
    return revision;
  }
  final revision = controller.revision;
  final result = await showDialog<_ViewChoice>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SimpleSetupDialog(
      controller: controller,
      target: target,
      questions: needsQuestions,
    ),
  );
  if (result == null || controller.revision != revision) return null;
  final Future<void> write;
  if (controller.configured || target) {
    write = controller.applyPreferences(
      result.preferences,
      enabled: target,
      skipPreview: result.skipPreview,
    );
  } else {
    write = controller
        .setEnabled(target)
        .then((_) => controller.setSkipPreview(result.skipPreview));
  }
  final appliedRevision = controller.revision;
  await write;
  return appliedRevision;
}

class _SimpleSetupDialog extends StatefulWidget {
  final SimplifiedInterfaceController controller;
  final bool target;
  final bool questions;
  const _SimpleSetupDialog({
    required this.controller,
    required this.target,
    required this.questions,
  });
  @override
  State<_SimpleSetupDialog> createState() => _SimpleSetupDialogState();
}

class _SimpleSetupDialogState extends State<_SimpleSetupDialog> {
  late int _step = widget.questions ? 0 : 3;
  late SimpleViewPreferences _draft = widget.controller.preferences;
  late bool _skip = widget.controller.skipPreview;
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _go(int step) {
    setState(() => _step = step);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Widget _choice(
    String id,
    String title,
    String description,
    bool selected,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            key: Key(id),
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    selected ? Icons.check_circle : Icons.circle_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Text(description),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = SimpleSetupL10n.of(context);
    final common = SimplifiedInterfaceL10n.of(context);
    final theme = Theme.of(context);
    final heading = switch (_step) {
      0 => text.contactsQuestion,
      1 => text.homeQuestion,
      2 => text.chatQuestion,
      _ => text.preview,
    };
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(text.title),
        ),
        body: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_step < 3) ...[
                Text(
                  text.question(_step + 1),
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: (_step + 1) / 3),
                const SizedBox(height: 24),
              ],
              Text(heading, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 24),
              if (_step == 0) ...[
                _choice(
                  'setup_frequent',
                  text.frequent,
                  text.frequentHelp,
                  _draft.quickAccess == SimpleQuickAccess.frequent,
                  () => setState(
                    () => _draft = _draft.copyWith(
                      quickAccess: SimpleQuickAccess.frequent,
                    ),
                  ),
                ),
                _choice(
                  'setup_chosen',
                  text.chosen,
                  text.chosenHelp,
                  _draft.quickAccess == SimpleQuickAccess.chosen,
                  () => setState(
                    () => _draft = _draft.copyWith(
                      quickAccess: SimpleQuickAccess.chosen,
                    ),
                  ),
                ),
                _choice(
                  'setup_none',
                  text.none,
                  text.noneHelp,
                  _draft.quickAccess == SimpleQuickAccess.none,
                  () => setState(
                    () => _draft = _draft.copyWith(
                      quickAccess: SimpleQuickAccess.none,
                    ),
                  ),
                ),
              ],
              if (_step == 1) ...[
                _choice(
                  'setup_clean_home',
                  text.cleanHome,
                  text.cleanHelp,
                  _draft.cleanHome,
                  () =>
                      setState(() => _draft = _draft.copyWith(cleanHome: true)),
                ),
                _choice(
                  'setup_detailed_home',
                  text.detailedHome,
                  text.detailedHelp,
                  !_draft.cleanHome,
                  () => setState(
                    () => _draft = _draft.copyWith(cleanHome: false),
                  ),
                ),
              ],
              if (_step == 2) ...[
                _choice(
                  'setup_quiet_chat',
                  text.quietChat,
                  text.quietHelp,
                  _draft.quietChat,
                  () =>
                      setState(() => _draft = _draft.copyWith(quietChat: true)),
                ),
                _choice(
                  'setup_familiar_chat',
                  text.familiarChat,
                  text.familiarHelp,
                  !_draft.quietChat,
                  () => setState(
                    () => _draft = _draft.copyWith(quietChat: false),
                  ),
                ),
              ],
              if (_step == 3) ...[
                ExpansionTile(
                  title: Text(text.tr('Current view', 'Vista actual')),
                  children: [
                    SimplifiedInterfacePreview(
                      enabled: widget.controller.enabled,
                      preferences: widget.controller.preferences,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  text.tr('After applying', 'Despu\u00e9s de aplicar'),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                SimplifiedInterfacePreview(
                  enabled: widget.target,
                  preferences: _draft,
                ),
                const SizedBox(height: 16),
                Text(text.saved),
                CheckboxListTile(
                  key: const Key('simple_skip_preview'),
                  contentPadding: EdgeInsets.zero,
                  value: _skip,
                  onChanged: (value) => setState(() => _skip = value ?? false),
                  title: Text(text.skip),
                ),
                Text(text.skipHelp, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 8,
              children: [
                TextButton(
                  key: const Key('simple_setup_cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(common.cancel),
                ),
                if (_step > 0 && widget.questions)
                  OutlinedButton(
                    key: const Key('simple_setup_back'),
                    onPressed: () => _go(_step - 1),
                    child: Text(text.back),
                  ),
                FilledButton(
                  key: Key(
                    _step == 3 ? 'simple_setup_apply' : 'simple_setup_next',
                  ),
                  onPressed: () => _step < 3
                      ? _go(_step + 1)
                      : Navigator.of(context).pop(_ViewChoice(_draft, _skip)),
                  child: Text(_step == 3 ? text.apply : text.next),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
