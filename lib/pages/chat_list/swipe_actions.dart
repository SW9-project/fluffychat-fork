// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:material_ui/material_ui.dart';

class SwipeAction {
  final String label;
  final IconData icon;
  final Color color;
  final void Function() onPressed;

  const SwipeAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });
}

/// The swipe actions of iOS lists: swiping a row to the end reveals the
/// [leading] actions, swiping it to the start the [trailing] ones.
// shortcut: no full swipe to run the outermost action, add it if missed.
class SwipeActions extends StatefulWidget {
  final List<SwipeAction> leading;
  final List<SwipeAction> trailing;
  final Widget child;

  static const double actionWidth = 74;

  const SwipeActions({
    required this.child,
    this.leading = const [],
    this.trailing = const [],
    super.key,
  });

  @override
  State<SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<SwipeActions>
    with SingleTickerProviderStateMixin {
  // Like in UIKit only one row is open at a time.
  static _SwipeActionsState? _openRow;

  /// Positive while the leading actions are revealed.
  late final AnimationController _offset = AnimationController.unbounded(
    vsync: this,
  );
  ScrollPosition? _scrollPosition;

  double get _direction =>
      Directionality.of(context) == TextDirection.ltr ? 1 : -1;
  double get _maxLeading => widget.leading.length * SwipeActions.actionWidth;
  double get _maxTrailing => widget.trailing.length * SwipeActions.actionWidth;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Scrolling the list closes the row.
    _scrollPosition?.isScrollingNotifier.removeListener(_close);
    _scrollPosition = Scrollable.maybeOf(context)?.position;
    _scrollPosition?.isScrollingNotifier.addListener(_close);
  }

  @override
  void dispose() {
    _scrollPosition?.isScrollingNotifier.removeListener(_close);
    if (_openRow == this) _openRow = null;
    _offset.dispose();
    super.dispose();
  }

  void _close() {
    if (_offset.value != 0) _animateTo(0);
  }

  void _animateTo(double target) {
    if (target == 0) {
      if (_openRow == this) _openRow = null;
    } else {
      if (_openRow != this) _openRow?._close();
      _openRow = this;
    }
    _offset.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  void _onDragStart(DragStartDetails _) {
    if (_openRow != this) _openRow?._close();
    _offset.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _offset.value = (_offset.value + details.primaryDelta! * _direction).clamp(
      -_maxTrailing,
      _maxLeading,
    );
  }

  void _onDragEnd([_]) {
    final value = _offset.value;
    _animateTo(
      value > _maxLeading / 2
          ? _maxLeading
          : value < -_maxTrailing / 2
          ? -_maxTrailing
          : 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.leading.isEmpty && widget.trailing.isEmpty) return widget.child;
    return Semantics(
      // VoiceOver offers the actions in its actions rotor.
      customSemanticsActions: {
        for (final action in [...widget.leading, ...widget.trailing])
          CustomSemanticsAction(label: action.label): action.onPressed,
      },
      child: GestureDetector(
        supportedDevices: const {PointerDeviceKind.touch},
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onHorizontalDragCancel: _onDragEnd,
        child: AnimatedBuilder(
          animation: _offset,
          child: widget.child,
          builder: (context, child) {
            final value = _offset.value;
            final open = value != 0;
            return Stack(
              children: [
                if (open)
                  Positioned.fill(
                    child: Align(
                      alignment: value > 0
                          ? AlignmentDirectional.centerStart
                          : AlignmentDirectional.centerEnd,
                      child: SizedBox(
                        width: value.abs(),
                        height: double.infinity,
                        child: Row(
                          crossAxisAlignment: .stretch,
                          children: [
                            for (final action
                                in value > 0 ? widget.leading : widget.trailing)
                              Expanded(
                                child: _SwipeActionButton(
                                  action: action,
                                  onPressed: () {
                                    _close();
                                    action.onPressed();
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Transform.translate(
                  offset: Offset(value * _direction, 0),
                  // While open, a tap on the row closes it.
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: open ? _close : null,
                    child: IgnorePointer(ignoring: open, child: child),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SwipeActionButton extends StatelessWidget {
  final SwipeAction action;
  final void Function() onPressed;

  const _SwipeActionButton({required this.action, required this.onPressed});

  @override
  Widget build(BuildContext context) => Material(
    color: action.color,
    child: InkWell(
      onTap: onPressed,
      // The content keeps its size while the row opens and is clipped.
      child: ClipRect(
        child: OverflowBox(
          minWidth: SwipeActions.actionWidth,
          maxWidth: SwipeActions.actionWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              mainAxisAlignment: .center,
              children: [
                Icon(action.icon, color: Colors.white, size: 22),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    action.label,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
