import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../ui/design.dart';
import '../atlas.dart';
import '../place.dart';

IconData wencuiFeatureIcon(WencuiFeatureKind kind) => switch (kind) {
  WencuiFeatureKind.room => Icons.meeting_room_outlined,
  WencuiFeatureKind.stairs => Icons.stairs_outlined,
  WencuiFeatureKind.lift => Icons.elevator_outlined,
  WencuiFeatureKind.entrance => Icons.door_front_door_outlined,
  WencuiFeatureKind.restroom => Icons.wc_rounded,
};

class WencuiFloorMap extends StatefulWidget {
  const WencuiFloorMap({
    super.key,
    required this.floor,
    required this.features,
    required this.selected,
    required this.wing,
    required this.focus,
    required this.onSelected,
  });
  final int floor;
  final List<WencuiFeature> features;
  final WencuiFeature? selected;
  final WencuiWing? wing;
  final Rect? focus;
  final ValueChanged<WencuiFeature> onSelected;
  @override
  State<WencuiFloorMap> createState() => _WencuiFloorMapState();
}

class _WencuiFloorMapState extends State<WencuiFloorMap>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  Animation<Matrix4>? _matrix;
  Size? _viewport;
  (int, Rect?)? _shown;
  WencuiFeature? _hover;
  static const _imageSize = Size(1500, 1000);

  @override
  void initState() {
    super.initState();
    _animation.addListener(() => _transform.value = _matrix!.value);
  }

  @override
  void didUpdateWidget(WencuiFloorMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.floor != widget.floor) _hover = null;
  }

  @override
  void dispose() {
    _animation.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _move(Matrix4 matrix, {bool animate = true}) {
    _animation.stop();
    if (!animate || MediaQuery.disableAnimationsOf(context)) {
      _transform.value = matrix;
      return;
    }
    _matrix = Matrix4Tween(
      begin: _transform.value,
      end: matrix,
    ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(_animation);
    _animation.forward(from: 0);
  }

  void _fit({bool whole = false, bool animate = true}) {
    final viewport = _viewport!;
    final bounds = whole ? null : widget.focus;
    final rect = bounds == null
        ? Offset.zero & _imageSize
        : Rect.fromLTRB(
            bounds.left * _imageSize.width,
            bounds.top * _imageSize.height,
            bounds.right * _imageSize.width,
            bounds.bottom * _imageSize.height,
          ).inflate(52);
    final scale =
        math.min(viewport.width / rect.width, viewport.height / rect.height) *
        .93;
    _move(
      Matrix4.identity()
        ..translateByDouble(
          viewport.width / 2 - rect.center.dx * scale,
          viewport.height / 2 - rect.center.dy * scale,
          0,
          1,
        )
        ..scaleByDouble(scale, scale, scale, 1),
      animate: animate,
    );
  }

  void _zoom(double factor) {
    final center = _viewport!.center(Offset.zero);
    final scene = _transform.toScene(center);
    final scale = (_transform.value.getMaxScaleOnAxis() * factor).clamp(
      .05,
      8.0,
    );
    _move(
      Matrix4.identity()
        ..translateByDouble(
          center.dx - scene.dx * scale,
          center.dy - scene.dy * scale,
          0,
          1,
        )
        ..scaleByDouble(scale, scale, scale, 1),
    );
  }

  WencuiFeature? _featureAt(Offset position) {
    final point = Offset(
      position.dx / _imageSize.width,
      position.dy / _imageSize.height,
    );
    return widget.features
        .where((feature) => feature.path.contains(point))
        .firstOrNull;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final viewport = constraints.biggest;
      final shown = (widget.floor, widget.focus);
      if (viewport != _viewport || shown != _shown) {
        final firstLayout = _viewport == null;
        _viewport = viewport;
        _shown = shown;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fit(animate: !firstLayout);
        });
      }
      final scheme = Theme.of(context).colorScheme;
      return ClipRect(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _transform,
                constrained: false,
                minScale: .05,
                maxScale: 8,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                onInteractionStart: (_) => _animation.stop(),
                child: MouseRegion(
                  cursor: _hover == null
                      ? SystemMouseCursors.grab
                      : SystemMouseCursors.click,
                  onHover: (event) {
                    final feature = _featureAt(event.localPosition);
                    if (feature != _hover) setState(() => _hover = feature);
                  },
                  onExit: (_) => setState(() => _hover = null),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) {
                      final feature = _featureAt(details.localPosition);
                      if (feature != null) widget.onSelected(feature);
                    },
                    child: SizedBox(
                      width: _imageSize.width,
                      height: _imageSize.height,
                      child: AnimatedBuilder(
                        animation: _transform,
                        builder: (context, _) => CustomPaint(
                          foregroundPainter: _MapFeatures(
                            features: widget.features,
                            selected: widget.selected,
                            hover: _hover,
                            wing: widget.wing,
                            scale: _transform.value.getMaxScaleOnAxis(),
                            accent: scheme.primary,
                            onSelected: widget.onSelected,
                          ),
                          child: Image.asset(
                            'assets/wencui/${widget.floor}.jpg',
                            fit: BoxFit.contain,
                            width: _imageSize.width,
                            height: _imageSize.height,
                            semanticLabel: '文萃楼${widget.floor}层平面图，上东、左北',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              top: 8,
              child: Material(
                color: scheme.surfaceContainerLow,
                borderRadius: AppCorners.compact,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text('上东 · 左北'),
                ),
              ),
            ),
            if (_hover != null)
              Positioned(
                right: 12,
                top: 8,
                child: Material(
                  color: scheme.surfaceContainerLow,
                  borderRadius: AppCorners.compact,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(_hover!.title),
                  ),
                ),
              ),
            Positioned(
              right: 12,
              bottom: 12,
              child: Material(
                color: scheme.surfaceContainerLow,
                borderRadius: AppCorners.control,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '缩小地图',
                      onPressed: () => _zoom(1 / 1.5),
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    IconButton(
                      tooltip: '放大地图',
                      onPressed: () => _zoom(1.5),
                      icon: const Icon(Icons.add_rounded),
                    ),
                    IconButton(
                      tooltip: '查看整层',
                      onPressed: () => _fit(whole: true),
                      icon: const Icon(Icons.fit_screen_rounded),
                    ),
                    if (widget.focus != null)
                      IconButton(
                        tooltip: '回到选中位置',
                        onPressed: _fit,
                        icon: const Icon(Icons.my_location_rounded),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _MapFeatures extends CustomPainter {
  _MapFeatures({
    required this.features,
    required this.selected,
    required this.hover,
    required this.wing,
    required this.scale,
    required this.accent,
    required this.onSelected,
  });
  final List<WencuiFeature> features;
  final WencuiFeature? selected;
  final WencuiFeature? hover;
  final WencuiWing? wing;
  final double scale;
  final Color accent;
  final ValueChanged<WencuiFeature> onSelected;

  @override
  void paint(Canvas canvas, Size size) {
    for (final feature in features) {
      final path = feature.path.transform(
        Matrix4.diagonal3Values(size.width, size.height, 1).storage,
      );
      if (feature == selected || feature == hover) {
        canvas.drawPath(
          path,
          Paint()
            ..color = accent.withValues(alpha: feature == selected ? .25 : .12),
        );
        canvas.drawPath(
          path,
          Paint()
            ..color = accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5 / scale,
        );
      }
      if (feature.kind != WencuiFeatureKind.room &&
          feature.kind != WencuiFeatureKind.restroom &&
          (wing != null || feature.kind == WencuiFeatureKind.entrance)) {
        final point = Offset(
          feature.anchor.dx * size.width,
          feature.anchor.dy * size.height,
        );
        final radius = 10 / scale;
        canvas.drawCircle(point, radius, Paint()..color = Colors.white);
        canvas.drawCircle(
          point,
          radius,
          Paint()
            ..color = const Color(0xFFA85E3E)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 / scale,
        );
        final icon = wencuiFeatureIcon(feature.kind);
        final text = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(
              fontFamily: icon.fontFamily,
              fontSize: 14 / scale,
              color: const Color(0xFF493224),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, point - Offset(text.width / 2, text.height / 2));
        text.dispose();
      }
    }
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (size) => [
        for (final feature in features)
          CustomPainterSemantics(
            rect: Rect.fromLTRB(
              feature.bounds.left * size.width,
              feature.bounds.top * size.height,
              feature.bounds.right * size.width,
              feature.bounds.bottom * size.height,
            ),
            properties: SemanticsProperties(
              label: '${feature.title}，${feature.floor}层',
              button: true,
              selected: feature == selected,
              textDirection: TextDirection.ltr,
              onTap: () => onSelected(feature),
            ),
          ),
      ];
  @override
  bool shouldRepaint(_MapFeatures old) =>
      old.features != features ||
      old.selected != selected ||
      old.hover != hover ||
      old.wing != wing ||
      old.scale != scale ||
      old.accent != accent;
  @override
  bool shouldRebuildSemantics(_MapFeatures old) =>
      old.features != features || old.selected != selected;
}
