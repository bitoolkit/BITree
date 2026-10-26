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
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  static const _threshold = 64.0;
  static const _duration = Duration(milliseconds: 320);
  static const _collapseDuration = Duration(milliseconds: 260);
  final _scroll = ScrollController();
  late final _reveal =
      AnimationController(
        vsync: this,
        duration: _duration,
        reverseDuration: _collapseDuration,
      )..addStatusListener((status) {
        if (status == AnimationStatus.dismissed) setState(() {});
      });
  late final _expansion = CurvedAnimation(
    parent: _reveal,
    curve: Curves.easeInOutCubic,
  );
  bool _revealed = false;
  bool _dragging = false;
  double _pull = 0;

  bool get _canReveal => !_revealed && widget.hiddenChildren.isNotEmpty;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _expansion.dispose();
    _reveal.dispose();
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
    if (!value && !reduceMotion && _scroll.hasClients && _scroll.offset > 0) {
      // Bring the collapsing content into view before changing its height.
      await _scroll.animateTo(
        0,
        duration: _collapseDuration,
        curve: Curves.easeOutCubic,
      );
      if (!mounted) return;
      // A new drag takes precedence over the collapse request.
      if (_scroll.offset > 1) return;
    }

    setState(() {
      _revealed = value;
      _pull = 0;
    });
    if (reduceMotion) {
      _reveal.value = value ? 1 : 0;
    } else if (value) {
      _reveal.forward();
    } else {
      _reveal.reverse();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (reduceMotion) {
        _scroll.jumpTo(0);
      } else {
        _scroll.animateTo(0, duration: _duration, curve: Curves.easeOutCubic);
      }
    });
  }

  Widget _revealedList() => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      // The footer uses spare space; tall lists keep their natural height.
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizeTransition(
              sizeFactor: _expansion,
              alignment: Alignment.topCenter,
              child: FadeTransition(
                opacity: _expansion,
                child: AnimatedBuilder(
                  animation: _expansion,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(0, -32 * (1 - _expansion.value)),
                    child: child,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: widget.hiddenChildren,
                  ),
                ),
              ),
            ),
            ...widget.children,
          ],
        ),
        SizeTransition(
          sizeFactor: _expansion,
          alignment: Alignment.bottomCenter,
          child: FadeTransition(
            opacity: _expansion,
            child: Center(
              child: TextButton(
                onPressed: () => _setRevealed(false),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('收回'),
              ),
            ),
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
                        physics: _canReveal
                            ? const _TopPullPhysics(
                                parent: AlwaysScrollableScrollPhysics(),
                              )
                            : const ClampingScrollPhysics(),
                        slivers: [
                          if ((_revealed || !_reveal.isDismissed) &&
                              widget.hiddenChildren.isNotEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: _revealedList(),
                            )
                          else ...[
                            AnimatedSliverChildren(
                              key: const ValueKey('current'),
                              children: widget.children,
                            ),
                            const SliverPadding(
                              padding: EdgeInsets.only(bottom: 24),
                            ),
                          ],
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

/// Bounces only at the top while the extra items are hidden.
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
