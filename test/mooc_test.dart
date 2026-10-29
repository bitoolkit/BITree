import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bitree/agenda/controller.dart';
import 'package:bitree/agenda/deadline_clear_scope.dart';
import 'package:bitree/agenda/deadline_source.dart';
import 'package:bitree/agenda/model.dart';
import 'package:bitree/core/async/cancelable_request.dart';
import 'package:bitree/core/diagnostics.dart';
import 'package:bitree/mooc/api.dart';
import 'package:bitree/mooc/controller.dart';
import 'package:bitree/mooc/credentials.dart';
import 'package:bitree/mooc/tasks.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/http.dart';
import 'support/test_app.dart';

final due = DateTime.utc(2026, 11, 2, 23, 59);
int timestamp(DateTime beijing) =>
    beijing.subtract(const Duration(hours: 8)).millisecondsSinceEpoch;

// Field names and nesting follow the public term response and the official
// personal-centre modules; identifiers, times and account data are test inputs.
Map<String, dynamic> task(int id, {int judge = 1, num? score}) => {
  'id': id,
  'name': '第 $id 周作业',
  'deadline': timestamp(due),
  'releaseTime': timestamp(due.subtract(const Duration(days: 7))),
  'evaluateJudgeType': judge,
  'evaluateStart': timestamp(due.add(const Duration(hours: 1))),
  'evaluateEnd': timestamp(due.add(const Duration(days: 3))),
  'userScore': score,
  'usedTryCount': 1,
};

