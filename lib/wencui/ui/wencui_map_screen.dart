import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../schedule/location.dart';
import '../../schedule/model.dart';
import '../../ui/app_menu_anchor.dart';
import '../../ui/design.dart';
import '../../ui/external_link.dart';
import '../atlas.dart';
import '../place.dart';
import 'floor_map.dart';

class WencuiMapScreen extends StatefulWidget {
  const WencuiMapScreen({
    super.key,
    required this.controller,
    this.initialRoom = '',
    this.initialCourse,
    this.initialOverview = false,
  });
  final AppController controller;
  final String initialRoom;
  final Course? initialCourse;
  final bool initialOverview;

  @override
  State<WencuiMapScreen> createState() => _WencuiMapScreenState();
}

void _showMapInfo(BuildContext context) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: const Text('地图说明'),
    scrollable: true,
    content: const Text(
      '点楼栋放大，再点房间查看位置。双指、鼠标滚轮或加减按钮可缩放地图。\n\n楼层图上东、左北，保持原图比例。1–10层图和位置索引保存在本地，无需登录。未收录的教室号只定位到楼栋。\n\n底图来自学校文萃导航的公开存档，通道开放情况以现场为准。',
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

class _WencuiMapScreenState extends State<WencuiMapScreen> {
  final _search = SearchController();
  final _camera = WencuiMapController();
  final _floorMenu = MenuController();
  final _facilities = <WencuiFeatureKind>{};
  late final _loading = WencuiAtlas.load();
  WencuiPlace? _place;
  WencuiFeature? _selected;
  Course? _course;
  int _floor = 1;

  WencuiWing? get _wing => _selected?.wing ?? _place?.wing;

  @override
  void initState() {
    super.initState();
    _course = widget.initialCourse;
    _place = WencuiPlace.parse(_course?.room ?? widget.initialRoom);
    _floor = _place?.floor ?? _place?.wing.firstFloor ?? 1;
    _loading.then(
      (atlas) {
        if (!mounted) return;
        setState(() => _selected = atlas.room(_place?.label ?? ''));
        if (!widget.initialOverview) {
          _camera.show(
            _selected?.bounds ??
                (_place == null ? null : atlas.wingBounds(_floor, _place!.wing)),
          );
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
    _camera.dispose();
    super.dispose();
  }

  List<({Course course, WencuiPlace place})> get _courses {
    final seen = <String>{};
    return [
      for (final course
          in widget.controller.timetable.schedule?.courses ?? <Course>[])
        if (WencuiPlace.parse(course.room, campus: course.campus)
            case final place?)
          if (seen.add('${course.name}\u0000${place.label}'))
            (course: course, place: place),
    ]..sort((a, b) {
      final day = (a.course.weekday ?? 8).compareTo(b.course.weekday ?? 8);
      return day != 0
          ? day
          : (a.course.startSection ?? 14).compareTo(
              b.course.startSection ?? 14,
            );
    });
  }

  void _selectPlace(WencuiPlace place, WencuiAtlas atlas, {Course? course}) {
    if (_search.isOpen) _search.closeView('');
    setState(() {
      _place = place;
      _course = course;
      _selected = atlas.room(place.label);
      _floor =
          place.floor ??
          (place.wing.hasFloor(_floor) ? _floor : place.wing.firstFloor);
      _facilities.clear();
    });
    _camera.show(_selected?.bounds ?? atlas.wingBounds(_floor, place.wing));
  }

  void _selectFeature(WencuiFeature feature) => setState(() {
    _selected = feature;
    _floor = feature.floor;
    if (feature.kind == WencuiFeatureKind.room) {
      _place = WencuiPlace.parse(feature.label);
      _course = _courses
          .where((item) => item.place.label == feature.label)
          .firstOrNull
          ?.course;
    }
    // A map tap selects without moving the camera. Inspecting facilities keeps
    // the destination so the user can return directly to the classroom.
  });

  void _changeFloor(int floor, WencuiAtlas atlas) {
    final wing = _wing;
    setState(() {
      _floor = floor;
      _selected = _place?.floor == floor ? atlas.room(_place!.label) : null;
    });
    _camera.show(wing == null ? null : atlas.wingBounds(floor, wing));
  }

  void _returnToRoom(WencuiAtlas atlas) {
    final place = _place!;
    setState(() {
      _floor = place.floor ?? place.wing.firstFloor;
      _selected = atlas.room(place.label);
    });
    _camera.show(_selected?.bounds ?? atlas.wingBounds(_floor, place.wing));
  }

  void _toggleFacility(WencuiFeatureKind kind, WencuiAtlas atlas) {
    final enabled = !_facilities.contains(kind);
    setState(() {
      if (enabled) {
        _facilities.add(kind);
      } else {
        _facilities.remove(kind);
        if (_selected?.kind == kind) _selected = null;
      }
    });
    if (enabled) {
      _camera.show(_wing == null ? null : atlas.wingBounds(_floor, _wing!));
    }
  }

  void _showCourses(WencuiAtlas atlas) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * .7,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          children: [
            ListTile(
              title: Text(
                '我的文萃课程',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              trailing: IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.pop(sheetContext),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            for (final (:course, :place) in _courses)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer,
                  child: Text(place.wing.letter),
                ),
                title: Text(course.name),
                subtitle: Text(
                  '${place.label} · ${course.weekday == null ? '' : '${weekdays[course.weekday! - 1]} '}${course.sectionLabel}',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _selectPlace(place, atlas, course: course);
                },
              ),
          ],
        ),
      ),
    ),
  );

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
            onTap: () => _selectPlace(place, atlas, course: course),
          ),
      if (query.isNotEmpty)
        for (final feature in atlas.onFloor(_floor))
          if (feature.kind != WencuiFeatureKind.room &&
              normalizeCampusLocation('${feature.title}$_floor层')
                  .contains(query))
            ListTile(
              leading: Icon(wencuiFeatureIcon(feature.kind)),
              title: Text(feature.title),
              subtitle: Text('$_floor层'),
              onTap: () {
                _search.closeView('');
                _facilities.add(feature.kind);
                _selectFeature(feature);
                _camera.show(feature.bounds);
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
      hintText: '教室号或课程名，如 F704',
      onTap: controller.openView,
      leading: const Icon(Icons.search_rounded),
      trailing: [
        if (_courses.isNotEmpty)
          IconButton(
            tooltip: '我的文萃课程',
            onPressed: () => _showCourses(atlas),
            icon: const Icon(Icons.school_outlined),
          ),
      ],
    ),
  );

  Widget _floorControl(WencuiAtlas atlas) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    elevation: 1,
    borderRadius: AppCorners.control,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '上一层',
          onPressed: _floor == 10
              ? null
              : () => _changeFloor(_floor + 1, atlas),
          icon: const Icon(Icons.keyboard_arrow_up_rounded),
        ),
        AppMenuAnchor(
          controller: _floorMenu,
          menuChildren: [
            SizedBox(
              width: 240,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var row = 0; row < 2; row++)
                    Row(
                      children: [
                        for (var column = 1; column <= 5; column++)
                          Expanded(
                            child: TextButton(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                backgroundColor: row * 5 + column == _floor
                                    ? Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                    : null,
                              ),
                              onPressed: () {
                                _floorMenu.close();
                                _changeFloor(row * 5 + column, atlas);
                              },
                              child: Text('${row * 5 + column}'),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
          builder: (context, menu, isOpen) => TextButton(
            onPressed: () => isOpen ? menu.close() : menu.open(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text('$_floor层', semanticsLabel: '选择楼层，当前$_floor层'),
          ),
        ),
        IconButton(
          tooltip: '下一层',
          onPressed: _floor == 1 ? null : () => _changeFloor(_floor - 1, atlas),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
        ),
      ],
    ),
  );

  Widget _details(WencuiAtlas atlas) {
    final theme = Theme.of(context);
    final place = _place;
    final selected = _selected;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place?.label ?? selected?.title ?? '点楼栋放大，或搜索教室号',
                    style: theme.textTheme.titleLarge,
                  ),
                  if (_course != null) ...[
                    const SizedBox(height: 3),
                    Text(_course!.name, style: theme.textTheme.bodyMedium),
                  ],
                  if (place != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      '文萃楼 ${place.wing.name} · ${place.floor == null ? place.wing.floorLabel : '${place.floor}层'}${_floor != place.floor && place.floor != null ? '，正在查看$_floor层' : ''}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            if (place != null || selected != null)
              IconButton(
                tooltip: '清除目的地',
                onPressed: () {
                  setState(() {
                    _place = null;
                    _selected = null;
                    _course = null;
                    _facilities.clear();
                  });
                  _camera.show(null);
                },
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
        if (place?.room != null && atlas.room(place!.label) == null) ...[
          const SizedBox(height: 6),
          Text(
            '图中未找到${place.label}的标注，已显示${place.wing.name}范围。',
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (selected != null && selected.kind != WencuiFeatureKind.room) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(wencuiFeatureIcon(selected.kind), size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '已选：${selected.title}',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final (kind, label) in [
              (WencuiFeatureKind.stairs, '楼梯'),
              (WencuiFeatureKind.lift, '电梯'),
              (WencuiFeatureKind.restroom, '卫生间'),
            ])
              FilterChip(
                shape: appControlShape,
                avatar: Icon(wencuiFeatureIcon(kind), size: 18),
                label: Text(label),
                selected: _facilities.contains(kind),
                showCheckmark: false,
                onSelected: (_) => _toggleFacility(kind, atlas),
              ),
            if (place?.wing.firstFloor == 1)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _floor = 1;
                    _selected = null;
                    _facilities.add(WencuiFeatureKind.entrance);
                  });
                  _camera.show(atlas.wingBounds(1, place!.wing));
                },
                icon: const Icon(Icons.door_front_door_outlined, size: 18),
                label: const Text('一层入口'),
              ),
            if (place != null)
              TextButton.icon(
                onPressed: () => _returnToRoom(atlas),
                icon: const Icon(Icons.my_location_rounded, size: 18),
                label: Text(place.room == null ? '回到楼栋' : '回到教室'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _content(WencuiAtlas atlas) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 760;
      final details = Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: _details(atlas),
        ),
      );
      final map = Stack(
        children: [
          Positioned.fill(
            child: WencuiFloorMap(
              floor: _floor,
              atlas: atlas,
              controller: _camera,
              selected: _selected?.floor == _floor ? _selected : null,
              wing: _wing,
              facilities: Set.of(_facilities),
              onSelected: _selectFeature,
              onWingSelected: (wing) => _selectPlace(WencuiPlace(wing), atlas),
            ),
          ),
          Positioned(right: 12, top: 8, child: _floorControl(atlas)),
        ],
      );
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: _searchBar(narrow, atlas),
          ),
          Expanded(
            child: narrow
                ? Column(
                    children: [
                      Expanded(child: map),
                      const Divider(height: 1),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: math.min(250, constraints.maxHeight * .34),
                        ),
                        child: details,
                      ),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 300, child: details),
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
      child: ListenableBuilder(
        listenable: widget.controller.timetable,
        builder: (_, _) => FutureBuilder<WencuiAtlas>(
          future: _loading,
          builder: (context, snapshot) => snapshot.hasData
              ? _content(snapshot.requireData)
              : snapshot.hasError
              ? const Center(child: Text('地图加载失败，请重新打开；详细信息可在设置中导出日志。'))
              : const Center(child: CircularProgressIndicator()),
        ),
      ),
    ),
  );
}
