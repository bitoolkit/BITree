import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../ui/app_menu_anchor.dart';
import '../../ui/app_menu_trigger.dart';
import '../../ui/design.dart';
import '../model.dart';

class WeekSelector extends StatelessWidget {
  const WeekSelector({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final schedule = controller.timetable.schedule;
    final screen = MediaQuery.sizeOf(context);
    final cellSize = math.max(
      48.0,
      MediaQuery.textScalerOf(context).scale(14) * 2 + 16,
    );
    final columns = ((screen.width - 32) / (cellSize + 4)).floor().clamp(1, 5);
    final weeks = controller.timetable.weeks;
    final currentWeek = schedule?.weekAt(campusNow());
    return AppMenuAnchor(
      style: MenuStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
      ),
      menuChildren: [
        for (var row = 0; row < weeks.length; row += columns)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final week in weeks.skip(row).take(columns))
                Padding(
                  padding: const EdgeInsets.all(2),
                  child: SizedBox.square(
                    dimension: cellSize,
                    child: Semantics(
                      selected: controller.timetable.week == week,
                      child: AppMenuItemButton(
                        onPressed: () => controller.timetable.selectWeek(week),
                        style: MenuItemButton.styleFrom(
                          padding: EdgeInsets.zero,
                          backgroundColor: controller.timetable.week == week
                              ? scheme.primary
                              : Colors.transparent,
                          foregroundColor: controller.timetable.week == week
                              ? scheme.onPrimary
                              : week == currentWeek
                              ? scheme.primary
                              : scheme.onSurface,
                          side: week == currentWeek
                              ? BorderSide(color: scheme.primary)
                              : BorderSide.none,
                          textStyle: TextStyle(
                            fontWeight:
                                controller.timetable.week == week ||
                                    week == currentWeek
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                          shape: appControlShape,
                        ),
                        child: Center(
                          child: Text(
                            '$week',
                            semanticsLabel:
                                '第 $week 周${week == currentWeek ? '，本周' : ''}',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
      builder: (context, menu, isOpen) => AppMenuTrigger(
        label: schedule == null ? '课表' : '第${controller.timetable.week}周',
        semanticsLabel: '选择周次',
        isOpen: isOpen,
        foregroundColor: scheme.onSurface,
        textStyle: Theme.of(context).appBarTheme.titleTextStyle,
        onPressed: schedule == null
            ? null
            : () => isOpen ? menu.close() : menu.open(),
      ),
    );
  }
}
