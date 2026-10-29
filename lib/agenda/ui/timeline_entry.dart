import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../schedule/model.dart';
import '../model.dart';
import 'timeline_colors.dart';

/// Renders entry content independently of timeline coordinates and lane packing.
class AgendaTimelineEntry extends StatelessWidget {
  const AgendaTimelineEntry({
    super.key,
    required this.entry,
    required this.now,
    required this.barWidth,
    required this.deadlineWidth,
    required this.onTap,
  });

  final AgendaEntry entry;
  final DateTime now;
  final double barWidth;
  final double deadlineWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = agendaTimelineColors(context, entry, now);
    final scale = math.max(
      1.0,
      MediaQuery.textScalerOf(context).scale(14) / 14,
    );
    final date = entry.startsAt;
    final caption = _caption(entry);
    final radius = entry.isDeadline ? null : BorderRadius.circular(8);
    final description =
        '${entry.kind.label}，${entry.title}，'
        '${date.year}年${date.month}月${date.day}日 ${caption.replaceAll('\n', ' ')}'
        '${entry.location.isEmpty ? '' : '，${entry.location}'}';
    final kindIcon = switch (entry.kind) {
      AgendaKind.event => Icons.event_outlined,
      AgendaKind.exam => Icons.school_outlined,
      AgendaKind.deadline => Icons.flag_outlined,
    };
    final source = entry.course.isNotEmpty
        ? entry.course
        : entry.source?.label ?? entry.kind.label;
    final title = Text(
      entry.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: entry.isDeadline ? TextAlign.right : TextAlign.left,
      style: TextStyle(
        fontSize: 14,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: colors.text,
        decoration: entry.done ? TextDecoration.lineThrough : null,
      ),
    );

    return Semantics(
      button: true,
      label: description,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Tooltip(
          message: _preview(entry, now),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  key: ValueKey(('agenda-timeline-bar', entry.id)),
                  width: barWidth,
                  height: double.infinity,
                  child: Ink(
                    decoration: BoxDecoration(
                      color: entry.isDeadline ? null : colors.fill,
                      gradient: entry.isDeadline
                          ? LinearGradient(
                              colors: [
                                colors.fill.withValues(alpha: 0),
                                colors.fill,
                                colors.fill,
                              ],
                              stops: const [0, 0.35, 1],
                            )
                          : null,
                      borderRadius: radius,
                    ),
                    // Ink includes border widths in its padding. Paint the
                    // outline separately so it never reduces the text space.
                    child: DecoratedBox(
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        border: entry.isDeadline
                            ? Border(
                                right: BorderSide(
                                  color: colors.accent,
                                  width: 3,
                                ),
                              )
                            : Border.all(color: colors.accent),
                      ),
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: entry.isDeadline ? deadlineWidth * 0.37 : 8,
                          right: 8,
                          top: 4,
                          bottom: 4,
                        ),
                        child: barWidth < 48
                            ? const SizedBox.shrink()
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: entry.isDeadline
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  if (entry.isDeadline)
                                    title
                                  else
                                    Row(
                                      children: [
                                        Icon(
                                          kindIcon,
                                          size: 13 * scale,
                                          color: colors.text,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(child: title),
                                      ],
                                    ),
                                  if (entry.isDeadline)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          entry.done
                                              ? Icons.check_circle_outline
                                              : entry.overdue(now)
                                              ? Icons.warning_amber_rounded
                                              : kindIcon,
                                          size: 13 * scale,
                                          color: colors.text,
                                        ),
                                        const SizedBox(width: 3),
                                        Flexible(
                                          child: Text(
                                            source,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              height: 1.1,
                                              color: colors.text,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  const SizedBox(height: 2),
                                  Text(
                                    caption,
                                    maxLines: entry.isDeadline ? 1 : 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: entry.isDeadline
                                        ? TextAlign.right
                                        : TextAlign.left,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.2,
                                      fontWeight: FontWeight.w600,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                      color: colors.accent,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _day(DateTime date) => '${date.month}/${date.day}';

String _caption(AgendaEntry entry) {
  if (entry.isDeadline) {
    return entry.allDay ? '全天截止' : '${clockText(entry.dueAt)} 截止';
  }
  final end = entry.endsAt!;
  if (entry.allDay) {
    final lastDay = end.subtract(const Duration(days: 1));
    return calendarDate(lastDay) == calendarDate(entry.startsAt)
        ? '全天'
        : '${_day(entry.startsAt)}–${_day(lastDay)}\n全天';
  }
  if (calendarDate(entry.startsAt) == calendarDate(end)) {
    return '${clockText(entry.startsAt)}–${clockText(end)}';
  }
  return '${_day(entry.startsAt)} ${clockText(entry.startsAt)}\n'
      '→ ${_day(end)} ${clockText(end)}';
}

String _fullDate(DateTime date) =>
    '${dateText(date)} ${weekdays[date.weekday - 1]}';
String _fullTime(DateTime date) => '${_fullDate(date)} ${clockText(date)}';

String _preview(AgendaEntry entry, DateTime now) => [
  '${entry.kind.label} · ${entry.title}',
  if (entry.isDeadline)
    entry.allDay
        ? '截止：${_fullDate(entry.startsAt)} 当天结束前'
        : '截止：${_fullTime(entry.dueAt)}'
  else if (entry.allDay) ...[
    '开始：${_fullDate(entry.startsAt)} 全天',
    '结束：${_fullDate(entry.endsAt!.subtract(const Duration(days: 1)))} 全天',
  ] else ...[
    '开始：${_fullTime(entry.startsAt)}',
    '结束：${_fullTime(entry.endsAt!)}',
  ],
  if (entry.course.isNotEmpty) '课程：${entry.course}',
  if (entry.location.isNotEmpty) '地点：${entry.location}',
  if (entry.done)
    '状态：已完成'
  else if (entry.overdue(now))
    '状态：已逾期'
  else if (entry.isFinished(now))
    '状态：已结束',
].join('\n');
