import '../schedule/model.dart';
import 'deadline_source.dart';

enum AgendaKind {
  event('活动'),
  deadline('DDL'),
  exam('考试');

  const AgendaKind(this.label);
  final String label;
}

/// Times use the same Beijing wall-clock convention as campusNow().
class AgendaEntry {
  AgendaEntry({
    required this.id,
    required this.title,
    required this.kind,
    required this.startsAt,
    this.endsAt,
    this.allDay = false,
    this.location = '',
    this.notes = '',
    this.done = false,
    this.deleted = false,
    this.term,
    this.local = true,
    this.source,
    this.course = '',
    this.url,
  }) {
    if (id.isEmpty || title.trim().isEmpty) {
      throw const FormatException('日程标题或编号缺失');
    }
    if (kind != AgendaKind.deadline &&
        (endsAt == null || !endsAt!.isAfter(startsAt))) {
      throw const FormatException('结束时间必须晚于开始时间');
    }
    if (url != null &&
        (source == null ||
            url!.scheme != 'https' ||
            url!.host != source!.host ||
            url!.userInfo.isNotEmpty)) {
      throw const FormatException('作业链接不属于对应的来源平台');
    }
  }

  final String id;
  final String title;
  final AgendaKind kind;
  final DateTime startsAt;
  final DateTime? endsAt;
  final bool allDay;
  final String location;
  final String notes;
  final bool done;
  final bool deleted;
  final String? term;
  final bool local;
  final DeadlineSource? source;
  final String course;
  final Uri? url;

  bool get isDeadline => kind == AgendaKind.deadline;

  DateTime get dueAt =>
      allDay ? calendarDate(startsAt).add(const Duration(days: 1)) : startsAt;

  bool overdue(DateTime now) => isDeadline && !done && dueAt.isBefore(now);

  bool isFinished(DateTime now) => isDeadline ? done : !endsAt!.isAfter(now);

  bool occursOn(DateTime date) {
    final day = calendarDate(date);
    if (isDeadline) return calendarDate(startsAt) == day;
    return startsAt.isBefore(day.add(const Duration(days: 1))) &&
        endsAt!.isAfter(day);
  }

  String get timeLabel {
    if (allDay) return '全天';
    if (isDeadline) return '${clockText(startsAt)} 截止';
    final end = endsAt!;
    final sameDay = calendarDate(startsAt) == calendarDate(end);
    return '${clockText(startsAt)}–'
        '${sameDay ? '' : '${end.month}月${end.day}日 '}${clockText(end)}';
  }

  AgendaEntry copyWith({bool? done, bool? deleted}) => AgendaEntry(
    id: id,
    title: title,
    kind: kind,
    startsAt: startsAt,
    endsAt: endsAt,
    allDay: allDay,
    location: location,
    notes: notes,
    done: done ?? this.done,
    deleted: deleted ?? this.deleted,
    term: term,
    local: local,
    source: source,
    course: course,
    url: url,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'kind': kind.name,
    'startsAt': startsAt.toIso8601String(),
    'endsAt': endsAt?.toIso8601String(),
    'allDay': allDay,
    'location': location,
    'notes': notes,
    'done': done,
    'deleted': deleted,
    'term': term,
    'local': local,
    'source': source?.name,
    'course': course,
    'url': url?.toString(),
  };

  factory AgendaEntry.fromJson(Map<String, dynamic> json) => AgendaEntry(
    id: json['id'] as String,
    title: json['title'] as String,
    kind: AgendaKind.values.byName(json['kind'] as String),
    startsAt: DateTime.parse(json['startsAt'] as String),
    endsAt: json['endsAt'] == null
        ? null
        : DateTime.parse(json['endsAt'] as String),
    allDay: json['allDay'] as bool,
    location: json['location'] as String,
    notes: json['notes'] as String,
    done: json['done'] as bool,
    deleted: json['deleted'] as bool? ?? false,
    term: json['term'] as String?,
    local: json['local'] as bool,
    source: json['source'] == null
        ? null
        : DeadlineSource.values.byName(json['source'] as String),
    course: json['course'] as String? ?? '',
    url: json['url'] == null ? null : Uri.parse(json['url'] as String),
  );
}

String clockText(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

String agendaDateLabel(DateTime date) {
  final day = calendarDate(date);
  final today = calendarDate(campusNow());
  final relative = switch (day.difference(today).inDays) {
    0 => '今天 ',
    1 => '明天 ',
    -1 => '昨天 ',
    _ => '',
  };
  final year = date.year == today.year ? '' : '${date.year}年';
  return '$relative$year${date.month}月${date.day}日 ${weekdays[date.weekday - 1]}';
}
