import 'package:flutter/material.dart';

/// Reconciles keyed rows while Flutter animates their insertion and removal.
class AnimatedSliverChildren extends StatefulWidget {
  const AnimatedSliverChildren({super.key, required this.children});

  final List<Widget> children;

  @override
  State<AnimatedSliverChildren> createState() => _AnimatedSliverChildrenState();
}

class _AnimatedSliverChildrenState extends State<AnimatedSliverChildren> {
  final _list = GlobalKey<SliverAnimatedListState>();
  late final _children = widget.children.map(_AnimatedRow.new).toList();

  Duration get _duration => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 220);

  void _remove(int index) {
    final child = _children.removeAt(index);
    _list.currentState!.removeItem(
      index,
      (context, animation) => _transition(child, animation, removing: true),
      duration: _duration,
    );
  }

  @override
  void didUpdateWidget(covariant AnimatedSliverChildren oldWidget) {
    super.didUpdateWidget(oldWidget);
    final keys = widget.children.map((child) => child.key).toSet();
    assert(!keys.contains(null) && keys.length == widget.children.length);
    for (var index = _children.length - 1; index >= 0; index--) {
      if (!keys.contains(_children[index].child.key)) _remove(index);
    }

    for (var index = 0; index < widget.children.length; index++) {
      final child = widget.children[index];
      if (index < _children.length && _children[index].child.key == child.key) {
        _children[index].child = child;
        continue;
      }
      final previous = _children.indexWhere(
        (row) => row.child.key == child.key,
      );
      if (previous != -1) _remove(previous);
      _children.insert(index, _AnimatedRow(child));
      _list.currentState!.insertItem(index, duration: _duration);
    }
  }

  Widget _transition(
    _AnimatedRow row,
    Animation<double> animation, {
    bool removing = false,
  }) {
    final progress = animation.drive(CurveTween(curve: Curves.easeInOutCubic));
    return KeyedSubtree(
      key: row.key,
      child: SizeTransition(
        sizeFactor: progress,
        alignment: Alignment.topCenter,
        child: FadeTransition(
          opacity: progress,
          child: ExcludeSemantics(
            excluding: removing,
            child: IgnorePointer(ignoring: removing, child: row.child),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SliverAnimatedList(
    key: _list,
    initialItemCount: _children.length,
    findChildIndexCallback: (key) {
      final index = _children.indexWhere((child) => child.key == key);
      return index == -1 ? null : index;
    },
    itemBuilder: (context, index, animation) =>
        _transition(_children[index], animation),
  );
}

class _AnimatedRow {
  _AnimatedRow(this.child);

  // Preserve row state through removal; a restored row gets its own identity.
  final key = GlobalKey();
  Widget child;
}
