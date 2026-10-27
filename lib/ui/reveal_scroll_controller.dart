import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Keeps the inserted history and scroll offset in the same layout frame.
/// A user drag releases the hold and immediately regains control of scrolling.
class RevealScrollController extends ScrollController {
  RevealScrollController(this._animation, {required this.historySpacing});

  final Animation<double> _animation;
  final double historySpacing;
  ScrollHoldController? _hold;
  double _historyHeight = 0;
  double _fromPixels = 0;
  double _fromFactor = 0;
  double _collapseTarget = 0;
  bool _revealing = false;

  void beginTransition({required bool revealing}) {
    endTransition();
    _revealing = revealing;
    _fromPixels = offset;
    _fromFactor = _animation.value;
    _collapseTarget = math.max(0, _fromPixels - _historyHeight * _fromFactor);
    _hold = position.hold(() => _hold = null);
  }

  void endTransition() {
    final hold = _hold;
    _hold = null;
    hold?.cancel();
  }

  void historyLaidOut(double extent) {
    final factor = _animation.value;
    _historyHeight = factor == 0 ? 0 : extent / factor;
  }

  double? _layoutOffset(double viewportHeight) {
    if (_hold == null) return null;
    final factor = _animation.value;
    if (!_revealing) {
      final remaining = _fromFactor == 0 ? 0 : factor / _fromFactor;
      return _collapseTarget + (_fromPixels - _collapseTarget) * remaining;
    }
    final progress = _fromFactor == 1
        ? 1.0
        : (factor - _fromFactor) / (1 - _fromFactor);
    final target = math.max(
      0.0,
      _historyHeight * factor - historySpacing - viewportHeight,
    );
    final startTarget = math.max(
      0.0,
      _historyHeight * _fromFactor - historySpacing - viewportHeight,
    );
    return target + (_fromPixels - startTarget) * (1 - progress);
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _RevealScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
    offsetForLayout: _layoutOffset,
  );

  @override
  void dispose() {
    endTransition();
    super.dispose();
  }
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
class TopPullScrollPhysics extends BouncingScrollPhysics {
  const TopPullScrollPhysics({super.parent});

  @override
  TopPullScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      TopPullScrollPhysics(parent: buildParent(ancestor));

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
