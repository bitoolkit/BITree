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
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  static const _current = ValueKey('current');
  static const _threshold = 64.0;
  static const _duration = Duration(milliseconds: 320);
  static const _collapseDuration = Duration(milliseconds: 260);
  static const _historySpacing = 24.0;
  late final _scroll = _RevealScrollController(_layoutOffset);
  late final _animation = AnimationController(vsync: this)
    ..addStatusListener((_) => setState(() {}));
  double _historyHeight = 0;
  ScrollHoldController? _hold;
  bool _following = false;
  double _fromPixels = 0;
  double _fromFactor = 0;
  double _collapseTarget = 0;
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
    _releaseHold();
    _animation.dispose();
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
    if (value == _revealed || !_scroll.hasClients) return;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _releaseHold();
    _fromPixels = _scroll.offset;
    _fromFactor = _animation.value;
    _collapseTarget = math.max(0, _fromPixels - _historyHeight * _fromFactor);
    _following = true;
    _hold = _scroll.position.hold(() {
      // A new drag takes over scrolling without fighting the reveal animation.
      _following = false;
      _hold = null;
    });
    setState(() {
      _revealed = value;
      _pull = 0;
    });
    try {
      final duration = reduceMotion
          ? Duration.zero
          : value
          ? _duration
          : _collapseDuration;
      final motion = value
          ? _animation.animateTo(
              1,
              duration: duration,
              curve: Curves.easeInOutCubic,
            )
          : _animation.animateBack(
              0,
              duration: duration,
              curve: Curves.easeInOutCubic,
            );
      await motion.orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted) return;
    // Keep the last animation value in control until its layout is painted.
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && _revealed == value && !_animation.isAnimating) {
      _releaseHold();
    }
  }

  void _releaseHold() {
    final hold = _hold;
    _hold = null;
    _following = false;
    hold?.cancel();
  }

  double? _layoutOffset(double viewportHeight) {
    if (!_following) return null;
    final factor = _animation.value;
    if (!_revealed) {
      final remaining = _fromFactor == 0 ? 0 : factor / _fromFactor;
      return _collapseTarget + (_fromPixels - _collapseTarget) * remaining;
    }
    final progress = _fromFactor == 1
        ? 1.0
        : (factor - _fromFactor) / (1 - _fromFactor);
    final target = math.max(
      0.0,
      _historyHeight * factor - _historySpacing - viewportHeight,
    );
    final startTarget = math.max(
      0.0,
      _historyHeight * _fromFactor - _historySpacing - viewportHeight,
    );
    return target + (_fromPixels - startTarget) * (1 - progress);
  }

  Widget _history() => Padding(
    padding: const EdgeInsets.only(bottom: _historySpacing),
    child: Column(
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
    final items = AnimatedSliverChildren(children: widget.children);
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
                        physics: const _TopPullPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        slivers: [
                          if (_revealed || !_animation.isDismissed)
                            SliverToBoxAdapter(
                              child: SizeTransition(
                                sizeFactor: _animation,
                                alignment: Alignment.bottomCenter,
                                child: _history(),
                              ),
                            ),
                          SliverLayoutBuilder(
                            key: _current,
                            builder: (context, constraints) {
                              final factor = _animation.value;
                              // Synchronize scrolling with the laid-out history extent.
                              _historyHeight = factor == 0
                                  ? 0
                                  : constraints.precedingScrollExtent / factor;
                              return items;
                            },
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

class _RevealScrollController extends ScrollController {
  _RevealScrollController(this.offsetForLayout);

  final double? Function(double viewportHeight) offsetForLayout;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _RevealScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
    offsetForLayout: offsetForLayout,
  );
}

class _RevealScrollPosition extends ScrollPositionWithSingleContext {
  _RevealScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    required this.offsetForLayout,
  });

  final double? Function(double viewportHeight) offsetForLayout;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final target = offsetForLayout(viewportDimension);
    if (target != null && (target - pixels).abs() > 0.01) {
      // Correct before paint so the panel height and scroll offset share a frame.
      correctPixels(target);
      return false;
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }

  @override
  bool correctForNewDimensions(
    ScrollMetrics oldPosition,
    ScrollMetrics newPosition,
  ) =>
      offsetForLayout(viewportDimension) != null ||
      super.correctForNewDimensions(oldPosition, newPosition);
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
