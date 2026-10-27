import 'dart:convert';
import 'dart:io';

import 'package:bitree/updates/release.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/http.dart';

Map<String, dynamic> _release({required bool development}) => {
  'tag_name': development ? 'v0.3.0-dev' : 'v0.3.0',
  'html_url':
      'https://github.com/so1ve/bitree/releases/tag/${development ? 'v0.3.0-dev' : 'v0.3.0'}',
  'body': '## Unreleased\n\n- 已安装的旧变更\n- 更早的历史变更',
  'published_at': '2026-10-27T10:00:00Z',
  'prerelease': development,
  'assets': development
      ? [
          {
            'name': 'BITree-${Platform.operatingSystem}-update.json',
            'browser_download_url': 'https://downloads.example/update.json',
          },
        ]
      : [],
};

List<Map<String, dynamic>> _commits(int count, {String head = '3333333'}) => [
  for (var index = 1; index <= count; index++)
    {
      'sha': (index == count ? head : index.toRadixString(16).padLeft(7, '0'))
          .padRight(40, '0'),
      'html_url': 'https://github.com/so1ve/bitree/commit/change-$index',
      'commit': {'message': '变更 $index\n\n提交正文不应进入摘要'},
    },
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late LocalHttpOverrides network;
  late List<Uri> requests;
  late Map<String, List<Map<String, dynamic>>> changes;
  late Map<String, dynamic>? stable;
  late Map<String, dynamic>? development;
  late String developmentVersion;
  late int compareStatus;
  late int discoveryStatus;

  setUp(() async {
    requests = [];
    changes = {};
    stable = null;
    development = _release(development: true);
    developmentVersion = 'v0.3.0-dev.3333333';
    compareStatus = HttpStatus.ok;
    discoveryStatus = HttpStatus.ok;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    network = LocalHttpOverrides(server.port);
    server.listen((request) async {
      requests.add(request.uri);
      Object? data;
      switch (request.uri.path) {
        case '/api.github.com/repos/so1ve/bitree/releases/latest':
          request.response.statusCode = stable == null
              ? HttpStatus.notFound
              : discoveryStatus;
          data = stable;
        case '/api.github.com/repos/so1ve/bitree/releases':
          request.response.statusCode = discoveryStatus;
          data = [?development];
        case '/downloads.example/update.json':
          data = {
            'version': developmentVersion,
            'builtAt': '2026-10-27T09:00:00Z',
          };
        default:
          final entries = changes[request.uri.pathSegments.last];
          request.response.statusCode = entries == null
              ? HttpStatus.notFound
              : compareStatus;
          if (entries != null) {
            final page = int.parse(request.uri.queryParameters['page']!);
            final pageSize = int.parse(
              request.uri.queryParameters['per_page']!,
            );
            data = {
              'total_commits': entries.length,
              'commits': entries
                  .skip((page - 1) * pageSize)
                  .take(pageSize)
                  .toList(),
            };
          }
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(data));
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    expect(network.clients.every((client) => client.closed), isTrue);
  });

  Future<List<AppRelease>> read(String installed, {DateTime? builtAt}) =>
      HttpOverrides.runWithHttpOverrides(
        () => availableAppReleases(installed, builtAt: builtAt),
        network,
      );

  test(
    'Development notes compare exact installed and downloaded commits',
    () async {
      changes['1111111...3333333'] = _commits(2);
      final release = (await read('v0.3.0-dev.1111111')).single;
      expect(release.version, developmentVersion);
      expect(release.notes, contains('变更 2'));
      expect(
        release.notes.indexOf('变更 2'),
        lessThan(release.notes.indexOf('变更 1')),
      );
      expect(release.notes, isNot(contains('旧变更')));
      expect(release.notes, isNot(contains('历史变更')));
      expect(release.notes, isNot(contains('提交正文')));
      expect(release.notes, isNot(contains('另有')));
      expect(
        requests.where((url) => url.path.contains('/compare/')).single.path,
        endsWith('/1111111...3333333'),
      );
    },
  );

  test(
    'Stable updates include all changes since the installed release',
    () async {
      development = null;
      stable = _release(development: false);
      changes['v0.1.0...v0.3.0'] = _commits(3);
      final release = (await read('0.1.0')).single;
      expect(release.isDevelopment, isFalse);
      expect(release.notes, contains('变更 3'));
      expect(release.notes, contains('变更 1'));
      expect(release.notes, isNot(contains('历史变更')));
    },
  );

  test(
    'Moving from development to stable excludes already installed changes',
    () async {
      development = null;
      stable = _release(development: false);
      changes['1111111...v0.3.0'] = _commits(1);
      final release = (await read('v0.3.0-dev.1111111')).single;
      expect(release.version, 'v0.3.0');
      expect(release.notes, contains('变更 1'));
      expect(release.notes, isNot(contains('已安装')));
    },
  );

  test('Stable and development choices keep separate version ranges', () async {
    stable = _release(development: false);
    changes['v0.2.0...v0.3.0'] = _commits(1);
    changes['v0.2.0...3333333'] = _commits(2);
    final releases = await read('v0.2.0');
    expect(releases, hasLength(2));
    expect(releases.first.notes, isNot(contains('变更 2')));
    expect(releases.last.notes, contains('变更 2'));
    expect(releases.first.url.path, endsWith('/v0.3.0'));
    expect(releases.last.url.path, endsWith('/v0.3.0-dev'));
  });

  for (final (count, pages) in [
    (6, [1]),
    (102, [1, 2]),
    (106, [1, 2]),
    (305, [1, 4, 3]),
  ]) {
    test(
      'Shows the newest six of $count changes without reading unused pages',
      () async {
        changes['1111111...3333333'] = _commits(count);
        final release = (await read('v0.3.0-dev.1111111')).single;
        final bullets = const LineSplitter()
            .convert(release.notes)
            .where((line) => line.startsWith('- '))
            .toList();
        expect(bullets, hasLength(6));
        expect(bullets.first, contains('变更 $count '));
        expect(bullets.last, contains('变更 ${count - 5} '));
        if (count > 6) {
          expect(release.notes, contains('另有 ${count - 6} 项变更'));
          expect(
            release.notes,
            contains(
              'https://github.com/so1ve/bitree/compare/1111111...3333333',
            ),
          );
        }
        expect(
          requests
              .where((url) => url.path.contains('/compare/'))
              .map((url) => int.parse(url.queryParameters['page']!))
              .toList(),
          pages,
        );
      },
    );
  }

  test('No available update makes no changelog request', () async {
    stable = _release(development: false);
    expect(await read('v0.3.0', builtAt: DateTime.utc(2026, 10, 28)), isEmpty);
    expect(requests.where((url) => url.path.contains('/compare/')), isEmpty);
  });

  test(
    'Rebuilding the same commit does not request or repeat historical notes',
    () async {
      final release = (await read(
        'v0.3.0-dev.3333333',
        builtAt: DateTime.utc(2026, 10, 26),
      )).single;
      expect(release.notes, contains('没有新增代码变更'));
      expect(requests.where((url) => url.path.contains('/compare/')), isEmpty);
    },
  );

  test('An empty comparison does not fall back to cumulative notes', () async {
    changes['1111111...3333333'] = [];
    final release = (await read('v0.3.0-dev.1111111')).single;
    expect(release.notes, contains('没有新增代码变更'));
    expect(release.notes, isNot(contains('旧变更')));
  });

  for (final status in [HttpStatus.notFound, HttpStatus.serviceUnavailable]) {
    test(
      'A $status changelog failure keeps release and download actions available',
      () async {
        compareStatus = status;
        changes['1111111...3333333'] = _commits(1);
        final release = (await read('v0.3.0-dev.1111111')).single;
        expect(release.version, developmentVersion);
        expect(release.url.path, endsWith('/v0.3.0-dev'));
        expect(release.downloadUrl, release.url);
        expect(release.notes, '更新说明暂时无法读取，请查看发布页。');
        expect(release.notes, isNot(contains('旧变更')));
      },
    );
  }

  test('Release discovery errors still reach the update caller', () async {
    discoveryStatus = HttpStatus.serviceUnavailable;
    await expectLater(
      read('v0.3.0-dev.1111111'),
      throwsA(isA<HttpException>()),
    );
  });
}
