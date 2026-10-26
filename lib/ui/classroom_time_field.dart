import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../classrooms/model.dart';
import '../schedule/model.dart';
import 'app_dropdown_field.dart';
import 'design.dart';

enum _TimePreset { all, current, morning, afternoon, evening, custom }

class ClassroomTimeField extends StatelessWidget {
  const ClassroomTimeField({
    super.key,
    required this.value,
    required this.date,
    required this.now,
    required this.onChanged,
  });

  final ClassroomPeriod? value;
  final DateTime date;
  final DateTime now;
  final ValueChanged<ClassroomPeriod?> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = date == calendarDate(now)
        ? currentClassroomSection(now)
        : null;
    final ranges = {
      if (current != null) _TimePreset.current: (start: current, end: current),
      _TimePreset.morning: (start: 1, end: 5),
      _TimePreset.afternoon: (start: 6, end: 10),
      _TimePreset.evening: (start: 11, end: sectionTimes.length),
    };
    final selected = value == null
        ? _TimePreset.all
        : ranges.entries
                  .where((entry) => entry.value == value)
                  .firstOrNull
                  ?.key ??
              _TimePreset.custom;
    final names = {
      _TimePreset.all: '不限时段',
      _TimePreset.current: '当前这节',
      _TimePreset.morning: '上午',
      _TimePreset.afternoon: '下午',
      _TimePreset.evening: '晚上',
      _TimePreset.custom: '自选课次',
    };

    return AppDropdownField<_TimePreset>(
      label: '空闲时段',
      value: selected,
      textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13),
      entries: [
        for (final preset in [
          _TimePreset.all,
          ...ranges.keys,
          _TimePreset.custom,
        ])
          DropdownMenuEntry(
            value: preset,
            label: preset == selected && value != null
                ? value!.timeLabel
                : names[preset]!,
            labelWidget: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(names[preset]!),
                  const SizedBox(height: 2),
                  Text(switch (preset) {
                    _TimePreset.all => '查看当天所有空闲时段',
                    _TimePreset.custom => '选择一节或连续几节',
                    _ =>
                      '${ranges[preset]!.timeLabel}（${ranges[preset]!.sectionLabel}）',
                  }, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
      ],
      onChanged: (preset) async {
        if (preset != _TimePreset.custom) {
          onChanged(ranges[preset]);
          return;
        }
        final selection = await showDialog<({ClassroomPeriod? period})>(
          context: context,
          builder: (_) => _ClassroomTimeDialog(
            initial: value ?? (start: current ?? 1, end: current ?? 2),
          ),
        );
        if (selection != null && context.mounted) {
          onChanged(selection.period);
        }
      },
    );
  }
}

class _ClassroomTimeDialog extends StatefulWidget {
  const _ClassroomTimeDialog({required this.initial});

  final ClassroomPeriod initial;

  @override
  State<_ClassroomTimeDialog> createState() => _ClassroomTimeDialogState();
}

class _ClassroomTimeDialogState extends State<_ClassroomTimeDialog> {
  late ClassroomPeriod _period = widget.initial;
  bool _choosingEnd = false;

  void _select(int section) => setState(() {
    if (_choosingEnd) {
      _period = (
        start: math.min(_period.start, section),
        end: math.max(_period.start, section),
      );
    } else {
      _period = (start: section, end: section);
    }
    _choosingEnd = !_choosingEnd;
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
        scrollable: true,
        title: Row(
          children: [
            const Expanded(child: Text('选择空闲时段')),
            IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
          ],
        ),
        content: LayoutBuilder(
          builder: (context, constraints) {
            final columns =
                (constraints.maxWidth /
                        (MediaQuery.textScalerOf(context).scale(11) * 7 + 20))
                    .floor()
                    .clamp(1, 4);
            final width = (constraints.maxWidth - (columns - 1) * 6) / columns;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '先选起始课次，再选结束课次。只用一节可直接应用。',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: AppCorners.control,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _period.timeLabel,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_period.sectionLabel}内全程空闲',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (
                      var section = 1;
                      section <= sectionTimes.length;
                      section++
                    )
                      SizedBox(
                        width: width,
                        child: Semantics(
                          selected: _period.contains(section),
                          child: OutlinedButton(
                            onPressed: () => _select(section),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 54),
                              padding: const EdgeInsets.symmetric(
                                vertical: 7,
                                horizontal: 3,
                              ),
                              backgroundColor: _period.contains(section)
                                  ? scheme.primaryContainer
                                  : null,
                              foregroundColor: _period.contains(section)
                                  ? scheme.onPrimaryContainer
                                  : scheme.onSurface,
                              side: BorderSide(
                                color: _period.contains(section)
                                    ? scheme.primary
                                    : scheme.outlineVariant,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '第$section节',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  (start: section, end: section).timeLabel,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, (period: null)),
            child: const Text('不限时段'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, (period: _period)),
            child: const Text('应用'),
          ),
        ],
      ),
    );
  }
}
