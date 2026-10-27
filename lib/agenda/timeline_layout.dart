import 'model.dart';

/// Lane bounds are expressed only in campus time, never in screen pixels.
/// DDLs reserve four days solely for packing; their painted width is separate.
class AgendaTimelinePlacement {
  const AgendaTimelinePlacement({
    required this.entry,
    required this.lane,
    required this.start,
    required this.end,
    required this.layoutStart,
    required this.layoutEnd,
  });

  final AgendaEntry entry;
  final int lane;
  final DateTime start;
  final DateTime end;
  final DateTime layoutStart;
  final DateTime layoutEnd;
}

/// Pack true event intervals and fixed four-day DDL reservations. No zoom,
/// viewport width or pixel gap participates, so zooming cannot change lanes.
List<AgendaTimelinePlacement> layoutAgendaTimeline(
  Iterable<AgendaEntry> entries,
) {
  final intervals = [
    for (final entry in entries.where((entry) => !entry.deleted))
      (
        entry: entry,
        start: entry.isDeadline
            ? entry.dueAt.subtract(const Duration(days: 4))
            : entry.startsAt,
        end: entry.isDeadline ? entry.dueAt : entry.endsAt!,
      ),
  ]..sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      if (byStart != 0) return byStart;
      final byEnd = a.end.compareTo(b.end);
      return byEnd != 0 ? byEnd : a.entry.id.compareTo(b.entry.id);
    });
  final laneEnds = <DateTime>[];
  final result = <AgendaTimelinePlacement>[];
  for (final interval in intervals) {
    var lane = laneEnds.indexWhere(
      (end) => !interval.start.isBefore(end),
    );
    if (lane < 0) {
      lane = laneEnds.length;
      laneEnds.add(interval.end);
    } else {
      laneEnds[lane] = interval.end;
    }
    result.add(AgendaTimelinePlacement(
      entry: interval.entry,
      lane: lane,
      start: interval.start,
      end: interval.end,
      layoutStart: interval.start,
      layoutEnd: interval.end,
    ));
  }
  return result;
}
