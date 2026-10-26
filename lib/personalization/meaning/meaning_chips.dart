// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

import '../personalization_l10n.dart';
import 'meaning_draft.dart';
import 'message_meaning.dart';

IconData intentIcon(MessageIntent intent) => switch (intent) {
  MessageIntent.question => Icons.help_outline,
  MessageIntent.information => Icons.info_outline,
  MessageIntent.request => Icons.assignment_turned_in_outlined,
};

String intentLabel(PersonalizationL10n l10n, MessageIntent intent) =>
    switch (intent) {
      MessageIntent.question => l10n.meaningQuestion,
      MessageIntent.information => l10n.meaningInformation,
      MessageIntent.request => l10n.meaningRequest,
    };

/// Shows the sender what will be sent as the message's meaning, above the
/// input, and lets them change it before sending.
class MeaningChips extends StatelessWidget {
  final MeaningDraft draft;

  const MeaningChips(this.draft, {super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: draft,
    builder: (context, _) {
      final meaning = draft.meaning;
      if (meaning == null) return const SizedBox.shrink();
      final theme = Theme.of(context);
      final l10n = PersonalizationL10n.of(context);
      return SingleChildScrollView(
        key: const Key('meaning_chips'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          spacing: 8,
          children: [
            PopupMenuButton<MessageIntent>(
              key: const Key('meaning_intent'),
              tooltip: '',
              onSelected: draft.setIntent,
              itemBuilder: (context) => [
                for (final intent in MessageIntent.values)
                  PopupMenuItem(
                    value: intent,
                    child: Row(
                      children: [
                        Icon(intentIcon(intent)),
                        const SizedBox(width: 12),
                        Text(intentLabel(l10n, intent)),
                      ],
                    ),
                  ),
              ],
              child: Chip(
                avatar: Icon(intentIcon(meaning.intent), size: 18),
                label: Text(intentLabel(l10n, meaning.intent)),
                deleteIcon: const Icon(Icons.arrow_drop_down),
                onDeleted: () {},
              ),
            ),
            FilterChip(
              key: const Key('meaning_urgent'),
              avatar: const Icon(Icons.priority_high, size: 18),
              label: Text(l10n.meaningUrgent),
              selected: meaning.urgency == MessageUrgency.high,
              showCheckmark: false,
              selectedColor: theme.colorScheme.errorContainer,
              onSelected: (selected) => draft.setUrgency(
                selected ? MessageUrgency.high : MessageUrgency.normal,
              ),
            ),
            for (final time in meaning.times)
              InputChip(
                avatar: const Icon(Icons.schedule, size: 18),
                label: Text(time.text),
                onDeleted: () => draft.removeTime(time),
              ),
            IconButton(
              key: const Key('meaning_remove'),
              tooltip: l10n.meaningRemove,
              icon: const Icon(Icons.close),
              onPressed: draft.remove,
            ),
          ],
        ),
      );
    },
  );
}
