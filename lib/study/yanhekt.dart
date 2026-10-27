import 'dart:convert';

import 'package:html/parser.dart';
import 'package:pointycastle/export.dart';

import '../core/async/cancelable_request.dart';
import '../school/errors.dart';
import '../school/login.dart';
import '../school/network.dart';
import '../school/session.dart';
import '../school/storage.dart';
import '../school/verification.dart';
import 'model.dart';

class LectureStreams {
  const LectureStreams({
    required this.urls,
    required this.duration,
    required this.user,
    required this.tenant,
    required this.phone,
  });
  final Map<String, Uri> urls;
  final Duration duration;
  final String user;
  final String tenant;
  final String phone;

  Uri sign(Uri url, {DateTime? at}) {
    if (!url.path.startsWith('/play/')) return url;
    final seconds = ((at ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000)
        .toString();
    final input = utf8.encode(
      '${url.path}$user$tenant${phone.split('').reversed.join()}$seconds',
    );
    final digest = MD5Digest()
        .process(input)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return url.replace(queryParameters: {'t': '$user-$seconds-$digest'});
  }
}

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
      String? token;
      Future<void> readToken() async {
        final cookies = await _storage.cookiesFor(SchoolNetwork.campus, origin);
        final raw = cookies
            .where((cookie) => cookie.name == '_token')
            .firstOrNull
            ?.value;
        token = raw == null
            ? null
            : RegExp(r'eyJ[\w-]+\.[\w-]+\.[\w-]+')
                  .firstMatch(Uri.decodeComponent(raw))?[0];
      }

      await readToken();
      SchoolResponse? profile;
      if (token != null) {
        profile = await session.request(
          origin.resolve('/userapi/v1/infosimple'),
          headers: {'Authorization': 'Bearer $token'},
          checkStatus: false,
        );
      }
      if (profile == null ||
          profile.status != 200 ||
          profile.json['code'] != 200) {
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
        final service = Uri.parse(
          redirect.location!.queryParameters['service']!,
        );
        await SchoolLogin(session, verify).signInTo(service);
        await readToken();
        if (token == null) throw const SessionExpired();
        profile = await session.request(
          origin.resolve('/userapi/v1/infosimple'),
          headers: {'Authorization': 'Bearer $token'},
        );
      }
      return await operation(
        session,
        profile.json['params'] as Map<String, dynamic>,
        token!,
      );
    } finally {
      detach();
      session.close();
    }
  }

  Future<Map<String, dynamic>> _get(
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
    );
    final json = response.json;
    if (![0, 200, 10002].contains(json['code'])) {
      if ([401, 403].contains(json['code'])) throw const SessionExpired();
      throw SchoolRequestError(
        '${json['msg'] ?? json['message'] ?? '延河课堂请求失败'}',
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
      final body = await _get(
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
          ),
      ];
    }
    final courses = <StudyCourse>[];
    var currentPage = 1;
    while (true) {
      cancellation.check();
      final body = await _get(
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
    final result = await _get(
      session,
      token,
      '/courseapi/v3/multi-search/get-course-detail',
      {'course_id': id},
    );
    final data = result['data'] as Map<String, dynamic>;
    final lectures = <StudyLecture>[];
    void visit(Object? node) {
      if (node is Map) {
        if (node.containsKey('sub_title')) {
          if ('${node['playback_status']}' == '1') {
            lectures.add(
              StudyLecture(
                id: '${node['id']}',
                title: node['sub_title'] as String,
                startsAt: DateTime.fromMillisecondsSinceEpoch(
                  int.parse('${node['class_begin']}') * 1000,
                ),
              ),
            );
          }
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
    );
  });

  Future<LectureStreams> streams(
    String course,
    String lecture,
    VerifySchoolLogin verify,
    CancellationToken cancellation,
  ) => _read(verify, cancellation, (session, profile, token) async {
    final body = await _get(
      session,
      token,
      '/courseapi/v3/portal-home-setting/get-sub-info',
      {'course_id': course, 'sub_id': lecture},
    );
    final data = body['data'] as Map<String, dynamic>;
    final urls = <String, Uri>{};
    final raw = data['video_list'];
    final videos = raw is Map ? raw.values : raw as List? ?? [];
    for (final video in videos) {
      if ('${video['status']}' != '2') continue;
      final kind = switch ('${video['type']}') {
        '2' => 'screen',
        '3' => 'classroom',
        _ => null,
      };
      if (kind != null) urls[kind] = Uri.parse(video['preview_url'] as String);
    }
    return LectureStreams(
      urls: urls,
      duration: Duration(
        milliseconds: (double.parse('${data['duration']}') * 1000).round(),
      ),
      user: '${profile['id']}',
      tenant: '${profile['tenant_id']}',
      phone: '${profile['phone']}',
    );
  });

  Future<List<TranscriptSegment>> transcript(
    String lecture,
    VerifySchoolLogin verify,
    CancellationToken cancellation,
  ) => _read(verify, cancellation, (session, profile, token) async {
    final body = await _get(
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
