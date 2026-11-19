// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/events/message_reactions.dart';
import 'package:fluffychat/widgets/liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The long-press menu of a message on iOS, like in Messages: the bubble
/// lifted above the blurred chat, reactions above it and actions below it.
/// [bubbleContext] must be inside of a [RepaintBoundary] around the bubble.
void showMessageContextMenu(
  BuildContext bubbleContext,
  ChatController controller,
  Event event,
) {
  if (event.redacted) return;
  final boundary = bubbleContext
      .findAncestorRenderObjectOfType<RenderRepaintBoundary>();
  if (boundary == null || !boundary.hasSize) return;
  final rect = boundary.localToGlobal(Offset.zero) & boundary.size;
  final preview = boundary.toImageSync(
    pixelRatio: MediaQuery.devicePixelRatioOf(bubbleContext),
  );
  FocusManager.instance.primaryFocus?.unfocus();
  HapticFeedback.mediumImpact();
  Navigator.of(bubbleContext, rootNavigator: true)
      .push(
        PageRouteBuilder<void>(
          opaque: false,
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (context, animation, _) => _MessageContextMenu(
            animation: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            ),
            controller: controller,
            event: event,
            rect: rect,
            preview: preview,
          ),
        ),
      )
      .whenComplete(preview.dispose);
}

class _MenuAction {
  final String label;
  final IconData icon;
  final bool destructive;
  final FutureOr<void> Function() onTap;

  const _MenuAction(
    this.label,
    this.icon,
    this.onTap, {
    this.destructive = false,
  });
}

class _MessageContextMenu extends StatelessWidget {
  final Animation<double> animation;
  final ChatController controller;
  final Event event;
  final Rect rect;
  final ui.Image preview;

  const _MessageContextMenu({
    required this.animation,
    required this.controller,
    required this.event,
    required this.rect,
    required this.preview,
  });

  bool get _ownMessage => event.senderId == event.room.client.userID;

  /// Runs a selection action of the chat on this event, then leaves the
  /// selection empty again.
  Future<void> _run(
    BuildContext context,
    FutureOr<void> Function() action,
  ) async {
    Navigator.of(context).pop();
    controller.selectedEvents = [event];
    await action();
    if (!controller.mounted) return;
    if (controller.selectedEvents.singleOrNull == event) {
      controller.clearSelectedEvents();
    }
  }

  /// The selection getters of the chat, asked for this event alone.
  T _ask<T>(T Function() getter) {
    final selected = controller.selectedEvents;
    controller.selectedEvents = [event];
    try {
      return getter();
    } finally {
      controller.selectedEvents = selected;
    }
  }

  List<List<_MenuAction>> _actions(BuildContext context) {
    final l10n = L10n.of(context);
    final room = event.room;
    final timeline = controller.timeline;
    final sent = (timeline == null ? event : event.getDisplayEvent(timeline))
        .status
        .isSent;
    final pinned = room.pinnedEventIds.contains(event.eventId);
    return [
      [
        if (sent && room.canSendDefaultMessages)
          _MenuAction(
            l10n.reply,
            CupertinoIcons.arrowshape_turn_up_left,
            () => controller.replyAction(replyTo: event),
          ),
        if (_ask(() => controller.canEditSelectedEvents))
          _MenuAction(
            l10n.edit,
            CupertinoIcons.pencil,
            controller.editSelectedEventAction,
          ),
        _MenuAction(
          l10n.copy,
          CupertinoIcons.doc_on_doc,
          controller.copyEventsAction,
        ),
        if (_ask(() => controller.canReadAloudSelectedEvents))
          _MenuAction(
            l10n.playSelectedText,
            CupertinoIcons.speaker_2,
            controller.readAloudEventsAction,
          ),
        if (controller.activeThreadId == null && room.canSendDefaultMessages)
          _MenuAction(
            l10n.replyInThread,
            CupertinoIcons.bubble_left_bubble_right,
            () => controller.enterThread(event.eventId),
          ),
        if (_ask(() => controller.canPinSelectedEvents))
          _MenuAction(
            pinned ? l10n.unpin : l10n.pinMessage,
            pinned ? CupertinoIcons.pin_slash : CupertinoIcons.pin,
            controller.pinEvent,
          ),
        if (_ask(() => controller.canSaveSelectedEvent))
          _MenuAction(
            l10n.downloadFile,
            CupertinoIcons.square_arrow_down,
            () => controller.saveSelectedEvent(controller.context),
          ),
        if (!event.status.isError)
          _MenuAction(
            l10n.forward,
            CupertinoIcons.arrowshape_turn_up_right,
            controller.forwardEventsAction,
          ),
        _MenuAction(
          l10n.messageInfo,
          CupertinoIcons.info_circle,
          () => controller.showEventInfo(event),
        ),
      ],
      [
        if (!sent)
          _MenuAction(
            l10n.tryToSendAgain,
            CupertinoIcons.arrow_clockwise,
            controller.sendAgainAction,
          ),
        // Selects the message without the menu, to select more of them.
        _MenuAction(
          l10n.select,
          CupertinoIcons.checkmark_circle,
          () => controller.onSelectMessage(event),
        ),
      ],
      [
        if (event.status.isSent)
          _MenuAction(
            l10n.reportMessage,
            CupertinoIcons.exclamationmark_bubble,
            controller.reportEventAction,
            destructive: true,
          ),
        if (event.status.isError)
          _MenuAction(
            l10n.delete,
            CupertinoIcons.trash,
            controller.deleteErrorEventsAction,
            destructive: true,
          )
        else if (_ask(() => controller.canRedactSelectedEvents))
          _MenuAction(
            l10n.redactMessage,
            CupertinoIcons.trash,
            controller.redactEventsAction,
            destructive: true,
          ),
      ],
    ].where((group) => group.isNotEmpty).toList();
  }

