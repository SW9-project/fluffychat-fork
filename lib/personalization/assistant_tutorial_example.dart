// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

import 'accessibility_scope.dart';
import 'assistant_tutorial_l10n.dart';
import 'personalization_l10n.dart';

enum _ExampleStage { request, preview, applied, undone }

/// A local practice interaction: no model, settings writes or chat messages.
class AssistantTutorialExample extends StatefulWidget {
  const AssistantTutorialExample({super.key});

  @override
  State<AssistantTutorialExample> createState() =>
      _AssistantTutorialExampleState();
}

class _AssistantTutorialExampleState extends State<AssistantTutorialExample> {
  _ExampleStage _stage = _ExampleStage.request;

  @override
  Widget build(BuildContext context) {
    final text = AssistantTutorialL10n.of(context);
    final words = PersonalizationL10n.of(context);
    final theme = Theme.of(context);
    final sizes = AccessibilityScope.of(context);
    final minimumSize = Size(0, sizes.buttonBox(48));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(text.practice, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(text.practiceHint, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ExcludeSemantics(child: Icon(Icons.chat_bubble_outline)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '“${text.example}”',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ],
          ),
          if (_stage == _ExampleStage.preview) ...[
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final samples = [
                  _sample(context, words.previewNow, false),
                  _sample(context, words.previewSuggested, true),
                ];
                if (constraints.maxWidth < 300 ||
                    MediaQuery.textScalerOf(context).scale(14) > 20) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      samples[0],
                      const SizedBox(height: 12),
                      samples[1],
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: samples[0]),
                    const SizedBox(width: 12),
                    Expanded(child: samples[1]),
                  ],
                );
              },
            ),
          ],
          if (_stage == _ExampleStage.applied ||
              _stage == _ExampleStage.undone) ...[
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(
                _stage == _ExampleStage.applied
                    ? text.exampleApplied
                    : text.exampleUndone,
                style: theme.textTheme.bodyLarge,
              ),
            ),
            const SizedBox(height: 12),
            _sample(context, words.previewNow, _stage == _ExampleStage.applied),
          ],
          const SizedBox(height: 16),
          if (_stage == _ExampleStage.applied)
            OutlinedButton.icon(
              key: const Key('tutorial_example_undo'),
              style: OutlinedButton.styleFrom(minimumSize: minimumSize),
              onPressed: () => setState(() => _stage = _ExampleStage.undone),
              icon: const Icon(Icons.undo),
              label: Text(words.undo),
            )
          else
            FilledButton.icon(
              key: Key(
                _stage == _ExampleStage.preview
                    ? 'tutorial_example_apply'
                    : 'tutorial_example_ask',
              ),
              style: FilledButton.styleFrom(minimumSize: minimumSize),
              onPressed: () => setState(
                () => _stage = _stage == _ExampleStage.preview
                    ? _ExampleStage.applied
                    : _ExampleStage.preview,
              ),
              icon: Icon(
                _stage == _ExampleStage.preview
                    ? Icons.check
                    : Icons.send_outlined,
              ),
              label: Text(
                _stage == _ExampleStage.preview ? words.applyChange : words.ask,
              ),
            ),
        ],
      ),
    );
  }

  Widget _sample(BuildContext context, String label, bool larger) {
    final text = AssistantTutorialL10n.of(context);
    final theme = Theme.of(context);
    return Semantics(
      label:
          '$label. ${larger ? text.largerSize : text.currentSize}. ${text.sample}',
      excludeSemantics: true,
      child: Container(
        key: Key(larger ? 'tutorial_sample_larger' : 'tutorial_sample_current'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(
              text.sample,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontSize: larger ? 22 : 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