Map<String, dynamic> term(int course) => {
  'id': 100 + course,
  'courseId': course,
  'chapters': [
    {
      'id': 1,
      'published': true,
      'visible': 1,
      'lessons': [],
      'homeworks': [
        {'id': 30, 'contentType': 3, 'test': task(31)},
      ],
      'quizs': [],
    },
  ],
  'exams': [],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('bitree-mooc-tests-');
    messenger.setMockMethodCallHandler(channel, (_) async => directory.path);
  });
  tearDownAll(() async {
    await AppDiagnostics.instance.recentLines();
    messenger.setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  group('MOOC task metadata', () {
    const course = MoocCourse(
      id: '7',
      termId: '107',
      name: '概率论与数理统计',
      spoc: true,
    );

    test('Submission, quiz, exam and subjective-exam peer review are separate deadlines', () {
      final data = term(7);
      final chapter = (data['chapters'] as List).single as Map<String, dynamic>;
      chapter['homeworks'] = [
        {'test': task(31)},
        {'test': task(32, judge: 2, score: 0)},
      ];
      chapter['quizs'] = [
        {'contentType': 2, 'test': task(41, judge: 2)},
      ];
      chapter['lessons'] = [
        {'contentType': 3, 'test': task(31)}, // Same homework also in lessons.
        {
          'contentType': 1,
          'units': [
            {'id': 999, 'contentType': 5},
          ],
        }, // Practice question, no DDL.
      ];
      data['exams'] = [
        {
          'id': 51,
          'name': '期末考试',
          'deadline': timestamp(due),
          'subjectTest': task(52),
          'objectTest': task(53, judge: 2),
        },
      ];
      final entries = readMoocTasks(data, course, '8');
      expect(entries, hasLength(6));
      expect(entries.where((e) => e.title.startsWith('互评：')), hasLength(2));
      expect(entries.where((e) => e.title == '互评：第 32 周作业'), isEmpty);
      expect(entries.where((e) => e.title == '第 31 周作业').single.done, isFalse);
      expect(entries.where((e) => e.title == '第 32 周作业').single.done, isTrue);
      expect(entries.first.startsAt, due);
      final review = entries.firstWhere((e) => e.title == '互评：期末考试');
      expect(review.startsAt, due.add(const Duration(days: 3)));
      expect(review.notes, contains('开始：'));
      expect(review.source, DeadlineSource.mooc);
      expect(
        DeadlineClearScope.values.where(
          (scope) => scope.includes(review.copyWith(done: true, deleted: true)),
        ),
        [DeadlineClearScope.mooc],
      );
      expect(review.course, course.name);
      expect(review.url!.path, '/spoc/learn/7');
      expect(AgendaEntry.fromJson(review.toJson()).id, review.id);
    });

    test('A different member has separate imported tasks', () {
      expect(
        readMoocTasks(term(7), course, '8').first.id,
        isNot(readMoocTasks(term(7), course, '9').first.id),
      );
    });

    test('Malformed metadata fails instead of reporting an empty successful import', () {
      final broken = term(7)..['chapters'] = 'not a list';
      expect(() => readMoocTasks(broken, course, '8'), throwsFormatException);
      expect(() => readMoocTasks(term(6), course, '8'), throwsFormatException);
    });

    test(
      'Hidden chapters and activities without a deadline do not create tasks',
      () {
        final data = term(7);
        final chapter =
            (data['chapters'] as List).single as Map<String, dynamic>;
        chapter['published'] = false;
        expect(readMoocTasks(data, course, '8'), isEmpty);
        chapter['published'] = true;
        chapter['homeworks'] = [
          {
            'test': {'id': 31, 'name': '无截止练习', 'deadline': -1},
          },
        ];
        expect(readMoocTasks(data, course, '8'), isEmpty);
      },
    );
  });

  test('Cookie import accepts copied headers and retains values containing equals signs', () {
    final value = MoocCredentials.fromCookieHeader(
      'Accept: */*\r\nCookie: NTESSTUDYSI=csrf; STUDY_SESS=abc==\r\nReferer: https://www.icourse163.org/',
    );
    expect(value.cookies.map(Cookie.fromSetCookieValue).last.value, 'abc==');
    expect(
      () => MoocCredentials.fromCookieHeader('NTESSTUDYSI=x\r\nX-Test: y'),
      throwsFormatException,
    );
  });

  group('Authenticated requests', () {
    late HttpServer server;
    late MoocController controller;
    late AgendaController agenda;
    late MemoryMoocStorage storage;
    late LocalHttpOverrides network;
    late MoocCredentials credential;
    var expired = false;
    var brokenCourse = false;
    var malformedPage = false;
    Completer<void>? waiting;
    final pages = <String>[];

    setUp(() async {
      expired = false;
      brokenCourse = false;
      malformedPage = false;
      waiting = null;
      pages.clear();
      credential = MoocCredentials(
        userAgent: 'MOOC test browser',
        cookies: [
          Cookie('NTESSTUDYSI', 'csrf')..path = '/',
          Cookie('STUDY_SESS', 'session')
            ..domain = '.icourse163.org'
            ..path = '/'
            ..httpOnly = true,
          Cookie('STUDY_SESS', 'specific')
            ..domain = '.icourse163.org'
            ..path = '/web/j/'
            ..httpOnly = true,
          Cookie('secret', 'foreign')
            ..domain = '.example.org'
            ..path = '/',
          Cookie('secret', 'wrong-path')
            ..domain = '.icourse163.org'
            ..path = '/passport/',
        ],
      );
      storage = MemoryMoocStorage();
      agenda = AgendaController(MemoryAgendaStore());
      await agenda.load();
      controller = MoocController(storage: storage, agenda: agenda);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      network = LocalHttpOverrides(server.port);
      server.listen((request) async {
        if (request.uri.path == '/www.icourse163.org/home.htm') {
          expect(request.method, 'GET');
          expect(
            request.headers.value(HttpHeaders.userAgentHeader),
            'MOOC test browser',
          );
          final cookie = request.headers.value(HttpHeaders.cookieHeader)!;
          expect(cookie, contains('STUDY_SESS=session'));
          expect(cookie, isNot(contains('STUDY_SESS=specific')));
          if (expired) {
            request.response.write('<html><body>请登录</body></html>');
          } else {
            request.response.cookies.add(
              Cookie('NTESSTUDYSI', 'rotated')..path = '/',
            );
            request.response.write(
              '<html><script>window.webUser = '
              '${jsonEncode({'id': 8, 'nickName': '测试同学'})};</script></html>',
            );
          }
          await request.response.close();
          return;
        }
        final form = Uri.splitQueryString(
          await utf8.decoder.bind(request).join(),
        );
        expect(request.method, 'POST');
        expect(request.uri.path, startsWith('/www.icourse163.org/web/j/'));
        expect(
          request.headers.value(HttpHeaders.userAgentHeader),
          'MOOC test browser',
        );
        final cookie = request.headers.value(HttpHeaders.cookieHeader)!;
        expect(cookie, isNot(contains('foreign')));
        expect(cookie, isNot(contains('wrong-path')));
        expect(
          cookie.indexOf('STUDY_SESS=specific'),
          lessThan(cookie.indexOf('STUDY_SESS=session')),
        );
        expect(
          request.headers.value('edu-script-token'),
          request.uri.queryParameters['csrfKey'],
        );
        if (expired) {
          request.response.write(
            jsonEncode({'code': 1, 'message': 'not_auth', 'result': null}),
          );
        } else if (request.uri.path.endsWith(
          'getMyLearnedCoursePanelList.rpc',
        )) {
          expect(form['type'], '30');
          expect(form['psize'], '8');
          pages.add('${form['courseType']}:${form['p']}');
          final spoc = form['courseType'] == '2';
          final ids = spoc
              ? [10]
              : form['p'] == '1'
              ? List.generate(8, (i) => i + 1)
              : [9];
          request.response.write(
            jsonEncode({
              'code': 0,
              'result': {
                'list': malformedPage
                    ? 'wrong'
                    : [
                        for (final id in ids)
                          {
                            'id': id,
                            'name': '课程 $id',
                            'termPanel': {'id': id + 100},
                          },
                      ],
                'query': {'totlePageCount': spoc ? 1 : 2},
              },
            }),
          );
        } else if (request.uri.path.endsWith('getMocTermDto.rpc')) {
          expect(request.uri.queryParameters['csrfKey'], 'rotated');
          expect(form['isDraft'], '0');
          final id = int.parse(form['termId']!) - 100;
          if (waiting case final signal?) {
            signal.complete();
            return;
          }
          if (brokenCourse && id == 10) {
            request.response.statusCode = 503;
          } else {
            request.response.write(jsonEncode({'code': 0, 'result': term(id)}));
          }
        } else {
          fail('Unexpected authenticated request');
        }
        await request.response.close();
      });
    });

    tearDown(() async {
      controller.dispose();
      agenda.dispose();
      await server.close(force: true);
    });

    test(
      'Every MOOC and SPOC page is read, rotated cookies are saved, and repeated sync preserves edits',
      () => HttpOverrides.runWithHttpOverrides(() async {
        await controller.connect(credential);
        expect(storage.account!.name, '测试同学');
        expect(
          storage.account!.credentials.cookies.join(';'),
          contains('NTESSTUDYSI=rotated'),
        );
        final first = (await controller.synchronize())!;
        expect(pages, ['1:1', '1:2', '2:1']);
        expect(first.courseCount, 10);
        expect(first.entries, hasLength(20));
        expect(first.failures, isEmpty);
        final saved = agenda.entries.first;
        await agenda.save(
          AgendaEntry(
            id: saved.id,
            title: '我编辑的标题',
            kind: saved.kind,
            startsAt: saved.startsAt,
            source: saved.source,
            local: true,
            done: true,
            deleted: true,
          ),
        );
        await controller.synchronize();
        expect(agenda.entries.length + agenda.deletedDeadlines.length, 20);
        final edited = agenda.deletedDeadlines.single;
        expect(edited.title, '我编辑的标题');
        expect(edited.done, isTrue);
        expect(controller.busy, isFalse);
      }, network),
    );

    test(
      'An expired session retains local tasks and can be manually reconnected',
      () => HttpOverrides.runWithHttpOverrides(() async {
        await controller.connect(credential);
        await controller.synchronize();
        expired = true;
        await expectLater(
          controller.synchronize(),
          throwsA(isA<MoocLoginRequired>()),
        );
        expect(controller.needsLogin, isTrue);
        expect(agenda.entries, hasLength(20));
        expired = false;
        await controller.connect(credential);
        expect(controller.needsLogin, isFalse);
      }, network),
    );

    test(
      'Partial course failure is visible in the import result',
      () => HttpOverrides.runWithHttpOverrides(() async {
        await controller.connect(credential);
        brokenCourse = true;
        final result = (await controller.synchronize())!;
        expect(result.courseCount, 9);
        expect(result.failures.single.course, '课程 10');
        expect(agenda.entries, hasLength(18));
      }, network),
    );

    test(
      'Invalid course pages do not overwrite the agenda',
      () => HttpOverrides.runWithHttpOverrides(() async {
        await controller.connect(credential);
        malformedPage = true;
        await expectLater(controller.synchronize(), throwsFormatException);
        expect(agenda.entries, isEmpty);
      }, network),
    );

    test(
      'Cancel closes the request before any task is imported',
      () => HttpOverrides.runWithHttpOverrides(() async {
        await controller.connect(credential);
        waiting = Completer<void>();
        final done = expectLater(
          controller.synchronize(),
          throwsA(isA<RequestCancelled>()),
        );
        await waiting!.future;
        controller.cancel();
        await done;
        expect(agenda.entries, isEmpty);
        expect(controller.busy, isFalse);
        expect(controller.error, isNull);
      }, network),
    );

    test(
      'Disconnect during a read prevents late results from restoring the account',
      () => HttpOverrides.runWithHttpOverrides(() async {
        await controller.connect(credential);
        waiting = Completer<void>();
        final done = expectLater(
          controller.synchronize(),
          throwsA(isA<RequestCancelled>()),
        );
        await waiting!.future;
        await controller.disconnect();
        await done;
        expect(storage.account, isNull);
        expect(controller.account, isNull);
        expect(agenda.entries, isEmpty);
      }, network),
    );
  });
}
