import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TileSwipeAction {
  const TileSwipeAction({
    required this.label,
    required this.releaseLabel,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onInvoke,
  });

  final String label;
  final String releaseLabel;
  final IconData icon;
  final Color background;
  final Color foreground;

  /// Return true when the row is removed; false restores it after a failure.
  final Future<bool> Function() onInvoke;
}

/// Dismissible owns drag arbitration and settling; the list owns row removal.
class SwipeActionTile extends StatefulWidget {
  const SwipeActionTile({
    super.key,
    required this.leftAction,
    this.rightAction,
    required this.enabled,
    required this.child,
  });

  final TileSwipeAction leftAction;
  final TileSwipeAction? rightAction;
  final bool enabled;
  final Widget child;

  @override
  State<SwipeActionTile> createState() => _SwipeActionTileState();
}

class _SwipeActionTileState extends State<SwipeActionTile> {
  static const _threshold = 72.0;
  final _dismissKey = UniqueKey();
  bool _ready = false;
  bool _running = false;

  Future<bool> _invoke(DismissDirection direction) async {
    final action = direction == DismissDirection.endToStart
        ? widget.leftAction
        : widget.rightAction!;
    setState(() => _running = true);
    try {
      return await action.onInvoke();
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Widget _background(TileSwipeAction action, Alignment alignment) =>
      ExcludeSemantics(
        child: ColoredBox(
          color: action.background,
          child: Align(
            alignment: alignment,
            child: SizedBox(
              width: _threshold,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(action.icon, size: 22, color: action.foreground),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _ready ? action.releaseLabel : action.label,
                        maxLines: 1,
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: action.foreground),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final threshold = (_threshold / constraints.maxWidth).clamp(0.0, 1.0);
      final right = widget.rightAction;
      return AbsorbPointer(
        absorbing: _running,
        child: Dismissible(
          key: _dismissKey,
          direction: !widget.enabled && !_running
              ? DismissDirection.none
              : right == null
              ? DismissDirection.endToStart
              : DismissDirection.horizontal,
          dismissThresholds: {
            DismissDirection.startToEnd: threshold,
            DismissDirection.endToStart: threshold,
          },
          movementDuration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          resizeDuration: null,
          confirmDismiss: _invoke,
          onUpdate: (details) {
            if (_ready == details.reached) return;
            setState(() => _ready = details.reached);
            if (_ready) HapticFeedback.selectionClick();
          },
          background: _background(
            right ?? widget.leftAction,
            right == null ? Alignment.centerRight : Alignment.centerLeft,
          ),
          secondaryBackground: right == null
              ? null
              : _background(widget.leftAction, Alignment.centerRight),
          child: Material(type: MaterialType.transparency, child: widget.child),
        ),
      );
    },
  );
}
