// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../personalization_l10n.dart';
import 'meaning_chips.dart';
import 'meaning_settings.dart';
import 'message_meaning.dart';

/// Shows an incoming message's meaning around its original text, following
/// the receiver's own [MeaningSettings]: a question or request marker, an
/// urgent marker and highlighted times. The text itself is never changed.
/// Missing or invalid meaning shows the text alone.
class MeaningDecoration extends StatelessWidget {
  final Map<String, Object?> content;
  final Color textColor;
  final Widget child;

  const MeaningDecoration({
    required this.content,
    required this.textColor,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final meaning = MessageMeaning.fromContent(content);
    if (meaning == null) return child;
    return ValueListenableBuilder<MeaningPreferences>(
      valueListenable: MeaningSettings.instance,
      builder: (context, prefs, _) {
        final l10n = PersonalizationL10n.of(context);
        final theme = Theme.of(context);
        final badges = [
          if (prefs.showIntent && meaning.intent != MessageIntent.information)
            _Badge(
              key: const Key('meaning_badge_intent'),
              icon: intentIcon(meaning.intent),
              label: intentLabel(l10n, meaning.intent),
              color: theme.colorScheme.primary,
            ),
          if (prefs.showUrgency && meaning.urgency == MessageUrgency.high)
            _Badge(
              key: const Key('meaning_badge_urgent'),
              icon: Icons.priority_high,
              label: l10n.meaningUrgent,
              color: theme.colorScheme.error,
            ),
        ];
        final times = prefs.highlightTimes ? meaning.times : const [];
        if (badges.isEmpty && times.isEmpty) return child;
        return Column(
          crossAxisAlignment: .start,
          mainAxisSize: .min,
          children: [
            if (badges.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Wrap(spacing: 6, runSpacing: 4, children: badges),
              ),
            child,
            if (times.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final time in times)
                      _Badge(
                        key: const Key('meaning_time'),
                        icon: Icons.schedule,
                        label: _timeLabel(context, time),
                        color: textColor,
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  /// The words from the message, plus the worked-out date when known.
  static String _timeLabel(BuildContext context, MeaningTime time) {
    final at = time.at == null ? null : DateTime.tryParse(time.at!);
    if (at == null) return time.text;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final hasTime = time.at!.contains('T');
    final formatted = hasTime
        ? DateFormat.MMMEd(locale).add_Hm().format(at)
        : DateFormat.MMMEd(locale).format(at);
    return '${time.text} · $formatted';
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Badge({
    required this.icon,
    required this.label,
    required this.color,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withAlpha(32),
      border: Border.all(color: color.withAlpha(128)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: .min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