  /// The user's own reaction events by their key.
  Map<String, Event> _ownReactions() {
    final timeline = controller.timeline;
    if (timeline == null) return {};
    return {
      for (final reaction in event.aggregatedEvents(
        timeline,
        RelationshipTypes.reaction,
      ))
        if (reaction.senderId == event.room.client.userID)
          ?reaction.content
                  .tryGetMap<String, Object?>('m.relates_to')
                  ?.tryGet<String>('key'):
              reaction,
    };
  }

  void _react(BuildContext context, String key) {
    Navigator.of(context).pop();
    final own = _ownReactions()[key];
    if (own != null) {
      own.redactEvent();
    } else {
      event.room.sendReaction(event.eventId, key);
    }
  }

  Future<void> _customReaction(BuildContext context) async {
    Navigator.of(context).pop();
    final key = await showCustomReactionPicker(controller.context, event.room);
    if (key == null || _ownReactions().containsKey(key)) return;
    await event.room.sendReaction(event.eventId, key);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ownReactions = _ownReactions();
    final groups = _actions(context);
    final side = _ownMessage ? 1.0 : -1.0;

    final reactions = LiquidGlass(
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.all(4),
        // Shrinks the grown buttons back when they are wider than the screen.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: .min,
            children: [
              if (event.room.canSendDefaultMessages) ...[
                for (final emoji in AppConfig.defaultReactions)
                  _ReactionButton(
                    selected: ownReactions.containsKey(emoji),
                    onTap: () => _react(context, emoji),
                    child: Text(emoji, style: const TextStyle(fontSize: 26)),
                  ),
                _ReactionButton(
                  tooltip: l10n.customReaction,
                  onTap: () => _customReaction(context),
                  child: Icon(
                    CupertinoIcons.smiley,
                    size: MediaQuery.textScalerOf(context).scale(24),
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    final menu = SizedBox(
      width: 250,
      child: LiquidGlass(
        borderRadius: BorderRadius.circular(22),
        child: Material(
          type: MaterialType.transparency,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: .min,
              children: [
                for (final (i, group) in groups.indexed) ...[
                  if (i > 0)
                    const Divider(height: 12, indent: 16, endIndent: 16),
                  for (final action in group)
                    _MenuItem(
                      action: action,
                      onTap: () => _run(context, action.onTap),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, _) => BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: 20 * animation.value,
                  sigmaY: 20 * animation.value,
                ),
                child: ColoredBox(
                  color: Colors.black.withValues(
                    alpha: (isDark ? 0.35 : 0.12) * animation.value,
                  ),
                ),
              ),
            ),
          ),
        ),
        CustomMultiChildLayout(
          delegate: _MenuLayout(
            animation: animation,
            rect: rect,
            ownMessage: _ownMessage,
            padding: MediaQuery.paddingOf(context) + const EdgeInsets.all(12),
          ),
          children: [
            if (event.room.canSendDefaultMessages)
              LayoutId(
                id: _Slot.reactions,
                child: _Reveal(
                  animation: animation,
                  alignment: Alignment(side, 1),
                  child: reactions,
                ),
              ),
            LayoutId(
              id: _Slot.bubble,
              child: RawImage(image: preview, fit: BoxFit.contain),
            ),
            LayoutId(
              id: _Slot.menu,
              child: _Reveal(
                animation: animation,
                alignment: Alignment(side, -1),
                child: menu,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Grows the reactions and the menu out of the bubble.
class _Reveal extends StatelessWidget {
  final Animation<double> animation;
  final Alignment alignment;
  final Widget child;

  const _Reveal({
    required this.animation,
    required this.alignment,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: animation,
    child: ScaleTransition(
      scale: Tween(begin: 0.6, end: 1.0).animate(animation),
      alignment: alignment,
      child: child,
    ),
  );
}

class _ReactionButton extends StatelessWidget {
  final bool selected;
  final String? tooltip;
  final VoidCallback onTap;
  final Widget child;

  const _ReactionButton({
    required this.onTap,
    required this.child,
    this.selected = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onTap,
    isSelected: selected,
    padding: EdgeInsets.zero,
    // Grows with the text size like the emoji in it.
    constraints: BoxConstraints.tight(
      Size.square(MediaQuery.textScalerOf(context).scale(44)),
    ),
    style: IconButton.styleFrom(
      backgroundColor: selected
          ? Theme.of(context).colorScheme.primary.withAlpha(60)
          : null,
    ),
    icon: Center(child: child),
  );
}

class _MenuItem extends StatelessWidget {
  final _MenuAction action;
  final VoidCallback onTap;

  const _MenuItem({required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = action.destructive
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      splashFactory: NoSplash.splashFactory,
      highlightColor: theme.colorScheme.onSurface.withAlpha(25),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Text(
                action.label,
                style: TextStyle(fontSize: 17, color: color),
              ),
            ),
            const SizedBox(width: 12),
            Icon(action.icon, size: 20, color: color),
          ],
        ),
      ),
    );
  }
}

enum _Slot { reactions, bubble, menu }

/// Puts the reactions right above the bubble and the menu right below it,
/// on the side of the bubble. Moves all of them up or down to fit on the
/// screen and shrinks bubbles that are too high.
class _MenuLayout extends MultiChildLayoutDelegate {
  final Animation<double> animation;
  final Rect rect;
  final bool ownMessage;
  final EdgeInsets padding;

  static const double gap = 8;

  _MenuLayout({
    required this.animation,
    required this.rect,
    required this.ownMessage,
    required this.padding,
  }) : super(relayout: animation);

  @override
  void performLayout(Size size) {
    final area = padding.deflateRect(Offset.zero & size);
    final loose = BoxConstraints.loose(area.size);
    final reactions = hasChild(_Slot.reactions)
        ? layoutChild(_Slot.reactions, loose)
        : Size.zero;
    // The menu gets all the room a small bubble leaves, and scrolls when
    // large text makes it taller than that.
    final menu = layoutChild(
      _Slot.menu,
      loose.copyWith(
        maxHeight: max(
          0.0,
          area.height -
              reactions.height -
              2 * gap -
              min(rect.height, area.height / 2),
        ),
      ),
    );
    final maxBubbleHeight = max(
      0.0,
      area.height - reactions.height - menu.height - 2 * gap,
    );
    final bubble = rect.size * min(1.0, maxBubbleHeight / rect.height);
    layoutChild(_Slot.bubble, BoxConstraints.tight(bubble));

    final total = reactions.height + gap + bubble.height + gap + menu.height;
    final top = (rect.top - reactions.height - gap)
        .clamp(area.top, max(area.top, area.bottom - total))
        .toDouble();
    final bubbleTop = top + reactions.height + gap;
    double left(double width) => (ownMessage ? rect.right - width : rect.left)
        .clamp(area.left, max(area.left, area.right - width));

    if (hasChild(_Slot.reactions)) {
      positionChild(_Slot.reactions, Offset(left(reactions.width), top));
    }
    positionChild(
      _Slot.bubble,
      Offset.lerp(
        rect.topLeft,
        Offset(left(bubble.width), bubbleTop),
        animation.value,
      )!,
    );
    positionChild(
      _Slot.menu,
      Offset(left(menu.width), bubbleTop + bubble.height + gap),
    );
  }

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) =>
      oldDelegate.rect != rect ||
      oldDelegate.ownMessage != ownMessage ||
      oldDelegate.padding != padding;
}
