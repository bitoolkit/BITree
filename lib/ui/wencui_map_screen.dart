import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../app_controller.dart';
import '../schedule/location.dart';
import '../schedule/model.dart';
import '../wencui/atlas.dart';
import '../wencui/place.dart';
import 'app_dropdown_field.dart';
import 'external_link.dart';
import 'design.dart';

class WencuiMapScreen extends StatefulWidget {
  const WencuiMapScreen({
    super.key,
    required this.controller,
    this.initialRoom = '',
  });
  final AppController controller;
  final String initialRoom;

  @override
  State<WencuiMapScreen> createState() => _WencuiMapScreenState();
}

class _WencuiMapScreenState extends State<WencuiMapScreen> {
  final _search = SearchController();
  late final _loading = WencuiAtlas.load();
  WencuiPlace? _place;
  WencuiFeature? _selected;
  int _floor = 1;
  bool _focusWing = false;

  WencuiWing? get _wing => _place?.wing ?? _selected?.wing;

  @override
  void initState() {
    super.initState();
    _place = WencuiPlace.parse(widget.initialRoom);
    _floor = _place?.floor ?? _place?.wing.firstFloor ?? 1;
    _loading.then(
      (atlas) {
        if (mounted && _place?.room != null) {
          setState(() => _selected = atlas.room(_place!.label));
        }
      },
      onError: (Object error, StackTrace stack) {
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack, library: '文萃地图'),
        );
      },
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _selectPlace(WencuiPlace place, WencuiAtlas atlas) {
    if (_search.isOpen) _search.closeView('');
    setState(() {
      _place = place;
      _selected = atlas.room(place.label);
      _floor =
          place.floor ??
          (place.wing.hasFloor(_floor) ? _floor : place.wing.firstFloor);
      _focusWing = _selected == null;
    });
  }

  void _selectFeature(WencuiFeature feature) => setState(() {
    _selected = feature;
    _place = feature.kind == WencuiFeatureKind.room
        ? WencuiPlace.parse(feature.label)
        : null;
    _floor = feature.floor;
    _focusWing = false;
  });

  List<({Course course, WencuiPlace place})> get _courses {
    final seen = <String>{};
    return [
      for (final course in widget.controller.schedule?.courses ?? <Course>[])
        if (WencuiPlace.parse(course.room, campus: course.campus)
            case final place?)
          if (seen.add('${course.name}\u0000${place.label}'))
            (course: course, place: place),
    ];
  }

