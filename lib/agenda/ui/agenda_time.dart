import '../../schedule/model.dart';
import '../model.dart';

String agendaClockLabel(AgendaEntry entry) =>
    entry.allDay ? '全天' : clockText(entry.startsAt);

String agendaTimeCaption(AgendaEntry entry, DateTime now) {
  if (entry.isDeadline) {
    if (entry.done) return '已完成';
    return entry.overdue(now) ? '已逾期' : '截止';
  }
  if (entry.isFinished(now)) return '已结束';
  if (entry.allDay) return '';
  final end = entry.endsAt!;
  final date = calendarDate(entry.startsAt) == calendarDate(end)
      ? ''
      : '${end.month}月${end.day}日 ';
  return '$date${clockText(end)} 结束';
}
