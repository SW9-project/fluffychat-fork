// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

import 'accessibility_scope.dart';
import 'quick_access_conversations.dart';
import 'simple_view_setup.dart';
import 'simplified_interface.dart';
import 'simplified_interface_l10n.dart';

class SimplifiedInterfaceSwitch extends StatelessWidget {
  const SimplifiedInterfaceSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = SimplifiedInterfaceScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();
    final text = SimplifiedInterfaceL10n.of(context);
    final theme = Theme.of(context);
    final sizes = AccessibilityScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(text.simpleView, style: theme.textTheme.bodyMedium),
          ),
          // Only while on: changing choices must not switch the view as a side effect.
          if (controller.enabled)
            TextButton(
              key: const Key('simple_personalize'),
              style: TextButton.styleFrom(
                minimumSize: Size(sizes.touchTarget(48), sizes.buttonBox(48)),
              ),
              onPressed: () => requestSimpleViewChange(
                context,
                controller,
                true,
                personalize: true,
              ),
              child: Text(text.edit),
            ),
          Semantics(
            label: text.simpleView,
            child: Switch.adaptive(
              key: const Key('simplified_interface_switch'),
              value: controller.enabled,
              onChanged: (value) =>
                  requestSimpleViewChange(context, controller, value),
            ),
          ),
        ],
      ),
    );
  }
}

/// Safe example only: it has no rooms, message content, or send actions.
class SimplifiedInterfacePreview extends StatelessWidget {
  final bool enabled;
  final SimpleViewPreferences? preferences;
  final List<String> conversationNames;
  const SimplifiedInterfacePreview({
    required this.enabled,
    this.preferences,
    this.conversationNames = const [],
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final text = SimplifiedInterfaceL10n.of(context);
    final theme = Theme.of(context);
    final profile =
        preferences ??
        SimplifiedInterfaceScope.maybeOf(context)?.preferences ??
        const SimpleViewPreferences();
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: enabled
              ? theme.colorScheme.primary.withAlpha(12)
              : theme.colorScheme.surface,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text.sample, style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: enabled
                    ? theme.colorScheme.primary.withAlpha(18)
                    : theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    enabled ? Icons.home_rounded : Icons.chat_bubble_outline,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      enabled ? text.simpleView : text.fullView,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (enabled && profile.quickAccess != SimpleQuickAccess.none) ...[
              Text(
                profile.quickAccess == SimpleQuickAccess.frequent
                    ? text.frequent
                    : text.quickAccess,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final name in conversationNames) Chip(label: Text(name)),
                  if (conversationNames.isEmpty)
                    const CircleAvatar(child: Icon(Icons.person)),
                ],
              ),
            ] else if (!enabled)
              const Wrap(
                spacing: 8,
                children: [
                  Icon(Icons.filter_list),
                  Icon(Icons.group),
                  Icon(Icons.notifications_none),
                  Icon(Icons.more_horiz),
                ],
              ),
            const SizedBox(height: 8),
            // The clean list reuses the real home tile so the preview matches it.
            if (enabled && profile.cleanHome)
              SimpleConversationTile(
                conversation: QuickAccessConversation(
                  id: 'preview',
                  name: text.samplePerson,
                  unread: 2,
                  onOpen: () {},
                ),
              )
            else
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.person_outline),
                  ),
                  title: Text(text.samplePerson),
                  subtitle: Text(
                    text.sampleBye,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text('12:30', style: theme.textTheme.bodySmall),
                ),
              ),
            if (enabled) ...[
              const SizedBox(height: 8),
              Text(profile.cleanHome ? text.cleanHome : text.detailedHome),
              Text(text.quietChat),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    text.sampleHello,
                    style: const TextStyle(height: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withAlpha(18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    text.sampleBye,
                    style: const TextStyle(height: 1.5),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
