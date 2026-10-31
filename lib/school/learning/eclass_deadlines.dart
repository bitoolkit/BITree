import '../../agenda/deadline_source.dart';
import '../../agenda/model.dart';
import '../../core/async/cancelable_request.dart';
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
  final tasks = await _courseTasks(session);

  final result = <AgendaEntry>[];
  Object? firstFailure;
  StackTrace? firstStack;
  for (final task in tasks) {
    try {
      result.add(
        AgendaEntry(
          id: 'eclass-${task.id}',
          title: task.title,
          kind: AgendaKind.deadline,
          startsAt: _eclassDate(task.deadline),
          done: await _submitted(session, task.id),
          course: task.course,
          source: DeadlineSource.eclass,
          local: false,
          url: DeadlineSource.eclass.origin.resolve(
            '/course/${Uri.encodeComponent(task.courseId)}'
            '/learning-activity/full-screen#/${task.id}',
          ),
        ),
      );
    } on RequestCancelled {
      rethrow;
    } on SessionExpired {
      rethrow;
    } on Exception catch (error, stack) {
      firstFailure ??= error;
      firstStack ??= stack;
    }
  }
  if (result.isEmpty && firstFailure != null) {
    Error.throwWithStackTrace(firstFailure, firstStack!);
  }
  return result;
}

Future<List<_EclassTask>> _courseTasks(SchoolSession session) async {
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

  final result = <_EclassTask>[];
  final activityIds = <String>{};
  Object? firstFailure;
  StackTrace? firstStack;
  for (final course in courses) {
    try {
      final courseId = _identifier(course['id'], 'course.id');
      final courseName = jsonStringField(course, 'name');
      final response = await _eclassJson(
        session,
        '/api/courses/${Uri.encodeComponent(courseId)}/activities',
      );
      for (final value in jsonListField(response, 'activities')) {
        final task = _taskFromActivity(
          jsonObject(value, 'activities[]'),
          courseId: courseId,
          courseName: courseName,
        );
        if (task != null && activityIds.add(task.id)) result.add(task);
      }
    } on RequestCancelled {
      rethrow;
    } on SessionExpired {
      rethrow;
    } on Exception catch (error, stack) {
      firstFailure ??= error;
      firstStack ??= stack;
    }
  }
  if (result.isEmpty && firstFailure != null) {
    Error.throwWithStackTrace(firstFailure, firstStack!);
  }
  return result;
}

_EclassTask? _taskFromActivity(
  Map<String, dynamic> task, {
  required String courseId,
  required String courseName,
}) {
  if (task['type'] == 'material') return null;
  final deadline = _deadline(task);
  if (deadline == null) return null;
  return (
    id: _identifier(task['id'], 'activity.id'),
    title: jsonStringOrNull(task['title'], 'activity.title') ?? '未命名作业',
    courseId: courseId,
    course: courseName,
    deadline: deadline,
  );
}

String? _deadline(Map<String, dynamic> task) {
  final deadline = jsonStringOrNull(
    task['end_time'] ?? task['visible_end_at'],
    'activity deadline',
  );
  return deadline == null || deadline.isEmpty || deadline == 'null'
      ? null
      : deadline;
}

Future<bool> _submitted(SchoolSession session, String id) async {
  try {
    final detail = await _eclassJson(
      session,
      '/api/activities/${Uri.encodeComponent(id)}',
    );
    return (jsonIntOrNull(detail['user_submit_count'], 'user_submit_count') ??
            0) >
        0;
  } on RequestCancelled {
    rethrow;
  } on SessionExpired {
    rethrow;
  } on Exception {
    return false;
  }
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

typedef _EclassTask = ({
  String id,
  String title,
  String courseId,
  String course,
  String deadline,
});
