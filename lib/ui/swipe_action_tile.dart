import 'dart:math' as math;

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

class _SwipeActionTileState extends State<SwipeActionTile>
    with SingleTickerProviderStateMixin {
  static const _threshold = 72.0;
  static const _settleDuration = Duration(milliseconds: 180);

  late final _offset = AnimationController.unbounded(vsync: this);
  TileSwipeAction? _activeAction;
  double _dragPosition = 0;
  bool _running = false;
  bool _thresholdFeedback = false;

  bool get _enabled => widget.enabled && !_running;
  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _start(DragStartDetails details) {
    _offset.stop();
    final distance = _offset.value.abs();
    // Invert the resistance curve so catching a returning row never jumps.
    _dragPosition =
        _offset.value.sign *
        (distance <= _threshold
            ? distance
            : _threshold * math.exp((distance - _threshold) / _threshold));
    _thresholdFeedback = false;
    _activeAction = _offset.value < 0 ? widget.leftAction : widget.rightAction;
  }

  void _drag(DragUpdateDetails details) {
    if (!_enabled) return;
    final previous = _offset.value;
    _dragPosition += details.primaryDelta!;
    if (widget.rightAction == null) {
      _dragPosition = math.min(0, _dragPosition);
    }
    final distance = _dragPosition.abs();
    // Follow the finger up to the threshold, then add resistance without a stop.
    final next =
        _dragPosition.sign *
        (distance <= _threshold
            ? distance
            : _threshold * (1 + math.log(distance / _threshold)));

    if (next.sign != previous.sign || _activeAction == null) {
      _activeAction = next < 0 ? widget.leftAction : widget.rightAction;
      _thresholdFeedback = false;
    }
    if (next.abs() < _threshold - 12) _thresholdFeedback = false;
    if (next.abs() >= _threshold && !_thresholdFeedback) {
      _thresholdFeedback = true;
      HapticFeedback.selectionClick();
    }
    _offset.value = next;
  }

  void _close() {
    _offset.animateTo(
      0,
      duration: _reduceMotion ? Duration.zero : _settleDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void _release(DragEndDetails details) {
    final reversing = details.primaryVelocity! * _offset.value.sign < -300;
    if (!_enabled || reversing || _offset.value.abs() < _threshold) {
      _close();
      return;
    }
    _invoke(_activeAction!);
  }

  Future<void> _invoke(TileSwipeAction action) async {
    setState(() => _running = true);
    final target =
        _offset.value.sign * math.max(context.size!.width, _offset.value.abs());
    try {
      await _offset
          .animateTo(
            target,
            duration: _reduceMotion ? Duration.zero : _settleDuration,
            curve: Curves.easeOutCubic,
          )
          .orCancel;
      final applied = await action.onInvoke();
      if (!mounted || applied) return;
      await _offset
          .animateTo(
            0,
            duration: _reduceMotion ? Duration.zero : _settleDuration,
            curve: Curves.easeOutCubic,
          )
          .orCancel;
    } on TickerCanceled {
      return;
    }
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onHorizontalDragStart: _enabled ? _start : null,
    onHorizontalDragUpdate: _enabled ? _drag : null,
    onHorizontalDragEnd: _enabled ? _release : null,
    onHorizontalDragCancel: _enabled ? _close : null,
    child: AnimatedBuilder(
      animation: _offset,
      child: IgnorePointer(
        ignoring: _running,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          child: widget.child,
        ),
      ),
      builder: (context, child) {
        final offset = _offset.value;
        final action = _activeAction;
        final ready = offset.abs() >= _threshold;
        return ClipRect(
          child: Stack(
            children: [
              if (offset != 0 && action != null)
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: ColoredBox(
                      color: action.background,
                      child: Align(
                        alignment: offset > 0
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        child: SizedBox(
                          width: _threshold,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                action.icon,
                                size: 22,
                                color: action.foreground,
                              ),
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    ready ? action.releaseLabel : action.label,
                                    maxLines: 1,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: action.foreground),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Transform.translate(offset: Offset(offset, 0), child: child),
            ],
          ),
        );
      },
    ),
  );
}
