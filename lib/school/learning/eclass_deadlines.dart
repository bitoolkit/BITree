import '../../agenda/deadline_source.dart';
import '../../agenda/model.dart';
import '../../core/json.dart';
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
    final rows = [
      for (final value in jsonListField(response, 'courses'))
        jsonObject(value, 'courses[]'),
    ];
    courses.addAll(rows);
    final pagesValue = response['pages'];
    final pages = pagesValue == null
        ? null
        : pagesValue is num
        ? pagesValue
        : throw const FormatException('pages 格式不正确');
    if (pages != null ? page >= pages : rows.length < 100) break;
    page++;
  }

  final result = <AgendaEntry>[];
  for (final course in courses) {
    final courseId = _identifier(course['id'], 'course.id');
    final coursePath = Uri.encodeComponent(courseId);
    final response = await _eclassJson(
      session,
      '/api/courses/$coursePath/activities',
    );
    for (final value in jsonListField(response, 'activities')) {
      final task = jsonObject(value, 'activities[]');
      final homework =
          task['submit_times'] != null ||
          task['is_review_homework'] != null ||
          task['late_submission_count'] != null;
      if (task['type'] == 'material' || !homework) continue;
      final deadline = jsonStringOrNull(
        task['end_time'] ?? task['visible_end_at'],
        'activity deadline',
      );
      if (deadline == null || deadline.isEmpty || deadline == 'null') continue;
      final id = _identifier(task['id'], 'activity.id');
      final detail = await _eclassJson(
        session,
        '/api/activities/${Uri.encodeComponent(id)}',
      );
      result.add(
        AgendaEntry(
          id: 'eclass-$id',
          title: jsonStringOrNull(task['title'], 'activity.title') ?? '未命名作业',
          kind: AgendaKind.deadline,
          startsAt: _eclassDate(deadline),
          done:
              (jsonIntOrNull(
                    detail['user_submit_count'],
                    'user_submit_count',
                  ) ??
                  0) >
              0,
          course: jsonStringField(course, 'name'),
          source: DeadlineSource.eclass,
          local: false,
          url: DeadlineSource.eclass.origin.resolve(
            '/course/$coursePath/learning-activity/full-screen#/$id',
          ),
        ),
      );
    }
  }
  return result;
}

String _identifier(Object? value, String field) {
  if (value is String && value.isNotEmpty) return value;
  if (value is int) return '$value';
  throw FormatException('$field 格式不正确');
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
