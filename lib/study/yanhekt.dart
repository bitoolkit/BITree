import 'package:html/parser.dart';

import '../core/async/cancelable_request.dart';
import '../school/errors.dart';
import '../school/login.dart';
import '../school/network.dart';
import '../school/session.dart';
import '../school/storage.dart';
import '../school/verification.dart';
import 'model.dart';
import 'playback.dart';

/// Yanhekt's course API. The existing CAS implementation owns school credentials.
class YanhektRepository {
  YanhektRepository(this._storage);
  final SchoolStorage _storage;
  static final origin = Uri.https('aita.yanhekt.cn');

  Future<T> _read<T>(
    VerifySchoolLogin verify,
    CancellationToken cancellation,
    Future<T> Function(SchoolSession, Map<String, dynamic>, String) operation,
  ) async {
    final session = SchoolSession(
      network: SchoolNetwork.campus,
      storage: _storage,
    );
    final detach = cancellation.onCancel(session.close);
    try {
      cancellation.check();
      var account = await _authenticate(session, verify);
      try {
        return await operation(session, account.profile, account.token);
      } on SessionExpired {
        account = await _authenticate(session, verify, renew: true);
        return await operation(session, account.profile, account.token);
      }
    } finally {
      detach();
      session.close();
    }
  }

  Future<String?> _token() async {
    final cookies = await _storage.cookiesFor(SchoolNetwork.campus, origin);
    final raw = cookies
        .where((cookie) => cookie.name == '_token')
        .firstOrNull
        ?.value;
    return raw == null
        ? null
        : RegExp(r'eyJ[\w-]+\.[\w-]+\.[\w-]+')
              .firstMatch(Uri.decodeComponent(raw))?[0];
  }

  Future<Map<String, dynamic>?> _profile(
    SchoolSession session,
    String token,
  ) async {
    final response = await session.request(
      origin.resolve('/userapi/v1/infosimple'),
      headers: {'Authorization': 'Bearer $token'},
      checkStatus: false,
    );
    if (response.status != 200) return null;
    final body = response.json;
    if (body['code'] != 200) return null;
    return body['params'] as Map<String, dynamic>;
  }

  Future<({Map<String, dynamic> profile, String token})> _authenticate(
    SchoolSession session,
    VerifySchoolLogin verify, {
    bool renew = false,
  }) async {
    var token = await _token();
    if (!renew && token != null) {
      final profile = await _profile(session, token);
      if (profile != null) return (profile: profile, token: token);
    }

    final query = {
      'r': 'auth/login',
      'auType': '',
      'tenant_code': '21',
      'forward': '${origin.origin}/course',
    };
    final entry = origin.resolve('/casapi/index.php');
    await session.request(
      entry.replace(queryParameters: query),
      followRedirects: false,
    );
    final redirect = await session.request(
      entry.replace(queryParameters: {...query, 'auType': 'cas'}),
      followRedirects: false,
    );
    final service = Uri.parse(redirect.location!.queryParameters['service']!);
    await SchoolLogin(session, verify).signInTo(service);
    token = await _token();
    if (token == null) throw const SessionExpired();
    final profile = await _profile(session, token);
    if (profile == null) throw const SessionExpired();
    return (profile: profile, token: token);
  }

  Future<Map<String, dynamic>> _json(
    SchoolSession session,
    String token,
    String path, [
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
  ]) async {
    final response = await session.request(
      origin.resolve(path).replace(queryParameters: query),
      headers: {
        'Authorization': 'Bearer $token',
        'Referer': '${origin.origin}/',
        ...headers,
      },
      stopAtLogin: true,
    );
    return response.json;
  }

  Future<Map<String, dynamic>> _courseApi(
    SchoolSession session,
    String token,
    String path, [
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
  ]) async {
    final json = await _json(session, token, path, query, headers);
    if (![0, 10002].contains(json['code'])) {
      if ([401, 403].contains(json['code'])) throw const SessionExpired();
      final message = [json['msg'], json['message']]
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .firstOrNull;
      throw SchoolRequestError(
        message ?? '延河课堂请求失败（错误码 ${json['code']}），请稍后重试。',
      );
    }
    return json;
  }

