import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart';

import '../core/async/cancelable_request.dart';
import '../school/errors.dart';
import '../school/session.dart';
import 'model.dart';
import 'playback.dart';

class LegacyLive {
  const LegacyLive({
    required this.id,
    required this.title,
    required this.location,
    required this.startsAt,
    required this.endsAt,
    required this.status,
  });
  final String id;
  final String title;
  final String location;
  final DateTime startsAt;
  final DateTime endsAt;
  final StudyLectureStatus status;
}

/// The original www.yanhekt.cn live catalog is public and has its own IDs.
class LegacyYanhektRepository {
  static final origin = Uri.https('cbiz.yanhekt.cn');

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> query,
    CancellationToken cancellation,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    final detach = cancellation.onCancel(() => client.close(force: true));
    try {
      cancellation.check();
      final request = await client.getUrl(
        origin.resolve(path).replace(queryParameters: query),
      );
      for (final entry in {
        'Origin': 'https://www.yanhekt.cn',
        'Referer': 'https://www.yanhekt.cn/',
        'Xdomain-Client': 'web_user',
        'Xclient-Version': 'v1',
        'Xclient-Signature': '72b77856f6df3f563ab6e658631cac3d',
        'Xclient-Timestamp': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
        'User-Agent': SchoolSession.userAgent,
      }.entries) {
        request.headers.set(entry.key, entry.value);
      }
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw SchoolRequestError('旧版延河课堂请求失败（HTTP ${response.statusCode}）');
      }
      final body = jsonDecode(
        await utf8.decoder
            .bind(response)
            .join()
            .timeout(const Duration(seconds: 30)),
      ) as Map<String, dynamic>;
      cancellation.check();
      if ('${body['code']}' != '0') {
        final message = body['displayable'] == false
            ? ''
            : (body['message'] as String? ?? '').trim();
        throw SchoolRequestError(
          message.isEmpty ? '旧版延河课堂请求失败（错误码 ${body['code']}）' : message,
        );
      }
      return body['data'] as Map<String, dynamic>;
    } catch (_) {
      cancellation.check();
      rethrow;
    } finally {
      detach();
      client.close(force: true);
    }
  }

  StudyLectureStatus _status(Object? status) => switch ('$status') {
    '1' => StudyLectureStatus.live,
    '2' => StudyLectureStatus.upcoming,
    _ => StudyLectureStatus.ended,
  };

  Future<({List<LegacyLive> items, bool more})> lives(
    CancellationToken cancellation, {
    String keyword = '',
    int page = 1,
  }) async {
    final data = await _get('/v2/live/list', {
      'page': '$page',
      'page_size': '20',
      if (keyword.isNotEmpty) 'keyword': keyword,
    }, cancellation);
    DateTime at(String value) =>
        DateTime.parse('${value.replaceFirst(' ', 'T')}+08:00');
    return (
      items: [
        for (final row in data['data'] as List)
          LegacyLive(
            id: '${row['id']}',
            title: parseFragment(row['title'] as String).text ?? '',
            location: row['subtitle'] as String? ?? '',
            startsAt: at(row['schedule_started_at'] as String),
            endsAt: at(row['schedule_ended_at'] as String),
            status: _status(row['status']),
          ),
      ],
      more: page < (data['last_page'] as num),
    );
  }

  Future<LectureStreams> streams(
    String id,
    CancellationToken cancellation,
  ) async {
    final data = await _get('/v1/live', {
      'id': id,
      'with_session': 'true',
      'with_course': 'true',
    }, cancellation);
    final status = _status(data['status']);
    return LectureStreams(
      status: status,
      referer: 'https://www.yanhekt.cn/',
      urls: {
        if (status == StudyLectureStatus.live)
          for (final (field, kind) in [
            ('target', 'classroom'),
            ('target_vga', 'screen'),
          ])
            if (data[field] case final String url when url.isNotEmpty)
              kind: Uri.parse(url.replaceAll(r'\', '')),
      },
    );
  }
}
