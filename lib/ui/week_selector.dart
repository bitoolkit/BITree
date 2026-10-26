import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../schedule/model.dart';
import 'app_menu_anchor.dart';
import 'app_menu_trigger.dart';
import 'design.dart';

class WeekSelector extends StatelessWidget {
  const WeekSelector({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final schedule = controller.schedule;
    final screen = MediaQuery.sizeOf(context);
    final cellSize = math.max(
      48.0,
      MediaQuery.textScalerOf(context).scale(14) * 2 + 16,
    );
    final columns = ((screen.width - 32) / (cellSize + 4)).floor().clamp(1, 5);
    final weeks = controller.weeks;
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
                      selected: controller.week == week,
                      child: AppMenuItemButton(
                        onPressed: () => controller.selectWeek(week),
                        style: MenuItemButton.styleFrom(
                          padding: EdgeInsets.zero,
                          backgroundColor: controller.week == week
                              ? scheme.primary
                              : Colors.transparent,
                          foregroundColor: controller.week == week
                              ? scheme.onPrimary
                              : week == currentWeek
                              ? scheme.primary
                              : scheme.onSurface,
                          side: week == currentWeek
                              ? BorderSide(color: scheme.primary)
                              : BorderSide.none,
                          textStyle: TextStyle(
                            fontWeight:
                                controller.week == week || week == currentWeek
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
        label: schedule == null ? '课表' : '第${controller.week}周',
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