  Future<List<StudyCourse>> courses(
    VerifySchoolLogin verify,
    CancellationToken cancellation, {
    String? search,
    int page = 1,
  }) => _read(verify, cancellation, (session, profile, token) async {
    String title(Object? text) => parseFragment('$text').text ?? '';
    if (search != null) {
      final tenant = '${profile['tenant_id']}';
      final body = await _courseApi(
        session,
        token,
        '/courseapi/v3/multi-search/get-course-list',
        {'tenant': tenant, 'title': search, 'page': '$page', 'per_page': '30'},
        {'tenant-id': tenant},
      );
      return [
        for (final row in (body['data'] as Map)['list'] as List)
          StudyCourse(
            id: '${row['id']}',
            title: title(row['title']),
            teacher: row['realname'] as String? ?? '',
            term: row['term_name'] as String? ?? '',
            lectureCount: ((row['progress'] as Map?)?['subjectNum'] as num?)
                ?.toInt(),
          ),
      ];
    }
    final courses = <StudyCourse>[];
    var currentPage = 1;
    while (true) {
      cancellation.check();
      // Passport returns params.result; it does not use the course API's code.
      final body = await _json(
        session,
        token,
        '/vlabpassportapi/v1/account-profile/course',
        {
          'force_mycourse': '1',
          'nowpage': '${currentPage++}',
          'per-page': '100',
        },
      );
      final result = (body['params'] as Map)['result'] as Map;
      final rows = result['data'] as List;
      courses.addAll([
        for (final row in rows)
          StudyCourse(
            id: '${row['Id']}',
            title: title(row['Title']),
            teacher: row['Teacher'] as String? ?? '',
            term: row['TermName'] as String? ?? '',
            lectureCount: ((row['progress'] as Map?)?['subjectNum'] as num?)
                ?.toInt(),
          ),
      ]);
      if (rows.isEmpty || courses.length >= (result['total'] as num)) {
        return courses;
      }
    }
  });

  Future<StudyCourse> course(
    String id,
    VerifySchoolLogin verify,
    CancellationToken cancellation,
  ) => _read(verify, cancellation, (session, profile, token) async {
    final result = await _courseApi(
      session,
      token,
      '/courseapi/v3/multi-search/get-course-detail',
      {'course_id': id},
    );
    final data = result['data'] as Map<String, dynamic>;
    final lectures = <StudyLecture>[];
    var lectureCount = 0;
    void visit(Object? node) {
      if (node is Map) {
        if (node.containsKey('sub_title')) {
          lectureCount++;
          lectures.add(
            StudyLecture(
              id: '${node['id']}',
              title: node['sub_title'] as String,
              startsAt: DateTime.fromMillisecondsSinceEpoch(
                int.parse('${node['class_begin']}') * 1000,
              ),
              endsAt: DateTime.fromMillisecondsSinceEpoch(
                int.parse('${node['class_over']}') * 1000,
              ),
              status: StudyLectureStatus.fromYanhekt(node['sub_status']),
            ),
          );
        } else {
          for (final item in node.values) {
            visit(item);
          }
        }
      } else if (node is List) {
        for (final item in node) {
          visit(item);
        }
      }
    }

    visit(data['sub_list']);
    lectures.sort((a, b) => b.startsAt!.compareTo(a.startsAt!));
    return StudyCourse(
      id: id,
      title: data['title'] as String,
      teacher: data['realname'] as String? ?? '',
      term: data['term_name'] as String? ?? '',
      lectures: lectures,
      lectureCount: lectureCount,
    );
  });

