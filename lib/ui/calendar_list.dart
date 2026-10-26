import 'package:flutter/material.dart';

import '../agenda/calendar.dart';
import '../agenda/model.dart';
import '../app_controller.dart';
import '../schedule/model.dart';
import 'agenda_detail.dart';
import 'completion_text.dart';
import 'course_detail.dart';
import 'sheet_layout.dart';

IconData agendaIcon(AgendaKind kind) => switch (kind) {
  AgendaKind.event => Icons.event_outlined,
  AgendaKind.deadline => Icons.flag_outlined,
  AgendaKind.exam => Icons.edit_note_rounded,
};

Future<void> showAgendaDay(
  BuildContext context,
  AppController controller,
  DateTime date,
) => showCalendarItems(
  context,
  controller,
  agendaDateLabel(date),
  controller.agenda
      .pendingOn(date, now: campusNow())
      .map(CalendarItem.agenda)
      .toList(),
  emptyMessage: '没有未完成的日程',
);

Future<void> openCalendarItem(
  BuildContext context,
  AppController controller,
  CalendarItem item,
) => item.course != null
    ? showCourse(context, controller, item.course!)
    : showAgendaEntry(context, controller, item.entry!);

Future<void> showCalendarItems(
  BuildContext context,
  AppController controller,
  String title,
  List<CalendarItem> items, {
  bool showDates = false,
  String emptyMessage = '这一天没有安排',
}) async {
  final selected = await showModalBottomSheet<CalendarItem>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => SafeArea(
      top: false,
      child: SheetLayout(
        header: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items)
              ListTile(
                leading: Icon(
                  item.entry == null
                      ? Icons.school_outlined
                      : agendaIcon(item.entry!.kind),
                ),
                title: CompletionText(
                  item.title,
                  completed: item.entry?.done == true,
                ),
                subtitle: CompletionText(
                  [
                    item.kindLabel,
                    if (item.entry?.source != null) item.entry!.source!.label,
                    if (item.entry?.course.isNotEmpty == true)
                      item.entry!.course,
                    if (showDates) agendaDateLabel(item.startsAt),
                    item.timeLabel,
                    if (item.location.isNotEmpty) item.location,
                  ].join('\n'),
                  completed: item.entry?.done == true,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(context, item),
              ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(emptyMessage),
              ),
          ],
        ),
      ),
    ),
  );
  if (selected != null && context.mounted) {
    await openCalendarItem(context, controller, selected);
  }
}
