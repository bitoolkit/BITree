import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';

import '../agenda/model.dart';
import '../core/async/cancelable_request.dart';
import 'credentials.dart';
import 'tasks.dart';

class MoocFailure implements Exception {
  const MoocFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class MoocLoginRequired extends MoocFailure {
  const MoocLoginRequired() : super('中国大学MOOC 登录已失效，请重新登录。');
}

class MoocImportResult {
  const MoocImportResult({
    required this.entries,
    required this.courseCount,
    required this.failures,
  });
  final List<AgendaEntry> entries;
  final int courseCount;
  final List<({String course, String message})> failures;
}

/// All authenticated reads stay on one HTTPS origin. A real cookie jar owns
/// scope, expiry, path ordering and server cookie rotation for this operation.
class MoocApi {
  MoocApi(this._credentials, this._cancellation) {
    _detach = _cancellation.onCancel(close);
  }
  final MoocCredentials _credentials;
  final CancellationToken _cancellation;
  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  final _cookies = CookieJar();
  void Function() _detach = () {};
  bool _seeded = false;
  static const _timeout = Duration(seconds: 25);

  Future<MoocCredentials> credentials() async => MoocCredentials(
    userAgent: _credentials.userAgent,
    cookies: await _requestCookies(MoocCredentials.rpcDirectory),
  );

  Future<List<Cookie>> _requestCookies(Uri url) async {
    final cookies = (await _cookies.loadForRequest(url)).indexed.toList();
    // cookie_jar groups host and domain cookies separately. RFC 6265 request
    // order must consider path specificity across both groups.
    cookies.sort((a, b) {
      final path = (b.$2.path ?? '/').length.compareTo(
        (a.$2.path ?? '/').length,
      );
      return path != 0 ? path : a.$1.compareTo(b.$1);
    });
    return [for (final (_, cookie) in cookies) cookie];
  }

  Future<MoocAccount> member() async {
    final response = moocMap(await _rpc('memberBean.getMocMember'));
    final member = moocMap(response?['member']) ?? response;
    final id = moocId(member?['id']);
    if (id == null) throw const MoocLoginRequired();
    final name = member?['nickName'];
    return MoocAccount(
      id: id,
      name: name is String ? name : 'MOOC 用户',
      credentials: await credentials(),
    );
  }

  Future<MoocImportResult> readDeadlines(
    String memberId,
    void Function(String) progress,
  ) async {
    final courses = <String, MoocCourse>{};
    for (final type in [1, 2]) {
      final seenTerms = <String>{};
      progress(type == 1 ? '正在读取 MOOC 课程…' : '正在读取 SPOC 课程…');
      for (var page = 1; ; page++) {
        final response = await _rpc(
          'learnerCourseRpcBean.getMyLearnedCoursePanelList',
          form: {
            'type': '30',
            'p': '$page',
            'psize': '8',
            'courseType': '$type',
          },
        );
        if (response == null) break; // Official personal centre's empty result.
        final data = moocMap(response);
        if (data == null) throw const FormatException('MOOC 课程列表格式不正确。');
        final rows = moocList(data['list'] ?? data['result']);
        final before = seenTerms.length;
        for (final row in rows) {
          final panel = moocMap(row);
          final term = moocMap(panel?['termPanel']);
          final id = moocId(panel?['id']);
          final tid = moocId(term?['id']);
          final name = panel?['name'];
          if (id == null ||
              tid == null ||
              name is! String ||
              name.trim().isEmpty) {
            throw const FormatException('MOOC 课程缺少名称或学期信息。');
          }
          courses[tid] = MoocCourse(
            id: id,
            termId: tid,
            name: name,
            spoc: type == 2,
          );
          seenTerms.add(tid);
        }
        final pagination = moocMap(data['query'] ?? data['pagination']);
        final pages = pagination?['totlePageCount'];
        if (rows.isEmpty || (pages is int ? page >= pages : rows.length < 8)) {
          break;
        }
        if (seenTerms.length == before) {
          throw const MoocFailure('MOOC 课程分页没有前进，请稍后重试。');
        }
      }
    }
    final entries = <AgendaEntry>[];
    final failures = <({String course, String message})>[];
    var count = 0;
    for (final course in courses.values) {
      _cancellation.check();
      progress('正在读取 ${++count}/${courses.length}：《${course.name}》');
      try {
        final term = moocMap(
          await _rpc(
            'courseBean.getMocTermDto',
            form: {
              'termId': course.termId,
              'isDraft': '0',
              'excludeUnrelease': 'false',
            },
            referer: course.url,
          ),
        );
        if (term == null) throw const FormatException('MOOC 未返回课程结构。');
        entries.addAll(readMoocTasks(term, course, memberId));
      } on MoocLoginRequired {
        rethrow;
      } on MoocFailure catch (error) {
        failures.add((course: course.name, message: error.message));
      } on FormatException catch (error) {
        failures.add((course: course.name, message: error.message));
      }
    }
    if (courses.isNotEmpty && failures.length == courses.length) {
      throw MoocFailure('所有 MOOC 课程读取失败：${failures.first.message}');
    }
    return MoocImportResult(
      entries: entries,
      courseCount: courses.length - failures.length,
      failures: failures,
    );
  }

