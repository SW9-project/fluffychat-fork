// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

import 'interaction_signal.dart';

export 'interaction_signal.dart' show TargetKind;

/// Disabled for now (Phase 3b): targets still register, but nothing reads
/// them because interaction signals are not collected.
///
/// Marks a widget as a target for interaction signals. Its on-screen
/// rectangle is read only when a tap happens, so it costs nothing per frame.
class TrackedTarget extends StatefulWidget {
  final String id;
  final TargetKind kind;
  final Widget child;

  const TrackedTarget({
    required this.id,
    required this.kind,
    required this.child,
    super.key,
  });

  /// A target that covers its parent [Stack] without wrapping anything, so it
  /// can be added to existing layouts as one line.
  static Widget fill({required String id, required TargetKind kind}) =>
      Positioned.fill(
        child: IgnorePointer(
          child: TrackedTarget(id: id, kind: kind, child: const SizedBox()),
        ),
      );

  /// Snapshots of all targets on the current route.
  static List<TargetSnapshot> snapshot() => [
    for (final state in _TrackedTargetState._mounted) ?state._snapshot(),
  ];

  @override
  State<TrackedTarget> createState() => _TrackedTargetState();
}

class _TrackedTargetState extends State<TrackedTarget> {
  static final Set<_TrackedTargetState> _mounted = {};

  ModalRoute<Object?>? _route;

  @override
  void initState() {
    super.initState();
    _mounted.add(this);
  }

  @override
  void dispose() {
    _mounted.remove(this);
    super.dispose();
  }

  TargetSnapshot? _snapshot() {
    // Targets on routes below the current one are covered and not tappable.
    if (_route != null && !_route!.isCurrent) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    return TargetSnapshot(widget.id, widget.kind, rect);
  }

  @override
  Widget build(BuildContext context) {
    _route = ModalRoute.of(context);
    return widget.child;
  }
}
