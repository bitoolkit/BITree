import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'animated_sliver_list.dart';

class PullToRevealList extends StatefulWidget {
  const PullToRevealList({
    super.key,
    required this.hiddenChildren,
    required this.hiddenLabel,
    required this.children,
  });

  final List<Widget> children;
  final List<Widget> hiddenChildren;
  final String hiddenLabel;

  @override
  State<PullToRevealList> createState() => _PullToRevealListState();
}

class _PullToRevealListState extends State<PullToRevealList>
    with AutomaticKeepAliveClientMixin {
  static const _current = ValueKey('current');
  static const _threshold = 64.0;
  static const _duration = Duration(milliseconds: 320);
  static const _collapseDuration = Duration(milliseconds: 260);
  final _scroll = ScrollController();
  bool _revealed = false;
  bool _dragging = false;
  double _pull = 0;

  bool get _canReveal => !_revealed && widget.hiddenChildren.isNotEmpty;

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(covariant PullToRevealList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_revealed && widget.hiddenChildren.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _setRevealed(false);
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    if (!_canReveal || notification.depth != 0) return false;
    final userDrag = switch (notification) {
      ScrollUpdateNotification(:final dragDetails) => dragDetails != null,
      OverscrollNotification(:final dragDetails) => dragDetails != null,
      _ => false,
    };
    if (userDrag) _dragging = true;
    if (!userDrag && _pull == 0) return false;

    final pull = math.max(
      0.0,
      notification.metrics.minScrollExtent - notification.metrics.pixels,
    );
    if (userDrag && pull >= _threshold && _pull < _threshold) {
      HapticFeedback.selectionClick();
    }
    if (pull != _pull) setState(() => _pull = pull);
    return false;
  }

  void _release() {
    final reveal = _dragging && _pull >= _threshold;
    _dragging = false;
    if (reveal) _setRevealed(true);
  }

  Future<void> _setRevealed(bool value) async {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (value) {
      setState(() {
        _revealed = true;
        _pull = 0;
      });
      // Lay out the history above the existing origin without moving the list.
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted || !_scroll.hasClients) return;

    // The origin separates overdue and upcoming items. One viewport of history
    // places its final item, the collapse button, at the bottom of the screen.
    final target = value ? -_scroll.position.viewportDimension : 0.0;
    if (reduceMotion) {
      _scroll.jumpTo(target);
    } else {
      await _scroll.animateTo(
        target,
        duration: value ? _duration : _collapseDuration,
        curve: Curves.easeInOutCubic,
      );
    }
    if (!mounted) return;

    // A new drag can cancel the scroll; keep history until it is offscreen.
    if (!value && _scroll.offset.abs() < 1) {
      setState(() {
        _revealed = false;
        _pull = 0;
      });
    }
  }

  Widget _history() => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      // Short histories end at the same boundary as long, scrollable histories.
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...widget.hiddenChildren,
        Center(
          child: TextButton(
            onPressed: () => _setRevealed(false),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('收回'),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    final behavior = ScrollConfiguration.of(context);
    final scrollbarGutter = switch (behavior.getPlatform(context)) {
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => 16.0,
      _ => 0.0,
    };
    return Semantics(
      customSemanticsActions: {
        if (_canReveal)
          CustomSemanticsAction(label: '查看${widget.hiddenLabel}'): () =>
              _setRevealed(true),
      },
      child: Listener(
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _dragging = false,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ScrollConfiguration(
            behavior: behavior.copyWith(
              overscroll: false,
              scrollbars: false,
              dragDevices: {...behavior.dragDevices, PointerDeviceKind.mouse},
            ),
            child: behavior.buildScrollbar(
              context,
              Padding(
                padding: EdgeInsetsDirectional.only(end: scrollbarGutter),
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomScrollView(
                        controller: _scroll,
                        center: _current,
                        physics: const _TopPullPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        slivers: [
                          if (_revealed)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: _history(),
                            ),
                          AnimatedSliverChildren(
                            key: _current,
                            children: widget.children,
                          ),
                          const SliverPadding(
                            padding: EdgeInsets.only(bottom: 24),
                          ),
                        ],
                      ),
                      if (_canReveal && _pull > 0)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: math.min(_pull, 96),
                          child: IgnorePointer(
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Transform.rotate(
                                    angle:
                                        math.pi *
                                        (_pull / _threshold).clamp(0.0, 1.0),
                                    child: Icon(
                                      Icons.expand_more_rounded,
                                      size: 20,
                                      color: scheme.error,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      '${_pull >= _threshold ? '松开查看' : '下拉查看'}'
                                      '${widget.hiddenLabel}',
                                      style: TextStyle(color: scheme.error),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              ScrollableDetails(
                direction: AxisDirection.down,
                controller: _scroll,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bounces at the top while keeping the bottom edge clamped.
class _TopPullPhysics extends BouncingScrollPhysics {
  const _TopPullPhysics({super.parent});

  @override
  _TopPullPhysics applyTo(ScrollPhysics? ancestor) =>
      _TopPullPhysics(parent: buildParent(ancestor));

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    if (value > position.pixels &&
        position.pixels >= position.maxScrollExtent) {
      return value - position.pixels;
    }
    if (value > position.maxScrollExtent &&
        position.pixels < position.maxScrollExtent) {
      return value - position.maxScrollExtent;
    }
    return 0;
  }
}
