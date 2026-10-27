import 'dart:convert';

import 'package:html/parser.dart' as html;

import '../../agenda/deadline_source.dart';
import '../../agenda/model.dart';
import '../errors.dart';
import '../session.dart';

Future<List<AgendaEntry>> fetchLexueDeadlines(
  SchoolSession session,
  SchoolResponse page,
) async {
  final source = DeadlineSource.lexue;
  final sesskey = RegExp(r'''["']sesskey["']\s*:\s*["']([^"']+)["']''')
      .firstMatch(page.text)?[1];
  if (sesskey == null) throw const SessionExpired();
  final exported = await session.request(
    source.origin.resolve('/calendar/export.php'),
    form: {
      'sesskey': sesskey,
      '_qf__core_calendar_export_form': '1',
      'events[exportevents]': 'all',
      'period[timeperiod]': 'recentupcoming',
      'generateurl': '获取日历网址',
    },
    stopAtLogin: true,
  );
  final block = html.parse(exported.text).querySelector('.calendarurl')!;
  final address = RegExp(r'https://\S+').firstMatch(block.text)![0]!;
  final url = Uri.parse(address);
  if (url.host != source.host || url.userInfo.isNotEmpty) {
    throw const SchoolRequestError('乐学返回的日程地址无效。');
  }
  final calendar = await session.request(url, stopAtLogin: true);
  final entries = _parseLexueCalendar(calendar.text);
  final completed = await _completedLexueEvents(session, sesskey, entries);
  return [
    for (final entry in entries)
      entry.copyWith(done: completed.contains(entry.id)),
  ];
}

Future<Set<String>> _completedLexueEvents(
  SchoolSession session,
  String sesskey,
  List<AgendaEntry> entries,
) async {
  if (entries.isEmpty) return {};

  // Moodle's ICS UID is the calendar event ID followed by the site's hostname.
  final events = await _lexueAjax(session, sesskey, [
    for (final entry in entries)
      (
        method: 'core_calendar_get_calendar_event_by_id',
        args: {
          'eventid': int.parse(
            entry.id.substring('lexue-'.length).split('@').first,
          ),
        },
      ),
  ]);
  final modulesByEvent = {
    for (var index = 0; index < events.length; index++)
      if (events[index]['event']['instance'] case final int moduleId)
        entries[index].id: moduleId,
  };
  final moduleIds = modulesByEvent.values.toSet().toList();
  if (moduleIds.isEmpty) return {};

  // Read course-list fragments, which expose completion without viewing an activity.
  final modules = await _lexueAjax(session, sesskey, [
    for (final id in moduleIds)
      (method: 'core_course_get_module', args: {'id': id}),
  ]);
  final completedModules = <int>{};
  for (var index = 0; index < modules.length; index++) {
    final activity = html.parseFragment(modules[index] as String);
    final manuallyCompleted =
        activity.querySelector('[data-toggletype="manual:undo"]') != null;
    final conditions = activity.querySelectorAll(
      '[data-region="completionrequirements"] [role="listitem"]',
    );
    final automaticallyCompleted =
        conditions.isNotEmpty &&
        conditions.every(
          (condition) => condition.classes.contains('badge-success'),
        );

    if (manuallyCompleted || automaticallyCompleted) {
      completedModules.add(moduleIds[index]);
    }
  }
  return {
    for (final entry in modulesByEvent.entries)
      if (completedModules.contains(entry.value)) entry.key,
  };
}

Future<List<dynamic>> _lexueAjax(
  SchoolSession session,
  String sesskey,
  List<({String method, Map<String, Object> args})> calls,
) async {
  final response = await session.request(
    DeadlineSource.lexue.origin
        .resolve('/lib/ajax/service.php')
        .replace(queryParameters: {'sesskey': sesskey}),
    jsonBody: [
      for (final (index, call) in calls.indexed)
        {'index': index, 'methodname': call.method, 'args': call.args},
    ],
    headers: {
      'Accept': 'application/json',
      'X-Requested-With': 'XMLHttpRequest',
    },
    stopAtLogin: true,
  );
  final results = (jsonDecode(response.text) as List).cast<Map>();
  return [
    for (final result in results)
      if (result['error'] == true)
        throw SchoolRequestError(result['exception']['message'] as String)
      else
        result['data'],
  ];
}

List<AgendaEntry> _parseLexueCalendar(String calendar) {
  final unfolded = calendar.replaceAll(RegExp(r'\r?\n[ \t]'), '');
  final result = <AgendaEntry>[];
  for (final block in unfolded.split('BEGIN:VEVENT').skip(1)) {
    final properties = <String, ({String parameters, String value})>{};
    for (final line
        in block.split('END:VEVENT').first.split(RegExp(r'\r?\n'))) {
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      final key = line.substring(0, colon);
      properties[key.split(';').first] = (
        parameters: key,
        value: _unescapeCalendarText(line.substring(colon + 1)),
      );
    }
    final start = properties['DTSTART']!;
    final dateOnly = start.value.length == 8;
    final rawUrl = properties['URL']?.value;
    final taskUrl = rawUrl == null ? null : Uri.parse(rawUrl);
    result.add(
      AgendaEntry(
        id: 'lexue-${properties['UID']!.value}',
        title: properties['SUMMARY']!.value,
        kind: AgendaKind.deadline,
        startsAt: _calendarDate(start.value, start.parameters),
        allDay: dateOnly,
        notes: html
            .parse(properties['DESCRIPTION']?.value ?? '')
            .body!
            .text
            .trim(),
        course: properties['CATEGORIES']?.value ?? '',
        source: DeadlineSource.lexue,
        local: false,
        url:
            taskUrl != null &&
                taskUrl.scheme == 'https' &&
                taskUrl.host == DeadlineSource.lexue.host &&
                taskUrl.userInfo.isEmpty &&
                (taskUrl.path.startsWith('/mod/') ||
                    taskUrl.path.startsWith('/course/'))
            ? taskUrl
            : null,
      ),
    );
  }
  return result;
}

String _unescapeCalendarText(String value) => value.replaceAllMapped(
  RegExp(r'\\([nN,;\\])'),
  (match) => switch (match[1]) {
    'n' || 'N' => '\n',
    _ => match[1]!,
  },
);

DateTime _calendarDate(String value, String parameters) {
  final parsed = DateTime.parse(value);
  final date = DateTime.utc(
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
  );
  final timezone = parameters
      .split(';')
      .where((part) => part.startsWith('TZID='))
      .firstOrNull
      ?.substring(5)
      .replaceAll('"', '');
  if (parsed.isUtc || timezone == 'UTC') {
    return date.add(const Duration(hours: 8));
  }
  return date;
}