  Future<Object?> _rpc(
    String method, {
    Map<String, String> form = const {},
    Uri? referer,
  }) async {
    _cancellation.check();
    if (!_seeded) {
      await _cookies.saveFromResponse(
        MoocCredentials.origin,
        _credentials.cookies.map(Cookie.fromSetCookieValue).toList(),
      );
      _seeded = true;
    }
    final url = MoocCredentials.origin.resolve('/web/j/$method.rpc');
    final cookies = await _requestCookies(url);
    final csrf = cookies
        .where((cookie) => cookie.name == 'NTESSTUDYSI')
        .firstOrNull
        ?.value;
    if (csrf == null) throw const MoocLoginRequired();
    try {
      final request = await _http
          .postUrl(url.replace(queryParameters: {'csrfKey': csrf}))
          .timeout(_timeout);
      _cancellation.check();
      request.followRedirects = false;
      request.headers
        ..set(HttpHeaders.userAgentHeader, _credentials.userAgent)
        ..set(HttpHeaders.acceptHeader, 'application/json')
        ..set(
          HttpHeaders.refererHeader,
          '${referer ?? MoocCredentials.origin.resolve('/home.htm')}',
        )
        ..set('Origin', '${MoocCredentials.origin}')
        ..set('X-Requested-With', 'XMLHttpRequest')
        ..set('edu-script-token', csrf)
        ..contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
          charset: 'utf-8',
        );
      request.cookies.addAll(cookies);
      request.write(Uri(queryParameters: form).query);
      final response = await request.close().timeout(_timeout);
      _cancellation.check();
      final received = response.cookies.where((cookie) {
        final domain = cookie.domain?.toLowerCase().replaceFirst(
          RegExp(r'^\.'),
          '',
        );
        return domain == null ||
            (MoocCredentials.isMoocHost(domain) &&
                (url.host == domain || url.host.endsWith('.$domain')));
      }).toList();
      // Convert relative lifetime at arrival, before persisting the session.
      // Reopening the app must not restart a server cookie's Max-Age clock.
      for (final cookie in received) {
        final seconds = cookie.maxAge;
        if (seconds != null && seconds > 0) {
          cookie.expires = DateTime.now().toUtc().add(
            Duration(seconds: seconds),
          );
          cookie.maxAge = null;
        }
      }
      await _cookies.saveFromResponse(url, received);
      final text = await utf8.decoder.bind(response).join().timeout(_timeout);
      _cancellation.check();
      if ([301, 302, 303, 307, 308, 401, 403].contains(response.statusCode)) {
        throw const MoocLoginRequired();
      }
      if (response.statusCode == 429) {
        throw const MoocFailure('MOOC 请求过于频繁，请稍后重试。');
      }
      if (response.statusCode != 200) {
        throw MoocFailure('MOOC 请求失败（${response.statusCode}），请稍后重试。');
      }
      if (text.trimLeft().startsWith('<')) throw const MoocLoginRequired();
      final data = moocMap(jsonDecode(text));
      if (data == null) throw const FormatException('MOOC 返回的数据格式不正确。');
      if (data['code'] == 0) return data['result'];
      final message = data['message'];
      if (message == 'not_auth' ||
          (message is String &&
              (message.contains('登录') || message.contains('非法跨域')))) {
        throw const MoocLoginRequired();
      }
      throw const MoocFailure('MOOC 未完成请求，请稍后重试或重新登录。');
    } on Exception catch (error) {
      _cancellation.check();
      if (error is SocketException ||
          error is HttpException ||
          error is HandshakeException ||
          error is TimeoutException) {
        throw const MoocFailure('无法连接中国大学MOOC，请检查网络后重试。');
      }
      rethrow;
    }
  }

  void close() {
    _http.close(force: true);
    _detach();
  }
}
