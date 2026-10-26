// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:material_ui/material_ui.dart';

import '../accessibility_settings.dart';
import '../heuristics/heuristics_engine.dart';
import '../personalization_l10n.dart';
import '../signals/tracked_target.dart';
import 'suggestion_manager.dart';

/// A small, non-blocking card at the top of the screen that shows the open
/// suggestion, or offers undo right after one was applied.
class SuggestionCard extends StatelessWidget {
  final SuggestionManager manager;

  const SuggestionCard(this.manager, {super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: manager,
    builder: (context, _) {
      final current = manager.current;
      final applied = manager.applied;
      final Widget content;
      if (current != null) {
        content = _SuggestionContent(
          key: ValueKey(current.id),
          suggestion: current,
          manager: manager,
        );
      } else if (applied != null) {
        content = _AppliedContent(
          key: const ValueKey('applied'),
          applied: applied,
          manager: manager,
        );
      } else {
        content = const SizedBox.shrink(key: ValueKey('empty'));
      }
      return SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: FluffyThemes.animationDuration,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SizeTransition(sizeFactor: animation, child: child),
            ),
            child: content,
          ),
        ),
      );
    },
  );
}

class _CardFrame extends StatelessWidget {
  final Widget child;

  const _CardFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        // Taps on the card are answers to it, not interaction problems.
        child: TrackedTarget(
          id: 'suggestion_card',
          kind: TargetKind.excluded,
          child: Material(
            elevation: 6,
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppConfig.borderRadius),
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    );
  }
}

class _SuggestionContent extends StatelessWidget {
  final Suggestion suggestion;
  final SuggestionManager manager;

  const _SuggestionContent({
    required this.suggestion,
    required this.manager,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = PersonalizationL10n.of(context);
    final language = Localizations.localeOf(context).languageCode;
    return _CardFrame(
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  l10n.suggestion,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            suggestion.description(language),
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          _ChangePreview(suggestion: suggestion),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 4,
            children: [
              if (!suggestion.isUserRequest)
                TextButton(
                  key: const Key('suggestion_opt_out'),
                  onPressed: manager.optOut,
                  child: Text(l10n.dontSuggestAgain),
                ),
              TextButton(
                key: const Key('suggestion_not_now'),
                onPressed: manager.notNow,
                child: Text(l10n.notNow),
              ),
              FilledButton(
                key: const Key('suggestion_apply'),
                onPressed: manager.apply,
                child: Text(l10n.apply),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shows the size before and after the change side by side.
class _ChangePreview extends StatelessWidget {
  final Suggestion suggestion;

  const _ChangePreview({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = PersonalizationL10n.of(context);
    Widget sample(double value) => switch (suggestion.category) {
      ScaleCategory.text || ScaleCategory.inputText => Text(
        'Aa',
        textScaler: TextScaler.noScaling,
        style: TextStyle(fontSize: AppConfig.messageFontSize * value),
      ),
      ScaleCategory.button => Icon(Icons.send, size: 24 * value),
      ScaleCategory.avatar => CircleAvatar(
        radius: 18 * value,
        backgroundColor: theme.colorScheme.primaryContainer,
      ),
      ScaleCategory.touchTarget => Container(
        width: 40 * value,
        height: 40 * value,
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.primary),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    };
    String label(double value) => '× ${value.toStringAsFixed(1)}';

    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.categoryTitles[suggestion.category]!,
            style: theme.textTheme.titleSmall,
          ),
        ),
        Column(
          mainAxisSize: .min,
          children: [sample(suggestion.from), Text(label(suggestion.from))],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Icon(Icons.arrow_forward, color: theme.colorScheme.primary),
        ),
        Column(
          mainAxisSize: .min,
          children: [
            sample(suggestion.to),
            Text(
              label(suggestion.to),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }
}

class _AppliedContent extends StatelessWidget {
  final AppliedSuggestion applied;
  final SuggestionManager manager;

  const _AppliedContent({
    required this.applied,
    required this.manager,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = PersonalizationL10n.of(context);
    final suggestion = applied.suggestion;
    return _CardFrame(
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.changedTo(
                l10n.categoryTitles[suggestion.category]!,
                suggestion.to.toStringAsFixed(1),
              ),
            ),
          ),
          TextButton.icon(
            key: const Key('suggestion_undo'),
            onPressed: manager.undoApplied,
            icon: const Icon(Icons.undo),
            label: Text(l10n.undo),
          ),
        ],
      ),
    );
  }
}
