// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/layouts/main_navigation_bar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'accessibility_scope.dart';
import 'assistant_tutorial_example.dart';
import 'assistant_tutorial_l10n.dart';
import 'personalization_l10n.dart';
import 'simple_view_dialog.dart';

/// One local flag: completing/skipping consumes it; Settings can re-arm it.
const assistantTutorialPendingKey = 'chat.fluffy.assistant_tutorial.pending.v1';

Future<void> showAssistantTutorial(
  BuildContext context, {
  SharedPreferences? store,
  required VoidCallback onOpenSettings,
}) async {
  final preferences = store ?? AppSettings.store;
  final openSettings = await showSimpleViewDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _Tutorial(),
  );
  await preferences.setBool(assistantTutorialPendingKey, false);
  if (context.mounted && openSettings == true) onOpenSettings();
}

/// Only the first visit is automatic. This does not prepare the AI or change
/// accessibility settings, and is safe to dismiss without completing the steps.
class AssistantTutorialGate extends StatefulWidget {
  final Widget child;
  final VoidCallback onOpenSettings;
  final SharedPreferences? store;
  const AssistantTutorialGate({
    required this.child,
    required this.onOpenSettings,
    this.store,
    super.key,
  });

  @override
  State<AssistantTutorialGate> createState() => _AssistantTutorialGateState();
}

class _AssistantTutorialGateState extends State<AssistantTutorialGate> {
  bool _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    final store = widget.store ?? AppSettings.store;
    if (!(store.getBool(assistantTutorialPendingKey) ?? true)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showAssistantTutorial(
        context,
        store: store,
        onOpenSettings: widget.onOpenSettings,
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class AssistantTutorialSettings extends StatefulWidget {
  final VoidCallback onOpenSettings;
  final SharedPreferences? store;
  const AssistantTutorialSettings({
    required this.onOpenSettings,
    this.store,
    super.key,
  });

  @override
  State<AssistantTutorialSettings> createState() =>
      _AssistantTutorialSettingsState();
}

class _AssistantTutorialSettingsState extends State<AssistantTutorialSettings> {
  SharedPreferences get _store => widget.store ?? AppSettings.store;

  @override
  Widget build(BuildContext context) {
    final text = AssistantTutorialL10n.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.help_outline),
          title: Text(text.replay),
          subtitle: Text(text.showNow),
          onTap: () async {
            await showAssistantTutorial(
              context,
              store: _store,
              onOpenSettings: widget.onOpenSettings,
            );
            if (mounted) setState(() {});
          },
        ),
        SwitchListTile.adaptive(
          key: const Key('assistant_tutorial_toggle'),
          title: Text(text.showNext),
          subtitle: Text(text.showNextHelp),
          value: _store.getBool(assistantTutorialPendingKey) ?? true,
          onChanged: (value) async {
            await _store.setBool(assistantTutorialPendingKey, value);
            if (mounted) setState(() {});
          },
        ),
      ],
    );
  }
}

class _Tutorial extends StatefulWidget {
  const _Tutorial();
  @override
  State<_Tutorial> createState() => _TutorialState();
}

class _TutorialState extends State<_Tutorial> {
  int _step = 0;
  final _scroll = ScrollController();

  void _go(int step) {
    setState(() => _step = step);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = AssistantTutorialL10n.of(context);
    final theme = Theme.of(context);
    final sizes = AccessibilityScope.of(context);
    final title = [
      text.welcome,
      text.ask,
      text.manual(L10n.of(context).settings),
    ][_step];
    final body = [
      text.welcomeBody,
      text.askBody(
        PersonalizationL10n.of(context).ask,
        PersonalizationL10n.of(context).applyChange,
        PersonalizationL10n.of(context).undo,
      ),
      text.manualBody(
        L10n.of(context).settings,
        PersonalizationL10n.of(context).accessibility,
      ),
    ][_step];
    final height = sizes.buttonBox(48);
    return Dialog.fullscreen(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              text.title,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          TextButton(
                            key: const Key('assistant_tutorial_skip'),
                            style: TextButton.styleFrom(
                              minimumSize: Size(0, height),
                            ),
                            onPressed: () => Navigator.of(context).pop(false),
                            child: Text(text.skip),
                          ),
                        ],
                      ),
                      Text(
                        text.step(_step + 1),
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: (_step + 1) / 3,
                        semanticsLabel: text.step(_step + 1),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          header: true,
                          liveRegion: true,
                          child: Text(
                            title,
                            style: theme.textTheme.headlineSmall,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(body, style: theme.textTheme.bodyLarge),
                        const SizedBox(height: 20),
                        _visual(context),
                        if (_step == 0) ...[
                          const SizedBox(height: 24),
                          Text(text.setup, style: theme.textTheme.bodyMedium),
                        ],
                        if (_step == 2) ...[
                          const SizedBox(height: 24),
                          OutlinedButton.icon(
                            key: const Key('assistant_tutorial_settings'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: Size(0, height),
                            ),
                            icon: const Icon(Icons.settings_outlined),
                            label: Text(text.openSettings),
                            onPressed: () => Navigator.of(context).pop(true),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            text.replayHint(L10n.of(context).settings),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_step > 0)
                        OutlinedButton(
                          key: const Key('assistant_tutorial_back'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: Size(0, height),
                          ),
                          onPressed: () => _go(_step - 1),
                          child: Text(
                            MaterialLocalizations.of(context).backButtonTooltip,
                          ),
                        ),
                      FilledButton(
                        key: const Key('assistant_tutorial_next'),
                        style: FilledButton.styleFrom(
                          minimumSize: Size(0, height),
                        ),
                        onPressed: () => _step == 2
                            ? Navigator.of(context).pop(false)
                            : _go(_step + 1),
                        child: Text(_step == 2 ? text.done : text.next),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _visual(BuildContext context) {
    if (_step == 1) return const AssistantTutorialExample();
    final theme = Theme.of(context);
    final text = AssistantTutorialL10n.of(context);
    final selected = _step == 0
        ? MainNavigationTab.assistant
        : MainNavigationTab.settings;
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(text.bottomBar, style: theme.textTheme.labelLarge),
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    for (final tab in MainNavigationTab.values)
                      Expanded(
                        child: Container(
                          key: tab == selected
                              ? const Key('tutorial_navigation_selected')
                              : null,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: tab == selected
                                ? theme.colorScheme.primaryContainer
                                : null,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            tab.materialIcon(tab == selected),
                            color: tab == selected
                                ? theme.colorScheme.onPrimaryContainer
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              selected.localizedLabel(L10n.of(context)),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (_step == 2) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Icon(Icons.arrow_downward),
              ),
              Row(
                children: [
                  Icon(
                    Icons.accessibility_new,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      PersonalizationL10n.of(context).accessibility,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
