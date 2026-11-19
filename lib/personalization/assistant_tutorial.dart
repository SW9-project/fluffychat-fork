// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'accessibility_scope.dart';
import 'assistant_tutorial_l10n.dart';
import 'personalization_l10n.dart';

/// One local flag: the guide starts on the first Assistant visit; finishing
/// or skipping consumes it.
const assistantTutorialPendingKey = 'chat.fluffy.assistant_tutorial.pending.v1';

/// The guided tour that runs inside the real Assistant tab. Only the first
/// visit starts it on its own. It does not prepare the AI; the example in
/// step 2 is a real request the user sends, applies and undoes.
class AssistantGuide extends ChangeNotifier {
  static const steps = 3;
  final SharedPreferences _store;
  int? _step;

  AssistantGuide({SharedPreferences? store})
    : _store = store ?? AppSettings.store {
    if (_store.getBool(assistantTutorialPendingKey) ?? true) _step = 0;
  }

  /// The step on screen, or null when the guide is closed.
  int? get step => _step;

  void start() => _go(0);
  void back() => _go(_step! - 1);
  void next() => _step == steps - 1 ? finish() : _go(_step! + 1);

  Future<void> finish() async {
    _go(null);
    await _store.setBool(assistantTutorialPendingKey, false);
  }

  void _go(int? step) {
    _step = step;
    notifyListeners();
  }
}

/// Which real control the guide points at while the user tries the example.
enum AssistantGuideSpot { send, apply, undo, done, declined }

/// Rings a real control the guide is talking about.
class AssistantGuideSpotlight extends StatelessWidget {
  final bool on;
  final Widget child;
  const AssistantGuideSpotlight({
    required this.on,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (!on) return child;
    return DecoratedBox(
      key: const Key('assistant_guide_spotlight'),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.tertiary,
          width: 3,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(padding: const EdgeInsets.all(2), child: child),
    );
  }
}

/// The guide, docked in the Assistant tab next to the controls it explains.
class AssistantGuideCard extends StatelessWidget {
  final AssistantGuide guide;

  /// Where the user is in the example, or null outside step 2.
  final AssistantGuideSpot? spot;
  final VoidCallback onOpenSettings;

  const AssistantGuideCard({
    required this.guide,
    required this.spot,
    required this.onOpenSettings,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final step = guide.step;
    if (step == null) return const SizedBox.shrink();
    final text = AssistantTutorialL10n.of(context);
    final words = PersonalizationL10n.of(context);
    final settings = L10n.of(context).settings;
    final theme = Theme.of(context);
    final height = AccessibilityScope.of(context).buttonBox(48);
    final title = [text.welcome, text.ask, text.manual(settings)][step];
    final body = [
      text.welcomeBody,
      text.askBody(words.ask, words.applyChange, words.undo),
      text.manualBody(settings, words.accessibility),
    ][step];
    final hint = step == 1 && spot != null
        ? switch (spot!) {
            AssistantGuideSpot.send => text.trySend(words.ask),
            AssistantGuideSpot.apply => text.tryApply(
              words.applyChange,
              words.noThanks,
            ),
            AssistantGuideSpot.undo => text.tryUndo(words.undo),
            AssistantGuideSpot.done => text.tryDone(text.next),
            AssistantGuideSpot.declined => text.tryDeclined(text.next),
          }
        : null;
    return Container(
      key: const Key('assistant_guide'),
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      // Leaves room for the real controls even with very large text.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.45,
      ),
      child: SingleChildScrollView(
        // A new step starts at the top, with Skip in view.
        key: ValueKey(step),
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${text.title} · ${text.step(step + 1)}',
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                TextButton(
                  key: const Key('assistant_tutorial_skip'),
                  style: TextButton.styleFrom(minimumSize: Size(0, height)),
                  onPressed: guide.finish,
                  child: Text(text.skip),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(
                    value: (step + 1) / AssistantGuide.steps,
                    semanticsLabel: text.step(step + 1),
                  ),
                  const SizedBox(height: 12),
                  Semantics(
                    header: true,
                    liveRegion: true,
                    child: Text(title, style: theme.textTheme.titleMedium),
                  ),
                  const SizedBox(height: 4),
                  Text(body),
                  if (hint != null) ...[
                    const SizedBox(height: 8),
                    Semantics(
                      liveRegion: true,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const ExcludeSemantics(
                            child: Icon(Icons.arrow_forward),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              hint,
                              key: const Key('assistant_guide_hint'),
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (step == 2) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const Key('assistant_tutorial_settings'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: Size(0, height),
                      ),
                      icon: const Icon(Icons.settings_outlined),
                      label: Text(text.openSettings),
                      onPressed: () {
                        guide.finish();
                        onOpenSettings();
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(text.replayHint),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (step > 0)
                        OutlinedButton(
                          key: const Key('assistant_tutorial_back'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: Size(0, height),
                          ),
                          onPressed: guide.back,
                          child: Text(
                            MaterialLocalizations.of(context).backButtonTooltip,
                          ),
                        ),
                      FilledButton(
                        key: const Key('assistant_tutorial_next'),
                        style: FilledButton.styleFrom(
                          minimumSize: Size(0, height),
                        ),
                        onPressed: guide.next,
                        child: Text(step == 2 ? text.done : text.next),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
