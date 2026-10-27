import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../schedule/model.dart';
import '../../school/ui/school_screen.dart';
import '../../school/ui/school_verification_dialog.dart';
import '../../ui/app_dropdown_field.dart';
import '../../ui/campus_time_builder.dart';
import '../../ui/dialog_layout.dart';
import '../../wencui/place.dart';
import '../../wencui/ui/wencui_map_screen.dart';
import '../controller.dart';
import '../model.dart';
import 'classroom_time_field.dart';

enum _DateChoice { today, tomorrow, other }

class ClassroomScreen extends StatefulWidget {
  const ClassroomScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<ClassroomScreen> createState() => _ClassroomScreenState();
}

class _ClassroomScreenState extends State<ClassroomScreen> {
  late final _queryState = ClassroomController(
    repository: widget.controller.classrooms,
    school: widget.controller.school,
    verify: (request) => verifySchoolLogin(context, request),
    signIn: () async =>
        mounted &&
        await openSchoolPage(
              context,
              widget.controller,
              action: SchoolAction.signIn,
            ) ==
            true,
    date: campusNow(),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_queryState.load());
    });
  }

  @override
  void dispose() {
    _queryState.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      builder: appPickerDialogBuilder,
      initialDate: _queryState.date,
      firstDate: DateTime(_queryState.date.year - 1),
      lastDate: DateTime(_queryState.date.year + 1, 12, 31),
    );
    if (date != null && mounted) _queryState.selectDate(date);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _queryState,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) => CampusTimeBuilder(
    active: true,
    builder: (context, now) => Scaffold(
      appBar: AppBar(
        title: const Text('空教室查询'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => _queryState.load(refresh: true),
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
    final directory = _queryState.directory;
    if (directory == null) {
      return _queryState.busy
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          : OutlinedButton.icon(
              onPressed: () => _queryState.load(refresh: true),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('加载教学楼'),
            );
    }
    if (directory.campuses.isEmpty) {
      return _QueryState(
        message: '暂无可查询的校区',
        action: '重新加载',
        onPressed: () => _queryState.load(refresh: true),
      );
    }

    final today = calendarDate(now);
    final tomorrow = today.add(const Duration(days: 1));
    final dateChoice = _queryState.date == today
        ? _DateChoice.today
        : _queryState.date == tomorrow
        ? _DateChoice.tomorrow
        : _DateChoice.other;
    final style = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(fontSize: 13);

    return _QueryFields(
      children: [
        AppDropdownField<String>(
          label: '校区',
          value: _queryState.campusCode!,
          textStyle: style,
          entries: [
            for (final campus in directory.campuses)
              DropdownMenuEntry(value: campus.code, label: campus.name),
          ],
          onChanged: _queryState.selectCampus,
        ),
        AppDropdownField<_DateChoice>(
          label: '日期',
          value: dateChoice,
          textStyle: style,
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
              label: _queryState.date.year == now.year
                  ? '${_queryState.date.month}/${_queryState.date.day} ${weekdays[_queryState.date.weekday - 1]}'
                  : dateText(_queryState.date),
              labelWidget: const Text('其他日期'),
            ),
          ],
          onChanged: (value) {
            switch (value) {
              case _DateChoice.today:
                _queryState.selectDate(today);
              case _DateChoice.tomorrow:
                _queryState.selectDate(tomorrow);
              case _DateChoice.other:
                unawaited(_pickDate());
            }
          },
        ),
        AppDropdownField<String?>(
          label: '教学楼',
          value: _queryState.buildingFilter,
          textStyle: style,
          entries: [
            const DropdownMenuEntry(value: null, label: '全部教学楼'),
            if (_queryState.buildings.any((building) => building.isWenCui))
              const DropdownMenuEntry(
                value: wenCuiBuildingFilter,
                label: '文萃楼（全部）',
              ),
            for (final building in _queryState.buildings)
              DropdownMenuEntry(
                value: buildingFilterKey(building),
                label: building.name,
              ),
          ],
          onChanged: (value) => _queryState.selectBuilding(value),
        ),
        ClassroomTimeField(
          value: _queryState.period,
          date: _queryState.date,
          now: now,
          onChanged: (value) => _queryState.selectPeriod(value),
        ),
      ],
    );
  }

  List<Widget> _buildResults(DateTime now) {
    if (_queryState.directory == null ||
        _queryState.directory!.campuses.isEmpty) {
      return const [];
    }
    final period = _queryState.period;
    final groups = _queryState.results;
    final count = groups.fold(0, (total, group) => total + group.rooms.length);
    final theme = Theme.of(context);
    final current = _queryState.date == calendarDate(now)
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
                      _queryState.busy
                          ? '查询中…'
                          : !_queryState.hasResult
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
              if (_queryState.busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(minHeight: 2),
              ],
              if (!_queryState.busy && !_queryState.hasResult)
                _QueryState(
                  message: widget.controller.school.username == null
                      ? '登录后可查询空教室'
                      : '查询未完成',
                  action: '重新查询',
                  onPressed: _queryState.query,
                )
              else if (!_queryState.busy && groups.isEmpty)
                _QueryState(
                  message: _queryState.buildings.isEmpty
                      ? '这个校区还没有教学楼信息'
                      : period != null
                      ? '这段时间没有空教室'
                      : '当天没有空闲时段',
                  action: _queryState.buildings.isEmpty
                      ? '重新加载教学楼'
                      : period != null
                      ? '不限时段查看'
                      : _queryState.buildingFilter != null
                      ? '查看全部教学楼'
                      : '换个日期',
                  onPressed: () {
                    if (_queryState.buildings.isEmpty) {
                      unawaited(_queryState.load(refresh: true));
                    } else if (period != null) {
                      _queryState.selectPeriod(null);
                    } else if (_queryState.buildingFilter != null) {
                      _queryState.selectBuilding(null);
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
                  onTap: () => _showRoom(
                    context,
                    widget.controller,
                    group.building,
                    room,
                    _queryState.date,
                  ),
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
  AppController controller,
  SchoolBuilding building,
  ClassroomOccupancy room,
  DateTime date,
) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: Text('${building.name} ${room.name}'),
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
      if (WencuiPlace.parse('${building.name} ${room.name}') != null)
        TextButton.icon(
          onPressed: () {
            Navigator.pop(dialogContext);
            Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => WencuiMapScreen(
                  controller: controller,
                  initialRoom: '${building.name} ${room.name}',
                ),
              ),
            );
          },
          icon: const Icon(Icons.map_outlined, size: 18),
          label: const Text('文萃地图'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text('关闭'),
      ),
    ],
  ),
);
