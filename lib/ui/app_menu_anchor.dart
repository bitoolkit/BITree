import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef AppMenuAnchorBuilder = Widget Function(
  BuildContext context,
  MenuController menu,
  bool isOpen,
);

/// Material menu items and lifecycle with a panel that closes fully to zero.
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

class _AppMenuAnchorState extends State<AppMenuAnchor>
    with SingleTickerProviderStateMixin {
  final _internalController = MenuController();
  final _focus = FocusScopeNode(
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    directionalTraversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
    reverseDuration: const Duration(milliseconds: 150),
  )..addStatusListener((_) => setState(() {}));
  // Flutter's MenuAnchor reverse curve ends at 0.35, then jumps to zero.
  // Keep the Material easing, but let it cover the entire panel height.
  late final _height = CurvedAnimation(
    parent: _animation,
    curve: const Cubic(.3, 0, 0, 1),
    reverseCurve: Easing.emphasizedAccelerate.flipped,
  );
  late final _opacity = CurvedAnimation(
    parent: _animation,
    curve: const Interval(0, .1),
    reverseCurve: const Interval(2 / 3, 1).flipped,
  );

  MenuController get _menu => widget.controller ?? _internalController;
  bool get _isOpen => _animation.isForwardOrCompleted;

  @override
  void dispose() {
    _height.dispose();
    _opacity.dispose();
    _animation.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _open(Offset? position, VoidCallback showOverlay) {
    if (!_menu.isOpen) showOverlay();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.value = 1;
    } else {
      _animation.forward();
    }
  }

  void _close(VoidCallback hideOverlay) {
    if (!_isOpen) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.value = 0;
      hideOverlay();
    } else {
      _animation.reverse().then((_) => hideOverlay());
    }
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    widthFactor: 1,
    heightFactor: 1,
    child: RawMenuAnchor(
      controller: _menu,
      childFocusNode: widget.childFocusNode,
      consumeOutsideTaps: true,
      useRootOverlay: true,
      onOpen: widget.onOpen,
      onClose: widget.onClose,
      onOpenRequested: _open,
      onCloseRequested: _close,
      overlayBuilder: _buildOverlay,
      builder: (context, menu, child) =>
          widget.builder?.call(context, menu, _isOpen) ??
          child ??
          const SizedBox.shrink(),
      child: widget.child,
    ),
  );

  Widget _buildOverlay(BuildContext context, RawMenuOverlayInfo info) {
    final theme = Theme.of(context);
    final style = (widget.style ?? const MenuStyle()).merge(
      MenuTheme.of(context).style,
    );
    final minimum = style.minimumSize?.resolve({}) ?? Size.zero;
    final fixed = style.fixedSize?.resolve({});
    final width = fixed?.width;
    final shape =
        style.shape?.resolve({}) ??
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        );

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => CustomSingleChildLayout(
        delegate: _MenuLayout(
          anchor: info.anchorRect,
          position: info.position,
          alignment: (style.alignment ?? AlignmentDirectional.bottomStart)
              .resolve(Directionality.of(context)),
          insets:
              MediaQuery.paddingOf(context) + MediaQuery.viewInsetsOf(context),
          heightFactor: _height.value,
        ),
        child: ExcludeSemantics(
          excluding: !_isOpen,
          child: IgnorePointer(
            ignoring: !_isOpen,
            child: ExcludeFocus(
              excluding: !_isOpen,
              child: TapRegion(
                groupId: info.tapRegionGroupId,
                consumeOutsideTaps: true,
                onTapOutside: (_) => _menu.close(),
                child: FadeTransition(
                  opacity: _opacity,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: width?.isFinite == true
                          ? width!
                          : minimum.width,
                      maxWidth: width?.isFinite == true
                          ? width!
                          : double.infinity,
                    ),
                    child: IntrinsicWidth(
                      child: Material(
                        color:
                            style.backgroundColor?.resolve({}) ??
                            theme.colorScheme.surfaceContainer,
                        surfaceTintColor: Colors.transparent,
                        elevation: style.elevation?.resolve({}) ?? 3,
                        shape: shape,
                        clipBehavior: Clip.antiAlias,
                        child: Align(
                          alignment: AlignmentDirectional.topStart,
                          widthFactor: 1,
                          heightFactor: _height.value,
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      child: FocusScope(
        node: _focus,
        autofocus: true,
        skipTraversal: true,
        child: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.arrowDown):
                DirectionalFocusIntent(TraversalDirection.down),
            SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
              TraversalDirection.up,
            ),
            SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
          },
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: false,
              overscroll: false,
              physics: const ClampingScrollPhysics(),
            ),
            child: SingleChildScrollView(
              primary: false,
              padding:
                  style.padding?.resolve({}) ??
                  const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.menuChildren,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuLayout extends SingleChildLayoutDelegate {
  const _MenuLayout({
    required this.anchor,
    required this.position,
    required this.alignment,
    required this.insets,
    required this.heightFactor,
  });

  final Rect anchor;
  final Offset? position;
  final Alignment alignment;
  final EdgeInsets insets;
  final double heightFactor;

  Offset get _target => position == null
      ? Offset(alignment.withinRect(anchor).dx, anchor.center.dy)
      : anchor.topLeft + position!;
  double get _verticalOffset => position == null ? anchor.height / 2 : 0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final available = insets
        .deflateRect(Offset.zero & constraints.biggest)
        .deflate(8);
    final height = math
        .max(
          _target.dy - _verticalOffset - available.top,
          available.bottom - _target.dy - _verticalOffset,
        )
        .clamp(0.0, available.height);
    return BoxConstraints(maxWidth: available.width, maxHeight: height);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final available = insets.deflateRect(Offset.zero & size);
    final fullHeight = heightFactor == 0
        ? 0.0
        : childSize.height / heightFactor;
    final fullSize = Size(childSize.width, fullHeight);
    final offset =
        positionDependentBox(
          size: available.size,
          childSize: fullSize,
          target: _target - available.topLeft,
          verticalOffset: _verticalOffset,
          preferBelow: true,
          margin: 8,
        ) +
        available.topLeft;
    final above = offset.dy + fullHeight <= _target.dy;
    return Offset(
      _target.dx.clamp(
        available.left + 8,
        math.max(available.left + 8, available.right - childSize.width - 8),
      ),
      above ? offset.dy + fullHeight - childSize.height : offset.dy,
    );
  }

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      position != oldDelegate.position ||
      alignment != oldDelegate.alignment ||
      insets != oldDelegate.insets ||
      heightFactor != oldDelegate.heightFactor;
}

/// RawMenuAnchor has no Material scope to close when an item is selected.
class AppMenuItemButton extends StatelessWidget {
  const AppMenuItemButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.leadingIcon,
    this.trailingIcon,
    this.style,
    this.autofocus = false,
    this.overflowAxis = Axis.vertical,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final Widget? leadingIcon;
  final Widget? trailingIcon;
  final ButtonStyle? style;
  final bool autofocus;
  final Axis overflowAxis;

  @override
  Widget build(BuildContext context) => MenuItemButton(
    closeOnActivate: false,
    onPressed: onPressed == null
        ? null
        : () {
            MenuController.maybeOf(context)!.close();
            onPressed!();
          },
    leadingIcon: leadingIcon,
    trailingIcon: trailingIcon,
    style: style,
    autofocus: autofocus,
    overflowAxis: overflowAxis,
    child: child,
  );
}