  Iterable<Widget> _suggestions(WencuiAtlas atlas, SearchController search) {
    final query = normalizeCampusLocation(search.text);
    final place = WencuiPlace.parse(search.text);
    final results = <Widget>[
      if (place != null)
        ListTile(
          leading: const Icon(Icons.location_on_outlined),
          title: Text(place.label),
          subtitle: Text(
            '${place.wing.name} · ${place.floor == null ? place.wing.floorLabel : '${place.floor}层'}${place.room != null && atlas.room(place.label) == null ? ' · 查看楼栋范围' : ''}',
          ),
          onTap: () => _selectPlace(place, atlas),
        ),
      for (final (:course, :place) in _courses)
        if (query.isEmpty ||
            normalizeCampusLocation('${course.name}${course.room}')
                .contains(query))
          ListTile(
            leading: const Icon(Icons.school_outlined),
            title: Text(course.name),
            subtitle: Text('${place.label} · ${course.sectionLabel}'),
            onTap: () => _selectPlace(place, atlas),
          ),
      if (query.isNotEmpty)
        for (final feature in atlas.onFloor(_floor))
          if (feature.kind != WencuiFeatureKind.room &&
              normalizeCampusLocation('${feature.title}$_floor层')
                  .contains(query))
            ListTile(
              leading: Icon(_featureIcon(feature.kind)),
              title: Text(feature.title),
              subtitle: Text('$_floor层'),
              onTap: () {
                _search.closeView('');
                _selectFeature(feature);
              },
            ),
      for (final wing in WencuiWing.values)
        if (place?.wing != wing &&
            (query.isEmpty ||
                normalizeCampusLocation('文萃楼${wing.letter}栋').contains(query)))
          ListTile(
            leading: const Icon(Icons.apartment_rounded),
            title: Text(wing.name),
            subtitle: Text(wing.floorLabel),
            onTap: () => _selectPlace(WencuiPlace(wing), atlas),
          ),
    ];
    return results.isEmpty
        ? [
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('没有找到。试试 F704、J1006，或课表里的课程名。'),
            ),
          ]
        : results;
  }

  Widget _searchBar(bool narrow, WencuiAtlas atlas) => SearchAnchor(
    searchController: _search,
    isFullScreen: narrow,
    viewShape: narrow ? const RoundedRectangleBorder() : null,
    viewHintText: '教室号、课程名、楼梯或电梯',
    viewOnSubmitted: (query) {
      final place = WencuiPlace.parse(query);
      if (place != null) _selectPlace(place, atlas);
    },
    suggestionsBuilder: (_, search) => _suggestions(atlas, search),
    builder: (_, controller) => SearchBar(
      readOnly: true,
      hintText: '找教室，如 F704',
      onTap: controller.openView,
      leading: const Icon(Icons.search_rounded),
    ),
  );

  Widget _details(WencuiAtlas atlas) {
    final theme = Theme.of(context);
    final place = _place;
    final selected = _selected;
    final wing = _wing;
    if (place == null && selected == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('点房间查看位置，双指缩放地图', style: theme.textTheme.titleSmall),
          if (_courses.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (:course, :place) in _courses)
                  ActionChip(
                    label: Text('${course.name} · ${place.label}'),
                    onPressed: () => _selectPlace(place, atlas),
                  ),
              ],
            ),
          ],
        ],
      );
    }
    final targetFloor = selected?.floor ?? place!.floor ?? wing!.firstFloor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                selected?.title ?? place!.label,
                style: theme.textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: '清除目的地',
              onPressed: () => setState(() {
                _place = null;
                _selected = null;
                _focusWing = false;
              }),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        Text(
          '${wing == null ? '文萃楼' : '文萃楼 ${wing.name}'} · $targetFloor层',
          style: theme.textTheme.bodyMedium,
        ),
        if (place?.room != null && selected == null) ...[
          const SizedBox(height: 6),
          Text(
            '图中未找到${place!.label}的标注，已显示${wing!.name}范围。',
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            if (wing != null)
              TextButton.icon(
                onPressed: () => setState(() {
                  _focusWing = true;
                }),
                icon: const Icon(Icons.stairs_outlined, size: 18),
                label: const Text('找楼梯 / 电梯'),
              ),
            if (wing?.firstFloor == 1 && targetFloor != 1)
              TextButton.icon(
                onPressed: () => setState(() {
                  _floor = 1;
                  _focusWing = true;
                }),
                icon: const Icon(Icons.door_front_door_outlined, size: 18),
                label: const Text('一层入口'),
              ),
            if (_floor != targetFloor || _focusWing)
              TextButton.icon(
                onPressed: () => setState(() {
                  _floor = targetFloor;
                  _focusWing = false;
                }),
                icon: const Icon(Icons.my_location_rounded, size: 18),
                label: Text(
                  '回到${selected?.kind == WencuiFeatureKind.room ? '教室' : '$targetFloor层'}',
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _filters(WencuiAtlas atlas) => Row(
    children: [
      SizedBox(
        width: 80 + MediaQuery.textScalerOf(context).scale(24),
        child: AppDropdownField<int>(
          label: '楼层',
          value: _floor,
          entries: [
            for (var floor = 1; floor <= 10; floor++)
              DropdownMenuEntry(value: floor, label: '$floor层'),
          ],
          onChanged: (floor) => setState(() {
            _floor = floor;
            _focusWing = true;
          }),
        ),
      ),
      const SizedBox(width: 12),
      Flexible(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: AppDropdownField<WencuiWing?>(
            label: '楼栋',
            value: _wing,
            entries: [
              const DropdownMenuEntry(value: null, label: '全部楼栋'),
              for (final wing in WencuiWing.values)
                DropdownMenuEntry(
                  value: wing,
                  label: '${wing.name} · ${wing.floorLabel}',
                ),
            ],
            onChanged: (wing) => wing == null
                ? setState(() {
                    _place = null;
                    _selected = null;
                    _focusWing = false;
                  })
                : _selectPlace(WencuiPlace(wing), atlas),
          ),
        ),
      ),
    ],
  );

  Widget _content(WencuiAtlas atlas) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 760;
      final wing = _wing;
      final selected = _selected?.floor == _floor ? _selected : null;
      final focus = !_focusWing && selected != null
          ? selected.bounds
          : wing == null
          ? null
          : atlas.wingBounds(_floor, wing);
      final details = ListenableBuilder(
        listenable: widget.controller,
        builder: (_, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: _details(atlas),
        ),
      );
      final map = _FloorMap(
        floor: _floor,
        features: atlas.onFloor(_floor),
        selected: selected,
        wing: wing,
        focus: focus,
        onSelected: _selectFeature,
      );
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: narrow
                ? Column(
                    children: [
                      _searchBar(true, atlas),
                      const SizedBox(height: 12),
                      _filters(atlas),
                    ],
                  )
                : Row(
                    children: [
                      Flexible(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: _searchBar(false, atlas),
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(width: 336, child: _filters(atlas)),
                    ],
                  ),
          ),
          Expanded(
            child: narrow
                ? Column(
                    children: [
                      Expanded(child: map),
                      const Divider(height: 1),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: math.min(220, constraints.maxHeight * .32),
                        ),
                        child: details,
                      ),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 280, child: details),
                      const VerticalDivider(width: 1),
                      Expanded(child: map),
                    ],
                  ),
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('文萃导航'),
      actions: [
        IconButton(
          tooltip: '地图说明',
          onPressed: () => _showMapInfo(context),
          icon: const Icon(Icons.info_outline_rounded),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: SafeArea(
      child: FutureBuilder<WencuiAtlas>(
        future: _loading,
        builder: (context, snapshot) => snapshot.hasData
            ? _content(snapshot.requireData)
            : snapshot.hasError
            ? const Center(child: Text('地图加载失败，请重新打开；详细信息可在设置中导出日志。'))
            : const Center(child: CircularProgressIndicator()),
      ),
    ),
  );
}

IconData _featureIcon(WencuiFeatureKind kind) => switch (kind) {
  WencuiFeatureKind.room => Icons.meeting_room_outlined,
  WencuiFeatureKind.stairs => Icons.stairs_outlined,
  WencuiFeatureKind.lift => Icons.elevator_outlined,
  WencuiFeatureKind.entrance => Icons.door_front_door_outlined,
  WencuiFeatureKind.restroom => Icons.wc_rounded,
};

class _FloorMap extends StatefulWidget {
  const _FloorMap({
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
  State<_FloorMap> createState() => _FloorMapState();
}

class _FloorMapState extends State<_FloorMap>
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
  void didUpdateWidget(_FloorMap oldWidget) {
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
        final icon = _featureIcon(feature.kind);
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

void _showMapInfo(BuildContext context) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: const Text('地图说明'),
    scrollable: true,
    content: const Text(
      '点房间可高亮位置；楼梯、电梯和入口也可点击。双指或鼠标滚轮缩放，拖动查看附近。\n\n楼层图保留原图比例，上东、左北。1–10层图和位置索引均保存在本地，无需登录。未收录的教室号会显示对应楼栋范围。\n\n底图来自学校文萃导航的公开存档，通道开放情况以现场为准。',
    ),
    actions: [
      TextButton(
        onPressed: () => openExternalLink(
          dialogContext,
          Uri.parse(
            'https://github.com/Zebedee2021/BIT-Nav-2026/tree/main/wencui',
          ),
          failureTitle: '无法打开地图来源',
        ),
        child: const Text('地图来源'),
      ),
      TextButton(
        onPressed: () => openExternalLink(
          dialogContext,
          Uri.parse('https://wencuigis.info.bit.edu.cn/3dbuilding/#/building2'),
          failureTitle: '无法打开学校导航',
        ),
        child: const Text('学校3D导航'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text('关闭'),
      ),
    ],
  ),
);
