// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/widgets.dart';

import 'quick_access_conversations.dart';
import 'simple_view_preview_scene.dart';

/// A local snapshot shared by onboarding from Chats and Assistant.
class SimpleViewConversations {
  final String account;
  final List<QuickAccessConversation> conversations;
  final SimpleViewPreviewScene Function(BuildContext)? createPreview;
  const SimpleViewConversations(
    this.account,
    this.conversations, {
    this.createPreview,
  });

  static SimpleViewConversations? fromContext(BuildContext context) => context
      .getInheritedWidgetOfExactType<SimpleViewConversationsScope>()
      ?.resolve();
}

class SimpleViewConversationsScope extends InheritedWidget {
  final SimpleViewConversations Function() resolve;
  const SimpleViewConversationsScope({
    super.key,
    required this.resolve,
    required super.child,
  });

  @override
  bool updateShouldNotify(SimpleViewConversationsScope oldWidget) =>
      resolve != oldWidget.resolve;
}
