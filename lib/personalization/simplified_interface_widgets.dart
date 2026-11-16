// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

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
    final setup = SimpleSetupL10n.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Material(
        color: controller.enabled
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: controller.enabled
                ? theme.colorScheme.primary
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (controller.enabled)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  children: [
                    Icon(
                      Icons.home_rounded,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        setup.subtitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            SwitchListTile.adaptive(
              key: const Key('simplified_interface_switch'),
              value: controller.enabled,
              title: Text(
                text.simpleView,
                style: controller.enabled
                    ? theme.textTheme.headlineSmall
                    : null,
              ),
              subtitle: Text(controller.enabled ? text.enabled : text.disabled),
              onChanged: (value) =>
                  requestSimpleViewChange(context, controller, value),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('simple_personalize'),
                onPressed: () => requestSimpleViewChange(
                  context,
                  controller,
                  true,
                  personalize: true,
                ),
                icon: const Icon(Icons.tune),
                label: Text(setup.personalize),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Safe example only: it has no rooms, message content, or send actions.
class SimplifiedInterfacePreview extends StatelessWidget {
  final bool enabled;
  final SimpleViewPreferences? preferences;
  const SimplifiedInterfacePreview({
    required this.enabled,
    this.preferences,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final text = SimplifiedInterfaceL10n.of(context);
    final theme = Theme.of(context);
    final setup = SimpleSetupL10n.of(context);
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
                    ? theme.colorScheme.primaryContainer
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
                      enabled ? setup.title : text.fullView,
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
                    ? setup.frequent
                    : text.quickAccess,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: const [
                  CircleAvatar(child: Icon(Icons.person)),
                  CircleAvatar(child: Icon(Icons.person)),
                  CircleAvatar(child: Icon(Icons.person)),
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.person_outline),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(text.samplePerson),
                          if (!enabled || !profile.cleanHome)
                            Text('...', style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    if (enabled && profile.cleanHome)
                      const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
            if (enabled) ...[
              const SizedBox(height: 8),
              Text(profile.cleanHome ? setup.cleanHome : setup.detailedHome),
              Text(profile.quietChat ? setup.quietChat : setup.familiarChat),
            ],
          ],
        ),
      ),
    );
  }
}
