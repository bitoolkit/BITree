import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../schedule/model.dart';
import 'add_menu.dart';
import 'agenda_reminder.dart';
import 'app_page.dart';
import 'course_detail.dart';
import 'course_editor.dart';
import 'schedule_menu.dart';
import 'school_import_button.dart';
import 'school_screen.dart';
import 'week_pager.dart';
import 'week_selector.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.now,
    this.active = true,
  });

  final AppController controller;
  final DateTime now;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final schedule = controller.schedule;
    final currentSemester = semesterAt(controller.schedules, now);
    final currentWeek = currentSemester?.term == schedule?.term
        ? currentSemester?.weekAt(now)
        : null;
    final selectedDate =
        schedule != null && schedule.weekAt(now) != controller.week
        ? schedule.mondayAt(controller.week).add(const Duration(hours: 9))
        : now;

    return AppPage(
      title: schedule == null
          ? const Text('首页')
          : LayoutBuilder(
              builder: (context, constraints) {
                final selector = WeekSelector(controller: controller);
                final compact =
                    constraints.maxWidth <
                    MediaQuery.textScalerOf(context).scale(200);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: selector),
                    if (currentWeek != null && controller.week != currentWeek)
                      if (compact)
                        IconButton(
                          tooltip: '回到本周',
                          onPressed: () => controller.selectWeek(currentWeek),
                          icon: const Icon(Icons.today_outlined, size: 20),
                        )
                      else
                        TextButton(
                          onPressed: () => controller.selectWeek(currentWeek),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: const Text('回到本周'),
                        ),
                  ],
                );
              },
            ),
      actions: [
        AddButton(controller: controller, date: selectedDate),
        SchoolImportButton(controller: controller),
        ScheduleMenu(controller: controller),
      ],
      child: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!controller.ready)
                const LinearProgressIndicator(minHeight: 3),
              Expanded(
                child: schedule == null
                    ? Center(
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          alignment: WrapAlignment.center,
                          children: [
                            FilledButton.icon(
                              onPressed:
                                  controller.busy || controller.schoolBusy
                                  ? null
                                  : () => openSchoolPage(
                                      context,
                                      controller,
                                      action: SchoolAction.importSchedule,
                                    ),
                              icon: const Icon(Icons.input_rounded, size: 20),
                              label: const Text('导入课表'),
                            ),
                            OutlinedButton.icon(
                              onPressed: controller.busy
                                  ? null
                                  : () => editCourse(context, controller),
                              icon: const Icon(Icons.add_rounded, size: 20),
                              label: const Text('添加课程'),
                            ),
                          ],
                        ),
                      )
                    : WeekPager(
                        key: ValueKey((
                          schedule.term,
                          schedule.firstMonday,
                          controller.weeks.first,
                          controller.weeks.last,
                        )),
                        controller: controller,
                        active: active,
                      ),
              ),
              if (schedule != null &&
                  schedule.courses.any((course) => !course.isScheduled))
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _unscheduled(context),
                    child: const Text('时间待定的课程'),
                  ),
                ),
            ],
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: AgendaReminder(
                  controller: controller,
                  entries: controller.agenda.ready
                      ? controller.agenda.pendingOn(now, now: now)
                      : const [],
                  now: now,
                  active: active,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _unscheduled(BuildContext context) => showDialog<void>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('时间待定的课程'),
      children: [
        for (final course in controller.schedule!.courses.where(
          (course) => !course.isScheduled,
        ))
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(dialogContext);
              showCourse(context, controller, course);
            },
            child: Text(course.name),
          ),
      ],
    ),
  );
}
