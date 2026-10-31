import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bitree/agenda/controller.dart';
import 'package:bitree/agenda/deadline_source.dart';
import 'package:bitree/agenda/model.dart';
import 'package:bitree/school/learning/eclass_deadlines.dart';
import 'package:bitree/school/learning/lexue_deadlines.dart';
import 'package:bitree/school/network.dart';
import 'package:bitree/school/session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/http.dart';
import 'support/test_app.dart';

void main() {
  test(
    'Eclass course scanning keeps later courses when one course fails',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final paths = <String>[];
      server.listen((request) async {
        paths.add(request.uri.path);
        switch (request.uri.path) {
          case '/zy-eclass.bit.edu.cn/api/my-courses':
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'courses': [
                  {'id': 1, 'name': '暂时不可用的课程'},
                  {'id': 20759, 'name': '大学物理AⅡ'},
                ],
              }),
            );
          case '/zy-eclass.bit.edu.cn/api/courses/1/activities':
            request.response.statusCode = HttpStatus.serviceUnavailable;
            request.response.write('temporarily unavailable');
          case '/zy-eclass.bit.edu.cn/api/courses/20759/activities':
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'activities': [
                  {
                    'id': 9058,
                    'type': 'homework',
                    'title': '第4次作业：卷三第二章习题 18、21、23、24、27、29、31、35',
                    'end_time': '2026-11-02T15:59:00Z',
                    'visible_end_at': null,
                  },
                ],
              }),
            );
          case '/zy-eclass.bit.edu.cn/api/activities/9058':
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({'user_submit_count': 0}));
          default:
            request.response.statusCode = HttpStatus.notFound;
            request.response.write('unexpected request');
        }
        await request.response.close();
      });

      SchoolSession? session;
      addTearDown(() => session?.close());
      final entries = await HttpOverrides.runWithHttpOverrides(() {
        session = SchoolSession(
          network: SchoolNetwork.campus,
          storage: MemorySchoolStorage(),
        );
        return fetchEclassDeadlines(session!);
      }, LocalHttpOverrides(server.port));

      expect(entries, hasLength(1));
      expect(entries.single.id, 'eclass-9058');
      expect(entries.single.course, '大学物理AⅡ');
      expect(entries.single.startsAt, DateTime.utc(2026, 11, 2, 23, 59));
      expect(paths, isNot(contains('/zy-eclass.bit.edu.cn/api/todos')));
    },
  );

  test(
    'Lexue activity pages supply deadlines missing from calendar export',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final activityIds = <String>[];
      server.listen((request) async {
        final path = request.uri.path;
        switch (path) {
          case '/lexue.bit.edu.cn/calendar/export.php':
            request.response.headers.contentType = ContentType(
              'text',
              'html',
              charset: 'utf-8',
            );
            request.response.write(
              '<div class="calendarurl">'
              'https://lexue.bit.edu.cn/calendar/export_execute.php'
              '</div>',
            );
          case '/lexue.bit.edu.cn/calendar/export_execute.php':
            request.response.write('BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n');
          case '/lexue.bit.edu.cn/my/':
            request.response.headers.contentType = ContentType(
              'text',
              'html',
              charset: 'utf-8',
            );
            request.response.write(
              '<a href="/course/view.php?id=1">不可访问课程</a>'
              '<a href="https://lexue.bit.edu.cn/course/view.php?id=18553">'
              '概率论与数理统计</a>',
            );
          case '/lexue.bit.edu.cn/course/view.php':
            if (request.uri.queryParameters['id'] == '1') {
              request.response.statusCode = HttpStatus.serviceUnavailable;
              break;
            }
            request.response.headers.contentType = ContentType(
              'text',
              'html',
              charset: 'utf-8',
            );
            if (request.uri.queryParameters['section'] == '5') {
              request.response.write(
                '<div id="region-main">'
                '<div class="activityinstance">'
                '<a href="https://lexue.bit.edu.cn/mod/assign/view.php?id=541355">'
                '<span class="instancename">第五周作业</span></a></div>'
                '<div class="activityinstance">'
                '<a href="https://lexue.bit.edu.cn/mod/assign/view.php?id=541356">'
                '<span class="instancename">第四周作业</span></a></div>'
                '<a href="https://lexue.bit.edu.cn/mod/assign/view.php?id=156254">'
                '正文中的旧作业链接</a></div>',
              );
            } else {
              request.response.write(
                '<div id="page-header"><h1>概率论与数理统计</h1></div>'
                '<a href="https://lexue.bit.edu.cn/course/view.php?id=18553&section=5">'
                '10月19日 - 10月25日</a>'
                '<div id="region-main"></div>',
              );
            }
          case '/lexue.bit.edu.cn/mod/assign/view.php':
            activityIds.add(request.uri.queryParameters['id']!);
            request.response.headers.contentType = ContentType(
              'text',
              'html',
              charset: 'utf-8',
            );
            if (request.uri.queryParameters['id'] == '541356') {
              request.response.write(
                '<div data-region="activity-dates">'
                '<div><strong>到期日：</strong> 2026年10月25日 星期日 23:30</div>'
                '</div>'
                '<div class="submissionstatustable">'
                '<div class="submissionstatussubmitted">已提交</div></div>',
              );
              break;
            }
            request.response.write(
              '<div data-region="activity-dates">'
              '<div><strong>打开：</strong> 2026年10月19日 星期一 12:00</div>'
              '<div><strong>到期日：</strong> 2026年11月7日 星期六 03:30</div>'
              '</div>'
              '<div data-region="completion-info">'
              '<button data-toggletype="manual:mark-done">标记完成</button>'
              '</div>',
            );
          default:
            request.response.statusCode = HttpStatus.notFound;
            request.response.write('unexpected request');
        }
        await request.response.close();
      });

      SchoolSession? session;
      addTearDown(() => session?.close());
      final page = SchoolResponse(
        url: DeadlineSource.lexue.loginPage,
        status: HttpStatus.ok,
        location: null,
        bytes: Uint8List.fromList(
          utf8.encode('<script>M.cfg = {"sesskey":"test"};</script>'),
        ),
      );
      final entries = await HttpOverrides.runWithHttpOverrides(() {
        session = SchoolSession(
          network: SchoolNetwork.campus,
          storage: MemorySchoolStorage(),
        );
        return fetchLexueDeadlines(session!, page);
      }, LocalHttpOverrides(server.port));

      expect(entries, hasLength(2));
      final pending = entries.singleWhere(
        (entry) => entry.id == 'lexue-cmid-541355',
      );
      expect(pending.title, '第五周作业');
      expect(pending.course, '概率论与数理统计');
      expect(pending.startsAt, DateTime.utc(2026, 11, 7, 3, 30));
      expect(pending.done, isFalse);
      final submitted = entries.singleWhere(
        (entry) => entry.id == 'lexue-cmid-541356',
      );
      expect(submitted.startsAt, DateTime.utc(2026, 10, 25, 23, 30));
      expect(submitted.done, isTrue);
      expect(activityIds, ['541355', '541356']);
    },
  );

  test('A refreshed remote identifier replaces the same synced URL', () async {
    final oldUrl = Uri.https('lexue.bit.edu.cn', '/mod/assign/view.php', {
      'id': '541355',
    });
    final store = MemoryAgendaStore([
      AgendaEntry(
        id: 'lexue-event-42',
        title: '旧标题',
        kind: AgendaKind.deadline,
        startsAt: DateTime.utc(2026, 11, 6),
        done: true,
        course: '概率论与数理统计',
        source: DeadlineSource.lexue,
        local: false,
        url: oldUrl,
      ),
      AgendaEntry(
        id: 'lexue-cmid-541355',
        title: '旧的活动页标题',
        kind: AgendaKind.deadline,
        startsAt: DateTime.utc(2026, 11, 6),
        course: '概率论与数理统计',
        source: DeadlineSource.lexue,
        local: false,
        url: oldUrl,
      ),
    ]);
    final agenda = AgendaController(store);
    addTearDown(agenda.dispose);
    await agenda.load();

    expect(
      await agenda.mergeDeadlines([
        AgendaEntry(
          id: 'lexue-cmid-541355',
          title: '第五周作业',
          kind: AgendaKind.deadline,
          startsAt: DateTime.utc(2026, 11, 7, 3, 30),
          course: '概率论与数理统计',
          source: DeadlineSource.lexue,
          local: false,
          url: oldUrl,
        ),
      ]),
      isTrue,
    );

    expect(agenda.entries, hasLength(1));
    expect(agenda.entries.single.id, 'lexue-cmid-541355');
    expect(agenda.entries.single.title, '第五周作业');
    expect(agenda.entries.single.done, isTrue);
  });
}
