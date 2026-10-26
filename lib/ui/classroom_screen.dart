import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../classrooms/model.dart';
import '../data/cancelable_request.dart';
import '../schedule/model.dart';
import 'app_dropdown_field.dart';
import 'app_notice.dart';
import 'campus_time_builder.dart';
import 'classroom_time_field.dart';
import 'school_screen.dart';
import 'school_verification_dialog.dart';

enum _DateChoice { today, tomorrow, other }

class ClassroomScreen extends StatefulWidget {
  const ClassroomScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<ClassroomScreen> createState() => _ClassroomScreenState();
}

class _ClassroomScreenState extends State<ClassroomScreen> {
  ClassroomDirectory? _directory;
  String? _campusCode;
  String? _buildingCode;
  DateTime _date = calendarDate(campusNow());
  ClassroomPeriod? _period;
  List<BuildingOccupancy>? _occupancy;
  bool _working = false;
  final _requests = LatestRequest();

  List<SchoolBuilding> get _buildings => [
    for (final building in _directory?.buildings ?? <SchoolBuilding>[])
      if (building.campusCode == _campusCode) building,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadDirectory());
    });
  }

  @override
  void dispose() {
    _requests.cancel();
    super.dispose();
  }

  Future<T?> _withLogin<T>(
    CancellationToken cancellation,
    Future<T?> Function() read,
  ) async {
    final controller = widget.controller;
    if (controller.busy || controller.schoolBusy) {
      showAppNotice(context, '正在处理学校请求，请稍后再试。');
      return null;
    }

    Future<bool> signIn() async =>
        await openSchoolPage(
          context,
          controller,
          action: SchoolAction.signIn,
        ) ==
        true;

    if (controller.username == null) {
      if (!await signIn() || !mounted) return null;
      cancellation.check();
    }

    var result = await read();
    cancellation.check();
    if (!mounted) return null;
    if (result == null && controller.loginExpired) {
      if (!await signIn() || !mounted) return null;
      cancellation.check();
      result = await read();
    }
    return result;
  }

  Future<void> _runQuery(
    Future<void> Function(CancellationToken cancellation) read,
  ) async {
    setState(() => _working = true);
    await _requests.run((cancellation) async {
      try {
        await read(cancellation);
      } finally {
        if (mounted && !cancellation.isCancelled) {
          setState(() => _working = false);
        }
      }
    });
  }

  Future<void> _loadDirectory({bool refresh = false}) =>
      _runQuery((cancellation) async {
        final result = await _withLogin(
          cancellation,
          () => widget.controller.classroomDirectory(
            verify: (request) => verifySchoolLogin(context, request),
            refresh: refresh,
            cancellation: cancellation,
          ),
        );
        cancellation.check();
        if (!mounted || result == null) return;
        setState(() {
          _directory = result;
          if (!result.campuses.any((campus) => campus.code == _campusCode)) {
            _campusCode =
                result.campuses
                    .where((campus) => campus.name.contains('良乡'))
                    .firstOrNull
                    ?.code ??
                result.campuses.firstOrNull?.code;
            _occupancy = null;
          }
          if (!_buildings.any((building) => building.code == _buildingCode)) {
            _buildingCode = null;
          }
        });
        await _fetchOccupancy(cancellation, refresh: refresh);
      });

  Future<void> _query({bool refresh = false}) => _runQuery(
    (cancellation) => _fetchOccupancy(cancellation, refresh: refresh),
  );

  Future<void> _fetchOccupancy(
    CancellationToken cancellation, {
    required bool refresh,
  }) async {
    if (_campusCode == null) return;
    final buildings = _buildings;
    final date = _date;
    if (buildings.isEmpty) {
      setState(() => _occupancy = const []);
      return;
    }
    final result = await _withLogin(
      cancellation,
      () => widget.controller.classroomOccupancy(
        buildings: buildings,
        date: date,
        verify: (request) => verifySchoolLogin(context, request),
        refresh: refresh,
        cancellation: cancellation,
      ),
    );
    cancellation.check();
    if (!mounted) return;
    setState(() {
      if (result == null) return;
      _occupancy = result;
    });
  }

  void _changeCampus(String code) {
    if (_campusCode == code) return;
    setState(() {
      _campusCode = code;
      _buildingCode = null;
      _occupancy = null;
    });
    unawaited(_query());
  }

  void _changeDate(DateTime date) {
    date = calendarDate(date);
    if (_date == date) return;
    setState(() {
      _date = date;
      _occupancy = null;
    });
    unawaited(_query());
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year - 1),
      lastDate: DateTime(_date.year + 1, 12, 31),
    );
    if (date != null && mounted) _changeDate(date);
  }

  @override
  Widget build(BuildContext context) => CampusTimeBuilder(
    active: true,
    builder: (context, now) => Scaffold(
      appBar: AppBar(
        title: const Text('空教室查询'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => _loadDirectory(refresh: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: _buildQuery(now),
                  ),
                ),
                ..._buildResults(now),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildQuery(DateTime now) {
    final directory = _directory;
    if (directory == null) {
      return _working
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          : OutlinedButton.icon(
              onPressed: () => _loadDirectory(refresh: true),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('加载教学楼'),
            );
    }
    if (directory.campuses.isEmpty) {
      return _QueryState(
        message: '暂无可查询的校区',
        action: '重新加载',
        onPressed: () => _loadDirectory(refresh: true),
      );
    }

    final today = calendarDate(now);
    final tomorrow = today.add(const Duration(days: 1));
    final dateChoice = _date == today
        ? _DateChoice.today
        : _date == tomorrow
        ? _DateChoice.tomorrow
        : _DateChoice.other;
    final menuWidth = math.min(360.0, MediaQuery.sizeOf(context).width - 32);
    final style = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(fontSize: 13);

    return _QueryFields(
      children: [
        AppDropdownField<String>(
          label: '校区',
          value: _campusCode!,
          textStyle: style,
          menuWidth: menuWidth,
          entries: [
            for (final campus in directory.campuses)
              DropdownMenuEntry(value: campus.code, label: campus.name),
          ],
          onChanged: _changeCampus,
        ),
        AppDropdownField<_DateChoice>(
          label: '日期',
          value: dateChoice,
          textStyle: style,
          menuWidth: menuWidth,
          entries: [
            DropdownMenuEntry(
              value: _DateChoice.today,
              label: '今天 ${today.month}/${today.day}',
            ),
            DropdownMenuEntry(
              value: _DateChoice.tomorrow,
              label: '明天 ${tomorrow.month}/${tomorrow.day}',
            ),
            DropdownMenuEntry(
              value: _DateChoice.other,
              label: _date.year == now.year
                  ? '${_date.month}/${_date.day} ${weekdays[_date.weekday - 1]}'
                  : dateText(_date),
              labelWidget: const Text('其他日期'),
            ),
          ],
          onChanged: (value) {
            switch (value) {
              case _DateChoice.today:
                _changeDate(today);
              case _DateChoice.tomorrow:
                _changeDate(tomorrow);
              case _DateChoice.other:
                unawaited(_pickDate());
            }
          },
        ),
        AppDropdownField<String?>(
          label: '教学楼',
          value: _buildingCode,
          textStyle: style,
          menuWidth: menuWidth,
          entries: [
            const DropdownMenuEntry(value: null, label: '全部教学楼'),
            for (final building in _buildings)
              DropdownMenuEntry(value: building.code, label: building.name),
          ],
          onChanged: (value) => setState(() => _buildingCode = value),
        ),
        ClassroomTimeField(
          value: _period,
          date: _date,
          now: now,
          onChanged: (value) => setState(() => _period = value),
        ),
      ],
    );
  }

  List<Widget> _buildResults(DateTime now) {
    if (_directory == null || _directory!.campuses.isEmpty) return const [];
    final period = _period;
    final groups = <BuildingOccupancy>[];
    for (final group in _occupancy ?? <BuildingOccupancy>[]) {
      if (_buildingCode != null && group.building.code != _buildingCode) {
        continue;
      }
      final rooms = group.rooms
          .where(
            (room) => period == null
                ? room.freePeriods.isNotEmpty
                : room.freePeriod(period.start, period.end) != null,
          )
          .toList();
      if (rooms.isNotEmpty) {
        groups.add(BuildingOccupancy(building: group.building, rooms: rooms));
      }
    }
    final count = groups.fold(0, (total, group) => total + group.rooms.length);
    final theme = Theme.of(context);
    final current = _date == calendarDate(now)
        ? currentClassroomSection(now)
        : null;

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      period == null ? '教室空闲时间' : '符合时段的教室',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _working
                          ? '查询中…'
                          : _occupancy == null
                          ? ''
                          : '$count间',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                period == null ? '显示各教室当天的空闲时段' : '${period.timeLabel}内全程空闲',
                style: theme.textTheme.bodySmall,
              ),
              if (_working) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(minHeight: 2),
              ],
              if (!_working && _occupancy == null)
                _QueryState(
                  message: widget.controller.username == null
                      ? '登录后可查询空教室'
                      : '查询未完成',
                  action: '重新查询',
                  onPressed: _query,
                )
              else if (!_working && groups.isEmpty)
                _QueryState(
                  message: _buildings.isEmpty
                      ? '这个校区还没有教学楼信息'
                      : period != null
                      ? '这段时间没有空教室'
                      : '当天没有空闲时段',
                  action: _buildings.isEmpty
                      ? '重新加载教学楼'
                      : period != null
                      ? '不限时段查看'
                      : _buildingCode != null
                      ? '查看全部教学楼'
                      : '换个日期',
                  onPressed: () {
                    if (_buildings.isEmpty) {
                      unawaited(_loadDirectory(refresh: true));
                    } else if (period != null) {
                      setState(() => _period = null);
                    } else if (_buildingCode != null) {
                      setState(() => _buildingCode = null);
                    } else {
                      unawaited(_pickDate());
                    }
                  },
                ),
            ],
          ),
        ),
      ),
      for (final group in groups) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
            child: Text(group.building.name, style: theme.textTheme.bodySmall),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.builder(
            itemCount: group.rooms.length,
            itemBuilder: (context, index) {
              final room = group.rooms[index];
              return DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(room.name),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        for (final free in room.freePeriods)
                          Text(
                            free.timeLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color:
                                  (period != null
                                      ? free.includes(period)
                                      : current != null &&
                                            free.contains(current))
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                  onTap: () => _showRoom(context, group.building, room, _date),
                ),
              );
            },
          ),
        ),
      ],
      if (groups.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Text('空闲表示该时段没有排课', style: theme.textTheme.bodySmall),
          ),
        ),
    ];
  }
}

