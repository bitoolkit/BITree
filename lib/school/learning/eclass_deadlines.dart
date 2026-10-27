import '../../agenda/deadline_source.dart';
import '../../agenda/model.dart';
import '../errors.dart';
import '../session.dart';

Future<Map<String, dynamic>> _eclassJson(
  SchoolSession session,
  String path, {
  Object? body,
}) async {
  final response = await session.request(
    DeadlineSource.eclass.origin.resolve(path),
    jsonBody: body,
    headers: {
      'Accept': 'application/json',
      'X-Requested-With': 'XMLHttpRequest',
    },
    stopAtLogin: true,
  );
  if (response.text.trimLeft().startsWith('<')) throw const SessionExpired();
  return response.json;
}

Future<List<AgendaEntry>> fetchEclassDeadlines(SchoolSession session) async {
  final courses = <Map<String, dynamic>>[];
  var page = 1;
  while (true) {
    final response = await _eclassJson(
      session,
      '/api/my-courses',
      body: {
        'page': page,
        'page_size': 100,
        'fields': 'id,name',
        'conditions': {},
      },
    );
    final rows = (response['courses'] as List).cast<Map<String, dynamic>>();
    courses.addAll(rows);
    final pages = response['pages'] as num?;
    if (pages != null ? page >= pages : rows.length < 100) break;
    page++;
  }

  final result = <AgendaEntry>[];
  for (final course in courses) {
    final courseId = course['id'];
    final response = await _eclassJson(
      session,
      '/api/courses/$courseId/activities',
    );
    for (final task in (response['activities'] as List).cast<Map>()) {
      final homework =
          task['submit_times'] != null ||
          task['is_review_homework'] != null ||
          task['late_submission_count'] != null;
      if (task['type'] == 'material' || !homework) continue;
      final deadline = (task['end_time'] ?? task['visible_end_at']) as String?;
      if (deadline == null || deadline.isEmpty || deadline == 'null') continue;
      final id = task['id'].toString();
      final detail = await _eclassJson(session, '/api/activities/$id');
      result.add(
        AgendaEntry(
          id: 'eclass-$id',
          title: task['title'] as String? ?? '未命名作业',
          kind: AgendaKind.deadline,
          startsAt: _eclassDate(deadline),
          done: (detail['user_submit_count'] as num) > 0,
          course: course['name'] as String,
          source: DeadlineSource.eclass,
          local: false,
          url: DeadlineSource.eclass.origin.resolve(
            '/course/$courseId/learning-activity/full-screen#/$id',
          ),
        ),
      );
    }
  }
  return result;
}

DateTime _eclassDate(String value) {
  final parsed = DateTime.parse(value.replaceAll('/', '-'));
  if (RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
    return parsed.toUtc().add(const Duration(hours: 8));
  }
  return DateTime.utc(
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
  );
}
