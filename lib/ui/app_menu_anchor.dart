import 'package:flutter/material.dart';

typedef AppMenuAnchorBuilder = Widget Function(
  BuildContext context,
  MenuController menu,
  bool isOpen,
);

/// Uses Material's menu positioning, motion, focus and dismissal behavior.
class AppMenuAnchor extends StatefulWidget {
  const AppMenuAnchor({
    super.key,
    required this.menuChildren,
    this.controller,
    this.childFocusNode,
    this.style,
    this.onOpen,
    this.onClose,
    this.builder,
    this.child,
  });

  final List<Widget> menuChildren;
  final MenuController? controller;
  final FocusNode? childFocusNode;
  final MenuStyle? style;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;
  final AppMenuAnchorBuilder? builder;
  final Widget? child;

  @override
  State<AppMenuAnchor> createState() => _AppMenuAnchorState();
}

class _AppMenuAnchorState extends State<AppMenuAnchor> {
  AnimationStatus _status = AnimationStatus.dismissed;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    widthFactor: 1,
    heightFactor: 1,
    child: MenuAnchor(
      controller: widget.controller,
      childFocusNode: widget.childFocusNode,
      style: (widget.style ?? const MenuStyle()).copyWith(
        alignment: widget.style?.alignment ?? AlignmentDirectional.bottomStart,
      ),
      crossAxisUnconstrained: false,
      animated: !MediaQuery.disableAnimationsOf(context),
      consumeOutsideTap: true,
      useRootOverlay: true,
      onOpen: widget.onOpen,
      onClose: widget.onClose,
      onAnimationStatusChanged: (status) => setState(() => _status = status),
      menuChildren: widget.menuChildren,
      builder: (context, menu, child) =>
          widget.builder?.call(context, menu, _status.isForwardOrCompleted) ??
          child ??
          const SizedBox.shrink(),
      child: widget.child,
    ),
  );
}
