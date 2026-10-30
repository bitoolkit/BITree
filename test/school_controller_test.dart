import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bitree/agenda/deadline_source.dart';
import 'package:bitree/core/async/cancelable_request.dart';
import 'package:bitree/school/controller.dart';
import 'package:bitree/school/service.dart';
import 'package:bitree/school/storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/http.dart';
import 'support/test_app.dart';

void main() {
  test('Disposing a school session cancels pending reads without notifying a dead view', () async {
    final app = TestAppController();
    await app.initialize();
    final school = SchoolController(
      service: SchoolService(),
      storage: MemorySchoolStorage(),
      timetable: app.timetable,
      agenda: app.agenda,
      academics: app.academics,
    );
    final response = Completer<int>();
    final read = school.read(
      '查询',
      (_) => response.future,
      verify: (_) async => null,
    );
    school.dispose();
    response.complete(1);
    expect(await read, isNull);
  });

  test('Cancelling a school read releases busy state without publishing its result', () async {
    final app = TestAppController();
    await app.initialize();
    final response = Completer<int>();
    final cancellation = CancellationToken();
    final read = app.school.read(
      '查询',
      (_) => response.future,
      verify: (_) async => null,
      cancellation: cancellation,
    );
    expect(app.school.busy, isTrue);
    cancellation.cancel();
    response.complete(1);
    expect(await read, isNull);
    expect(app.school.busy, isFalse);
  });

  test('Sign out cancels the active read before removing credentials and academic state', () async {
    final storage = MemorySchoolStorage(
      credentials: const SchoolCredentials(
        username: 'student',
        password: 'test',
      ),
    );
    final app = TestAppController(schoolStorage: storage);
    await app.initialize();
    final response = Completer<int>();
    final read = app.school.read(
      '查询',
      (_) => response.future,
      verify: (_) async => null,
    );
    final signOut = app.school.signOut();
    response.complete(1);
    expect(await read, isNull);
    expect(await signOut, isTrue);
    expect(app.school.busy, isFalse);
    expect(app.school.accountStatus, AccountStatus.signedOut);
    expect(app.school.username, isNull);
    expect(await storage.readCredentials(), isNull);
    expect(app.academics.record.grades, isEmpty);
  });

  for (final lexueFails in [false, true]) {
    test(
      'One DDL update fetches both platforms when lexueFails=$lexueFails',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final hosts = <String>{};
        server.listen((request) async {
          final path = request.uri.path;
          hosts.add(request.uri.pathSegments.first);
          if (path == '/lexue.bit.edu.cn/login/index.php') {
            request.response.statusCode = lexueFails ? 503 : 200;
            request.response.write('<script>M.cfg={"sesskey":"test"}</script>');
          } else if (path == '/lexue.bit.edu.cn/calendar/export.php') {
            request.response.write(
              '<div class="calendarurl">https://lexue.bit.edu.cn/calendar/export_execute.php</div>',
            );
          } else if (path == '/lexue.bit.edu.cn/calendar/export_execute.php') {
            request.response.write('BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n');
          } else {
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode(switch (path) {
                '/zy-eclass.bit.edu.cn/user/courses' => {},
                '/zy-eclass.bit.edu.cn/api/my-courses' => {
                  'courses': [
                    {'id': 7, 'name': '离散数学'},
                  ],
                  'pages': 1,
                },
                '/zy-eclass.bit.edu.cn/api/courses/7/activities' => {
                  'activities': [
                    {
                      'id': 8,
                      'title': '第一章作业',
                      'submit_times': 1,
                      'end_time': '2099-10-27 23:59:00',
                    },
                  ],
                },
                '/zy-eclass.bit.edu.cn/api/activities/8' => {
                  'user_submit_count': 0,
                },
                _ => throw StateError('Unexpected request: $path'),
              }),
            );
          }
          await request.response.close();
        });
        final app = TestAppController();
        await app.initialize();
        final busy = <bool>[];
        app.school.addListener(() => busy.add(app.school.busy));
        final success = await HttpOverrides.runWithHttpOverrides(
          () => app.school.importDeadlines(verify: (_) async => null),
          LocalHttpOverrides(server.port),
        );
        expect(success, !lexueFails);
        expect(hosts, {'lexue.bit.edu.cn', 'zy-eclass.bit.edu.cn'});
        expect(app.agenda.entries.single.title, '第一章作业');
        expect(app.agenda.entries.single.source, DeadlineSource.eclass);
        expect(busy, [true, false]);
      },
    );
  }

  for (final source in [DeadlineSource.lexue, DeadlineSource.eclass]) {
    test('A source-specific DDL update only fetches ${source.label}', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final hosts = <String>{};
      server.listen((request) async {
        final path = request.uri.path;
        hosts.add(request.uri.pathSegments.first);
        switch (path) {
          case '/lexue.bit.edu.cn/login/index.php':
            request.response.write('<script>M.cfg={"sesskey":"test"}</script>');
          case '/lexue.bit.edu.cn/calendar/export.php':
            request.response.write(
              '<div class="calendarurl">https://lexue.bit.edu.cn/calendar/export_execute.php</div>',
            );
          case '/lexue.bit.edu.cn/calendar/export_execute.php':
            request.response.write('BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n');
          case '/zy-eclass.bit.edu.cn/user/courses':
            request.response.headers.contentType = ContentType.json;
            request.response.write('{}');
          case '/zy-eclass.bit.edu.cn/api/my-courses':
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({'courses': [], 'pages': 1}));
          default:
            throw StateError('Unexpected request: $path');
        }
        await request.response.close();
      });
      final app = TestAppController();
      await app.initialize();
      final success = await HttpOverrides.runWithHttpOverrides(
        () => app.school.importDeadlines(
          source: source,
          verify: (_) async => null,
        ),
        LocalHttpOverrides(server.port),
      );
      expect(success, isTrue);
      expect(hosts, {source.origin.host});
      expect(app.school.busy, isFalse);
    });
  }

  test(
    'Cancelling a combined DDL update does not start the next platform',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final first = Completer<void>();
      final hosts = <String>[];
      server.listen((request) {
        hosts.add(request.uri.pathSegments.first);
        if (!first.isCompleted) first.complete();
      });
      final app = TestAppController();
      await app.initialize();
      await HttpOverrides.runWithHttpOverrides(() async {
        final updating = app.school.importDeadlines(verify: (_) async => null);
        await first.future;
        app.school.cancel();
        expect(await updating, isFalse);
      }, LocalHttpOverrides(server.port));
      expect(hosts, ['lexue.bit.edu.cn']);
      expect(app.agenda.entries, isEmpty);
      expect(app.school.busy, isFalse);
    },
  );
}