  Future<LectureStreams> streams(
    String course,
    String lecture,
    VerifySchoolLogin verify,
    CancellationToken cancellation,
  ) => _read(verify, cancellation, (session, profile, token) async {
    final body = await _courseApi(
      session,
      token,
      '/courseapi/v3/portal-home-setting/get-sub-info',
      {'course_id': course, 'sub_id': lecture},
    );
    final data = body['data'] as Map<String, dynamic>;
    final status = StudyLectureStatus.fromYanhekt(data['sub_status']);
    final urls = <String, Uri>{};
    if (status == StudyLectureStatus.live) {
      final live = data['live_url'] as Map;
      for (final (field, kind) in [
        ('output', 'classroom'),
        ('output_ppt', 'screen'),
      ]) {
        final url = (live[field] as Map?)?['m3u8'] as String?;
        if (url != null && url.isNotEmpty) urls[kind] = Uri.parse(url);
      }
    } else if (status == StudyLectureStatus.recorded) {
      final raw = data['video_list'];
      final videos = raw is Map ? raw.values : raw as List? ?? [];
      for (final video in videos) {
        if ('${video['status']}' != '2') continue;
        final kind = switch ('${video['type']}') {
          '2' => 'screen',
          '3' => 'classroom',
          _ => null,
        };
        if (kind != null) {
          urls[kind] = Uri.parse(video['preview_url'] as String);
        }
      }
    }
    return LectureStreams(
      urls: urls,
      duration: Duration(
        milliseconds: status == StudyLectureStatus.recorded
            ? (double.parse('${data['duration']}') * 1000).round()
            : 0,
      ),
      status: status,
      signing: status == StudyLectureStatus.recorded
          ? (
              user: '${profile['id']}',
              tenant: '${profile['tenant_id']}',
              phone: '${profile['phone']}',
            )
          : null,
    );
  });

  Future<List<StudyBroadcast>> broadcasts(
    DateTime date,
    VerifySchoolLogin verify,
    CancellationToken cancellation,
  ) => _read(verify, cancellation, (session, profile, token) async {
    final day =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final body = await _json(
      session,
      token,
      '/courseapi/v2/schedule/get-week-schedules',
      {
        'user_id': '${profile['id']}',
        'tenant_id': '${profile['tenant_id']}',
        'start_at': day,
        'end_at': day,
      },
    );
    final result = body['result'] as Map;
    if (result['code'] == 400 && result['msg'] == '课表为空') return [];
    if ([401, 403].contains(result['code'])) throw const SessionExpired();
    if (result['code'] != 200) {
      throw SchoolRequestError(result['msg'] as String);
    }
    return [
      for (final day in result['list'] as List)
        for (final row in day['course'] as List)
          StudyBroadcast(
            course: StudyCourse(
              id: '${row['course_id']}',
              title: row['course_title'] as String,
              teacher: row['lecturer_name'] as String? ?? '',
            ),
            lecture: StudyLecture(
              id: '${row['id']}',
              title: row['course_title'] as String,
              startsAt: DateTime.fromMillisecondsSinceEpoch(
                int.parse('${row['start_at']}') * 1000,
              ),
              endsAt: DateTime.fromMillisecondsSinceEpoch(
                int.parse('${row['end_at']}') * 1000,
              ),
              status: StudyLectureStatus.fromYanhekt(row['status']),
            ),
          ),
    ];
  });

  Future<List<TranscriptSegment>> transcript(
    String lecture,
    VerifySchoolLogin verify,
    CancellationToken cancellation,
  ) => _read(verify, cancellation, (session, profile, token) async {
    final body = await _courseApi(
      session,
      token,
      '/courseapi/v3/web-socket/search-trans-result',
      {'sub_id': lecture, 'format': 'json'},
    );
    final segments = <int, TranscriptSegment>{};
    for (final group in body['list'] as List? ?? []) {
      for (final row in group['all_content'] as List) {
        final start = Duration(
          milliseconds: (double.parse('${row['BeginSec']}') * 1000).round(),
        );
        segments[start.inMilliseconds] = TranscriptSegment(
          start,
          Duration(
            milliseconds: (double.parse('${row['EndSec']}') * 1000).round(),
          ),
          row['Text'] as String,
        );
      }
    }
    return segments.values.toList()..sort((a, b) => a.start.compareTo(b.start));
  });
}
