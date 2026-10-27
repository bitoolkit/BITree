import 'model.dart';

const _microsecondsPerHour = Duration.microsecondsPerSecond * 3600;

/// Visual bounds and the (possibly larger) interval reserved in a lane.
/// DDLs have no real start: three days are reserved solely for packing.
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

/// Pack entries in deterministic lanes. Reserve both the three-day virtual DDL
/// interval and its fixed-width visible bar, so neither can collide at any zoom.
/// Dates keep the same campus wall-clock convention as [AgendaEntry].
List<AgendaTimelinePlacement> layoutAgendaTimeline(
  Iterable<AgendaEntry> entries, {
  required double pixelsPerHour,
  double deadlineWidth = 180,
  double gap = 10,
}) {
  assert(pixelsPerHour > 0);
  assert(deadlineWidth > 0);
  assert(gap >= 0);
  final deadlineDuration = Duration(
    microseconds: (deadlineWidth / pixelsPerHour * _microsecondsPerHour).ceil(),
  );
  final separation = Duration(
    microseconds: (gap / pixelsPerHour * _microsecondsPerHour).ceil(),
  );
  final intervals = [
    for (final entry in entries.where((entry) => !entry.deleted))
      _interval(entry, deadlineDuration),
  ]..sort((a, b) {
      final byStart = a.layoutStart.compareTo(b.layoutStart);
      if (byStart != 0) return byStart;
      final byEnd = a.end.compareTo(b.end);
      return byEnd != 0 ? byEnd : a.entry.id.compareTo(b.entry.id);
    });
  final laneEnds = <DateTime>[];
  final result = <AgendaTimelinePlacement>[];
  for (final interval in intervals) {
    var lane = laneEnds.indexWhere(
      (end) => !interval.layoutStart.isBefore(end),
    );
    final reservedEnd = interval.end.add(separation);
    if (lane < 0) {
      lane = laneEnds.length;
      laneEnds.add(reservedEnd);
    } else {
      laneEnds[lane] = reservedEnd;
    }
    result.add(AgendaTimelinePlacement(
      entry: interval.entry,
      lane: lane,
      start: interval.start,
      end: interval.end,
      layoutStart: interval.layoutStart,
      layoutEnd: interval.end,
    ));
  }
  return result;
}

({AgendaEntry entry, DateTime start, DateTime end, DateTime layoutStart})
_interval(AgendaEntry entry, Duration deadlineDuration) {
  if (!entry.isDeadline) {
    return (
      entry: entry,
      start: entry.startsAt,
      end: entry.endsAt!,
      layoutStart: entry.startsAt,
    );
  }
  final end = entry.dueAt;
  final visualStart = end.subtract(deadlineDuration);
  final virtualStart = end.subtract(const Duration(days: 3));
  return (
    entry: entry,
    start: visualStart,
    end: end,
    layoutStart: visualStart.isBefore(virtualStart) ? visualStart : virtualStart,
  );
}