class _QueryFields extends StatelessWidget {
  const _QueryFields({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final minimumWidth = MediaQuery.textScalerOf(context).scale(13) * 8 + 36;
      final columns = constraints.maxWidth >= 720 * scale
          ? 4
          : constraints.maxWidth >= minimumWidth * 2 + 8
          ? 2
          : 1;
      final width = (constraints.maxWidth - 8 * (columns - 1)) / columns;
      return Wrap(
        spacing: 8,
        runSpacing: 12,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class _QueryState extends StatelessWidget {
  const _QueryState({
    required this.message,
    required this.action,
    required this.onPressed,
  });

  final String message;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        const SizedBox(height: 8),
        TextButton(onPressed: onPressed, child: Text(action)),
      ],
    ),
  );
}

Future<void> _showRoom(
  BuildContext context,
  SchoolBuilding building,
  ClassroomOccupancy room,
  DateTime date,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text('${building.name} ${room.name}'),
    constraints: const BoxConstraints(maxWidth: 560),
    insetPadding: const EdgeInsets.all(24),
    scrollable: true,
    content: SizedBox(
      width: double.maxFinite,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${dateText(date)} ${weekdays[date.weekday - 1]}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          for (final block in room.periods)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(block.period.timeLabel),
              subtitle: Text(block.period.sectionLabel),
              trailing: Text(
                block.busy ? '有课' : '空闲',
                style: TextStyle(
                  color: block.busy
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  ),
);
