import 'package:flutter/material.dart';

import '../agenda/calendar.dart';
import '../agenda/model.dart';
import '../app_controller.dart';
import '../schedule/model.dart';
import 'agenda_detail.dart';
import 'agenda_time.dart';
import 'completion_text.dart';
import 'course_detail.dart';
import 'sheet_layout.dart';
import 'design.dart';

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
    builder: (context) => SafeArea(
      top: false,
      child: SheetLayout(
        header: SheetHeader(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '${items.length}项日程',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
          actions: [
            IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
          ],
        ),
        content: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < items.length; index++) ...[
                if (index > 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Divider(height: 1),
                  ),
                _CalendarItemRow(
                  item: items[index],
                  now: campusNow(),
                  showDate: showDates,
                  onTap: () => Navigator.pop(context, items[index]),
                ),
              ],
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 20, 12, 28),
                  child: Text(
                    emptyMessage,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  if (selected != null && context.mounted) {
    await openCalendarItem(context, controller, selected);
  }
}

class _CalendarItemRow extends StatelessWidget {
  const _CalendarItemRow({
    required this.item,
    required this.now,
    required this.showDate,
    required this.onTap,
  });

  final CalendarItem item;
  final DateTime now;
  final bool showDate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entry = item.entry;
    final overdue = entry?.overdue(now) == true;
    final dueToday =
        entry?.isDeadline == true &&
        !entry!.done &&
        calendarDate(item.startsAt) == calendarDate(now);
    final timeColor = overdue
        ? scheme.error
        : dueToday
        ? scheme.primary
        : scheme.onSurface;
    final captionStyle = theme.textTheme.bodySmall?.copyWith(
      color: overdue
          ? scheme.error
          : dueToday
          ? scheme.primary
          : scheme.onSurfaceVariant,
    );
    final clock = entry == null
        ? clockText(item.startsAt)
        : agendaClockLabel(entry);
    final caption = entry == null
        ? '${clockText(item.endsAt!)} 结束'
        : agendaTimeCaption(entry, now);
    final metadata = [
      item.kindLabel,
      if (entry?.source case final source?) source.label,
    ].join(' · ');

    Widget time({required bool inline}) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          clock,
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: 20,
            height: 1.2,
            color: timeColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (!inline && caption.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(caption, style: captionStyle),
        ],
      ],
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        CompletionText(
          item.title,
          completed: entry?.done == true,
          style: theme.textTheme.titleMedium?.copyWith(fontSize: 17),
        ),
        if (entry?.course.isNotEmpty == true) ...[
          const SizedBox(height: 5),
          Text(
            entry!.course,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        if (item.location.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            item.location,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 7),
        Text(metadata, style: theme.textTheme.bodySmall),
        if (showDate) ...[
          const SizedBox(height: 4),
          Text(
            agendaDateLabel(item.startsAt),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 330 ||
            MediaQuery.textScalerOf(context).scale(14) > 20;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppCorners.control,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!stacked) ...[
                    SizedBox(width: 76, child: time(inline: false)),
                    const SizedBox(width: 16),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (stacked) ...[
                          Wrap(
                            spacing: 10,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              time(inline: true),
                              if (caption.isNotEmpty)
                                Text(caption, style: captionStyle),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],
                        content,
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
