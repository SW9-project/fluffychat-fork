// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

import 'accessibility_scope.dart';
import 'quick_access_conversations.dart';
import 'simple_view_conversations.dart';
import 'simple_view_dialog.dart';
import 'simplified_interface.dart';
import 'simplified_interface_l10n.dart';
import 'simplified_interface_widgets.dart';

class _ViewChoice {
  final SimpleViewPreferences preferences;
  final bool skipPreview;
  final List<String> selectedIds;
  const _ViewChoice(this.preferences, this.skipPreview, this.selectedIds);
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
  SimpleViewConversations? conversations,
}) async {
  final source = conversations ?? SimpleViewConversations.fromContext(context);
  final needsQuestions = personalize || (target && !controller.configured);
  if (!needsQuestions && (previewAlreadyShown || controller.skipPreview)) {
    final write = controller.setEnabled(target);
    final revision = controller.revision;
    await write;
    return revision;
  }
  final revision = controller.revision;
  final result = await showSimpleViewDialog<_ViewChoice>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SimpleSetupDialog(
      controller: controller,
      target: target,
      questions: needsQuestions,
      source: source,
    ),
  );
  if (result == null || !context.mounted || controller.revision != revision) {
    return null;
  }
  if (conversations == null &&
      source != null &&
      SimpleViewConversations.fromContext(context)?.account != source.account) {
    return null;
  }
  final Future<void> write;
  if (controller.configured || target) {
    write = controller.applyPreferences(
      result.preferences,
      enabled: target,
      skipPreview: result.skipPreview,
      accountId: source?.account,
      quickAccessIds: result.preferences.quickAccess == SimpleQuickAccess.chosen
          ? result.selectedIds
          : null,
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
  final SimpleViewConversations? source;
  const _SimpleSetupDialog({
    required this.controller,
    required this.target,
    required this.questions,
    this.source,
  });
  @override
  State<_SimpleSetupDialog> createState() => _SimpleSetupDialogState();
}

class _SimpleSetupDialogState extends State<_SimpleSetupDialog> {
  late int _step = widget.questions ? 0 : 2;
  late SimpleViewPreferences _draft = widget.controller.preferences;
  late bool _skip = widget.controller.skipPreview;
  late List<String> _selected = widget.controller.quickAccessFor(
    widget.source?.account ?? '',
  );

  List<String> get _visibleIds =>
      _draft.quickAccess == SimpleQuickAccess.frequent
      ? widget.controller.frequentFor(
          widget.source?.account ?? '',
          widget.source?.conversations.map((entry) => entry.id).toList() ?? [],
        )
      : _draft.quickAccess == SimpleQuickAccess.chosen
      ? _selected
      : [];

  List<String> get _names => [
    for (final id in _visibleIds)
      for (final entry
          in widget.source?.conversations ?? <QuickAccessConversation>[])
        if (entry.id == id) entry.name,
  ];

  Future<void> _chooseNames() async {
    final result = await chooseSimpleConversations(
      context,
      widget.source?.conversations ?? [],
      _selected,
    );
    if (result != null && mounted) setState(() => _selected = result);
  }

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

  Widget _contactNames(SimplifiedInterfaceL10n text) => Padding(
    key: const Key('setup_contact_names'),
    padding: const EdgeInsets.only(bottom: 16),
    child: _names.isEmpty
        ? Text(text.emptyNames)
        : Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [for (final name in _names) Chip(label: Text(name))],
          ),
  );

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
              ? theme.colorScheme.primary.withAlpha(18)
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
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    selected ? Icons.check_circle : Icons.circle_outlined,
                    size: AccessibilityScope.of(context).icon(),
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
    final text = SimplifiedInterfaceL10n.of(context);
    final theme = Theme.of(context);
    final heading = switch (_step) {
      0 => text.contactsQuestion,
      1 => text.homeQuestion,
      _ => text.preview,
    };
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(text.simpleView),
          toolbarHeight: MediaQuery.textScalerOf(context).scale(22) * 2 + 16,
        ),
        body: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_step < 2) ...[
                Text(text.step(_step + 1), style: theme.textTheme.labelLarge),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: (_step + 1) / 2),
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
                if (_draft.quickAccess == SimpleQuickAccess.frequent)
                  _contactNames(text),
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
                if (_draft.quickAccess == SimpleQuickAccess.chosen) ...[
                  _contactNames(text),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: OutlinedButton.icon(
                      key: const Key('setup_choose_names'),
                      onPressed: widget.source?.conversations.isNotEmpty == true
                          ? _chooseNames
                          : null,
                      icon: const Icon(Icons.person_add_outlined),
                      label: Text(text.editNames),
                    ),
                  ),
                ],
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
                ExpansionTile(
                  title: Text(text.currentView),
                  children: [
                    SimplifiedInterfacePreview(
                      enabled: widget.controller.enabled,
                      preferences: widget.controller.preferences,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(text.afterApplying, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                SimplifiedInterfacePreview(
                  enabled: widget.target,
                  preferences: _draft,
                  conversationNames: _names,
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
                  child: Text(text.cancel),
                ),
                if (_step > 0 && widget.questions)
                  OutlinedButton(
                    key: const Key('simple_setup_back'),
                    onPressed: () => _go(_step - 1),
                    child: Text(text.back),
                  ),
                FilledButton(
                  key: Key(
                    _step == 2 ? 'simple_setup_apply' : 'simple_setup_next',
                  ),
                  onPressed: () => _step < 2
                      ? _go(_step + 1)
                      : Navigator.of(
                          context,
                        ).pop(_ViewChoice(_draft, _skip, _selected)),
                  child: Text(_step == 2 ? text.apply : text.next),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
