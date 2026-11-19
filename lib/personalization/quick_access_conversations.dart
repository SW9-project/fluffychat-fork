// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

import 'simple_view_dialog.dart';
import 'simplified_interface.dart';
import 'simplified_interface_l10n.dart';

class SimpleConversationTile extends StatelessWidget {
  final QuickAccessConversation conversation;
  final bool shortcut;
  const SimpleConversationTile({
    required this.conversation,
    this.shortcut = false,
    super.key,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = SimplifiedInterfaceL10n.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: shortcut
              ? theme.colorScheme.primary.withAlpha(90)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        key: Key('simple_conversation_${conversation.id}'),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        leading:
            conversation.avatar ??
            const CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text(
          conversation.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium,
        ),
        subtitle: Text(
          conversation.unread > 0
              ? text.unread(conversation.unread)
              : text.open,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: conversation.onOpen,
      ),
    );
  }
}

class QuickAccessConversation {
  final String id;
  final String name;
  final Widget? avatar;
  final int unread;
  final VoidCallback onOpen;

  const QuickAccessConversation({
    required this.id,
    required this.name,
    required this.onOpen,
    this.avatar,
    this.unread = 0,
  });
}

/// Shortcuts supplied by the chosen manual or local-use preference.
/// No invented contacts, phone-contact permission, or message-history analysis.
class QuickAccessConversations extends StatelessWidget {
  final List<QuickAccessConversation> conversations;
  final List<String> selectedIds;
  final ValueChanged<List<String>> onSave;
  final bool automatic;

  const QuickAccessConversations({
    required this.conversations,
    required this.selectedIds,
    required this.onSave,
    this.automatic = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final text = SimplifiedInterfaceL10n.of(context);
    final theme = Theme.of(context);
    final byId = {
      for (final conversation in conversations) conversation.id: conversation,
    };
    final selected = [
      for (final id in selectedIds)
        if (byId[id] != null) byId[id]!,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                automatic ? text.frequent : text.quickAccess,
                style: theme.textTheme.titleLarge,
              ),
              TextButton.icon(
                key: const Key('quick_access_choose'),
                icon: const Icon(Icons.edit_outlined),
                label: Text(
                  selected.isEmpty ? text.choose : text.editQuickAccess,
                ),
                onPressed: conversations.isEmpty
                    ? null
                    : () async {
                        final result = await chooseSimpleConversations(
                          context,
                          conversations,
                          selected.map((entry) => entry.id).toList(),
                        );
                        if (result != null) onSave(result);
                      },
              ),
            ],
          ),
          if (selected.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(conversations.isEmpty ? text.empty : text.chooseInfo),
            ),
          for (final entry in selected)
            KeyedSubtree(
              key: Key('quick_access_${entry.id}'),
              child: SimpleConversationTile(
                conversation: entry,
                shortcut: true,
              ),
            ),
        ],
      ),
    );
  }
}

Future<List<String>?> chooseSimpleConversations(
  BuildContext context,
  List<QuickAccessConversation> conversations,
  List<String> selectedIds,
) => showSimpleViewDialog<List<String>>(
  context: context,
  builder: (_) => _QuickAccessPicker(
    conversations: conversations,
    selectedIds: selectedIds,
  ),
);

class _QuickAccessPicker extends StatefulWidget {
  final List<QuickAccessConversation> conversations;
  final List<String> selectedIds;
  const _QuickAccessPicker({
    required this.conversations,
    required this.selectedIds,
  });

  @override
  State<_QuickAccessPicker> createState() => _QuickAccessPickerState();
}

class _QuickAccessPickerState extends State<_QuickAccessPicker> {
  late final _selected = [...widget.selectedIds];
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final text = SimplifiedInterfaceL10n.of(context);
    final entries =
        widget.conversations
            .where(
              (entry) => entry.name.toLowerCase().contains(
                _query.trim().toLowerCase(),
              ),
            )
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          toolbarHeight: MediaQuery.textScalerOf(context).scale(22) * 2 + 16,
          title: Text(text.choose, maxLines: 2),
        ),
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(text.chooseInfo),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('quick_access_search'),
                      decoration: InputDecoration(
                        labelText: text.search,
                        prefixIcon: const Icon(Icons.search),
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ],
                ),
              ),
            ),
            SliverList.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final chosen = _selected.contains(entry.id);
                return CheckboxListTile(
                  key: Key('quick_access_pick_${entry.id}'),
                  title: Text(entry.name),
                  value: chosen,
                  onChanged:
                      !chosen &&
                          _selected.length >=
                              SimplifiedInterfaceController.maxQuickAccess
                      ? null
                      : (value) => setState(() {
                          if (value == true) {
                            _selected.add(entry.id);
                          } else {
                            _selected.remove(entry.id);
                          }
                        }),
                );
              },
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: const Key('quick_access_cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(text.cancel),
                ),
                FilledButton(
                  key: const Key('quick_access_save'),
                  onPressed: () => Navigator.of(context).pop([..._selected]),
                  child: Text(
                    '${text.save} (${_selected.length}/${SimplifiedInterfaceController.maxQuickAccess})',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
