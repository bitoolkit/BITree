import 'package:flutter/material.dart';

import '../agenda/model.dart';
import '../app_controller.dart';
import '../schedule/model.dart';
import 'add_menu.dart';
import 'agenda_list_tile.dart';
import 'app_menu_anchor.dart';
import 'app_page.dart';
import 'pull_to_reveal_list.dart';
import 'school_import_button.dart';
import 'swipe_pager.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    required this.controller,
    required this.now,
  });

  final AppController controller;
  final DateTime now;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  AgendaKind? _kind;
  int _status = 0;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final now = widget.now;
    final scheme = Theme.of(context).colorScheme;
    final entries = controller.agenda.entries
        .where((entry) => _kind == null || entry.kind == _kind)
        .toList();
    final doneCount = entries.where((entry) => entry.isFinished(now)).length;

    return AppPage(
      title: Row(
        children: [
          const Text('日程'),
          const SizedBox(width: 8),
          Flexible(
            child: _AgendaKindFilter(
              value: _kind,
              onChanged: (kind) => setState(() => _kind = kind),
            ),
          ),
        ],
      ),
      actions: [
        AddButton(controller: controller, includeCourse: false),
        SchoolImportButton(controller: controller),
      ],
      child: SwipePager(
        index: _status,
        itemCount: 2,
        onChanged: (index) => setState(() => _status = index),
        headerBuilder: (context, tabs) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TabBar(
              controller: tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorSize: TabBarIndicatorSize.label,
              labelPadding: const EdgeInsets.symmetric(horizontal: 12),
              labelColor: scheme.primary,
              unselectedLabelColor: scheme.onSurfaceVariant,
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
              tabs: [
                Tab(text: '未完成 ${entries.length - doneCount}'),
                Tab(text: '已完成 $doneCount'),
              ],
            ),
            if (!controller.agenda.ready && controller.agenda.busy)
              const LinearProgressIndicator(minHeight: 3),
            if (!controller.agenda.ready && !controller.agenda.busy)
              TextButton.icon(
                onPressed: controller.agenda.load,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重新加载日程'),
              ),
          ],
        ),
        itemBuilder: (context, index) => _AgendaStatusList(
          key: ValueKey((_kind, index)),
          controller: controller,
          entries: entries,
          completed: index == 1,
          now: now,
        ),
      ),
    );
  }
}

class _AgendaStatusList extends StatelessWidget {
  const _AgendaStatusList({
    super.key,
    required this.controller,
    required this.entries,
    required this.completed,
    required this.now,
  });

  final AppController controller;
  final List<AgendaEntry> entries;
  final bool completed;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final visible =
        entries.where((entry) => entry.isFinished(now) == completed).toList()
          ..sort((a, b) {
            final time = a.startsAt.compareTo(b.startsAt);
            final order = time == 0 ? a.id.compareTo(b.id) : time;
            return completed ? -order : order;
          });
    final days = <DateTime, List<AgendaEntry>>{};
    final overdueDays = <DateTime, List<AgendaEntry>>{};
    for (final entry in visible) {
      final group = entry.overdue(now) ? overdueDays : days;
      group.putIfAbsent(calendarDate(entry.startsAt), () => []).add(entry);
    }

    List<Widget> dayRows(Map<DateTime, List<AgendaEntry>> groups) => [
      for (final day in groups.entries) ...[
        _AgendaDateHeading(
          key: ValueKey(('day', day.key)),
          date: day.key,
          now: now,
        ),
        for (final entry in day.value)
          AgendaListTile(
            key: ValueKey(entry.id),
            controller: controller,
            entry: entry,
            now: now,
          ),
      ],
    ];

    final overdueCount = overdueDays.values.fold(
      0,
      (count, entries) => count + entries.length,
    );

    return PullToRevealList(
      hiddenLabel: '$overdueCount项逾期日程',
      hiddenChildren: dayRows(overdueDays),
      children: [
        if (days.isEmpty && controller.agenda.ready)
          Padding(
            key: const ValueKey('empty-state'),
            padding: const EdgeInsets.symmetric(vertical: 64),
            child: Center(
              child: Text(
                completed
                    ? '还没有已完成的日程'
                    : overdueCount > 0
                    ? '没有即将到来的日程'
                    : '没有未完成的日程',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ...dayRows(days),
      ],
    );
  }
}

class _AgendaKindFilter extends StatelessWidget {
  const _AgendaKindFilter({required this.value, required this.onChanged});

  final AgendaKind? value;
  final ValueChanged<AgendaKind?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppMenuAnchor(
      menuChildren: [
        for (final kind in [
          null,
          AgendaKind.deadline,
          AgendaKind.event,
          AgendaKind.exam,
        ])
          Semantics(
            selected: value == kind,
            child: AppMenuItemButton(
              onPressed: () => onChanged(kind),
              trailingIcon: value == kind
                  ? const Icon(Icons.check_rounded, size: 18)
                  : const SizedBox(width: 18),
              child: Text(kind?.label ?? '全部'),
            ),
          ),
      ],
      builder: (context, menu, isOpen) => Semantics(
        label: '日程类型',
        expanded: isOpen,
        child: TextButton(
          onPressed: () => isOpen ? menu.close() : menu.open(),
          style: TextButton.styleFrom(
            foregroundColor: value == null
                ? scheme.onSurfaceVariant
                : scheme.primary,
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            textStyle: theme.textTheme.bodyMedium,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  value?.label ?? '全部',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                isOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgendaDateHeading extends StatelessWidget {
  const _AgendaDateHeading({super.key, required this.date, required this.now});

  final DateTime date;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = date.difference(calendarDate(now)).inDays;
    final label = switch (days) {
      0 => '今天',
      1 => '明天',
      -1 => '昨天',
      _ => weekdays[date.weekday - 1],
    };
    final year = date.year == now.year ? '' : '${date.year}年';

    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: label,
              style: TextStyle(
                color: days == 0 ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            TextSpan(
              text: '  $year${date.month}月${date.day}日',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}
