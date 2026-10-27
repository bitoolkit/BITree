import 'dart:convert';
import 'dart:io';

import 'package:bitree/core/async/cancelable_request.dart';
import 'package:bitree/school/errors.dart';
import 'package:bitree/school/network.dart';
import 'package:bitree/school/storage.dart';
import 'package:bitree/study/controller.dart';
import 'package:bitree/study/yanhekt.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/http.dart';
import 'support/test_app.dart';

const oldToken = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.old-signature';
const newToken = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.new-signature';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late LocalHttpOverrides network;
  late MemorySchoolStorage storage;
  late YanhektRepository repository;
  late Future<void> Function(HttpRequest) respond;

  Future<void> reply(
    HttpRequest request,
    Object body, {
    int status = 200,
    Uri? location,
    String? token,
  }) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType(
      'application',
      'json',
      charset: 'utf-8',
    );
    if (location != null) {
      request.response.headers.set('Location', location.toString());
    }
    if (token != null) {
      request.response.cookies.add(Cookie('_token', token)..path = '/');
    }
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  Future<void> profile(HttpRequest request) => reply(request, {
    'code': 200,
    'params': {'id': 1, 'tenant_id': 21, 'phone': '123'},
  });

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    network = LocalHttpOverrides(server.port);
    storage = MemorySchoolStorage(
      credentials: const SchoolCredentials(
        username: 'student',
        password: 'test',
      ),
    );
    await storage.saveCookies(SchoolNetwork.campus, YanhektRepository.origin, [
      Cookie('_token', Uri.encodeComponent(jsonEncode({'token': oldToken})))
        ..path = '/',
    ]);
    repository = YanhektRepository(storage);
    server.listen((request) async => respond(request));
  });

  tearDown(() => server.close(force: true));

  test(
    'Passport course pagination uses params.result without a course API status code',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final pages = <String>[];
      respond = (request) async {
        expect(request.headers.value('Authorization'), 'Bearer $oldToken');
        if (request.uri.path.endsWith('/userapi/v1/infosimple')) {
          return profile(request);
        }
        expect(
          request.uri.path,
          '/aita.yanhekt.cn/vlabpassportapi/v1/account-profile/course',
        );
        expect(request.uri.queryParameters['force_mycourse'], '1');
        final page = request.uri.queryParameters['nowpage']!;
        pages.add(page);
        await reply(request, {
          'msg': '',
          'params': {
            'result': {
              'total': 2,
              'data': [
                {
                  'Id': page,
                  'Title': page == '1' ? '概率论 &amp; 数理统计' : '大学物理',
                  'Teacher': '张老师',
                  'TermName': '2026-2027-1',
                  'progress': {'subjectNum': page == '1' ? 0 : 12},
                },
              ],
            },
          },
        });
      };
      final courses = await repository.courses(
        (_) async => fail('Saved session should be reused'),
        CancellationToken(),
      );
      expect(courses.map((course) => course.id), ['1', '2']);
      expect(courses.first.title, '概率论 & 数理统计');
      expect(courses.last.title, '大学物理');
      expect(courses.map((course) => course.lectureCount), [0, 12]);
      expect(pages, ['1', '2']);
      expect(network.clients.every((client) => client.closed), isTrue);
    }, network),
  );

  test(
    'Refreshing the library hides confirmed empty offerings and preserves local courses',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final store = MemoryStudyStore();
      final controller = StudyController(store: store, repository: repository);
      addTearDown(controller.dispose);
      final local = await controller.addLocalCourse('大学物理实验');
      respond = (request) async {
        if (request.uri.path.endsWith('/userapi/v1/infosimple')) {
          return profile(request);
        }
        await reply(request, {
          'params': {
            'result': {
              'total': 3,
              'data': [
                {
                  'Id': 1,
                  'Title': '大学物理实验',
                  'progress': {'subjectNum': 0},
                },
                {
                  'Id': 2,
                  'Title': '大学物理',
                  'progress': {'subjectNum': 12},
                },
                {'Id': 3, 'Title': '未加载课时的课程'},
              ],
            },
          },
        });
      };
      await controller.refresh(
        (_) async => fail('Saved session should be reused'),
      );
      expect(controller.courses.map((course) => course.title), [
        local.title,
        '大学物理',
        '未加载课时的课程',
      ]);
      final reloaded = StudyController(store: store, repository: repository);
      addTearDown(reloaded.dispose);
      await reloaded.load();
      expect(reloaded.courses.map((course) => course.id), [local.id, '2', '3']);
    }, network),
  );

  test(
    'Course search still uses the recording API response format',
    () => HttpOverrides.runWithHttpOverrides(() async {
      respond = (request) async {
        if (request.uri.path.endsWith('/userapi/v1/infosimple')) {
          return profile(request);
        }
        expect(
          request.uri.path,
          '/aita.yanhekt.cn/courseapi/v3/multi-search/get-course-list',
        );
        expect(request.uri.queryParameters['title'], '振动');
        expect(request.headers.value('tenant-id'), '21');
        await reply(request, {
          'code': 0,
          'data': {
            'list': [
              {
                'id': 17,
                'title': '机械振动',
                'realname': '张老师',
                'term_name': '2026-2027-1',
              },
            ],
            'total': 1,
          },
        });
      };
      final courses = await repository.courses(
        (_) async => fail('Saved session should be reused'),
        CancellationToken(),
        search: '振动',
      );
      expect(courses.single.title, '机械振动');
      expect(courses.single.id, '17');
    }, network),
  );

  for (final message in ['', '  ', '服务正在维护']) {
    test(
      'A recording API error has a visible message when upstream says "$message"',
      () => HttpOverrides.runWithHttpOverrides(() async {
        respond = (request) async {
          if (request.uri.path.endsWith('/userapi/v1/infosimple')) {
            return profile(request);
          }
          await reply(request, {'code': 10003, 'msg': message});
        };
        await expectLater(
          repository.courses(
            (_) async => null,
            CancellationToken(),
            search: '数学',
          ),
          throwsA(
            isA<SchoolRequestError>().having(
              (failure) => failure.message,
              'message',
              message.trim().isEmpty ? contains('10003') : equals(message),
            ),
          ),
        );
      }, network),
    );
  }

  for (final stillExpired in [false, true]) {
    test(
      'An expired course request renews CAS once, stillExpired=$stillExpired',
      () => HttpOverrides.runWithHttpOverrides(() async {
        final callback = YanhektRepository.origin.resolve(
          '/casapi/index.php?r=auth/callback',
        );
        var signIns = 0;
        var courseRequests = 0;
        respond = (request) async {
          final path = request.uri.path;
          if (path.endsWith('/userapi/v1/infosimple')) return profile(request);
          if (path.endsWith('/vlabpassportapi/v1/account-profile/course')) {
            courseRequests++;
            if (request.headers.value('Authorization') == 'Bearer $oldToken' ||
                stillExpired) {
              return reply(request, {
                'name': 'Unauthorized',
                'code': 0,
                'status': 401,
              }, status: 401);
            }
            return reply(request, {
              'params': {
                'result': {
                  'total': 1,
                  'data': [
                    {
                      'Id': 9,
                      'Title': '数据结构',
                      'Teacher': '李老师',
                      'TermName': '2026-2027-1',
                    },
                  ],
                },
              },
            });
          }
          if (path == '/aita.yanhekt.cn/casapi/index.php') {
            if (request.uri.queryParameters['auType'] == 'cas') {
              return reply(
                request,
                {},
                status: 302,
                location: Uri.https('sso.bit.edu.cn', '/cas/login', {
                  'service': callback.toString(),
                }),
              );
            }
            if (request.uri.queryParameters['ticket'] == 'test-ticket') {
              return reply(request, {}, token: newToken);
            }
            return reply(request, {});
          }
          expect(path, '/sso.bit.edu.cn/cas/login');
          signIns++;
          await reply(
            request,
            {},
            status: 302,
            location: callback.replace(
              queryParameters: {
                ...callback.queryParameters,
                'ticket': 'test-ticket',
              },
            ),
          );
        };
        final reading = repository.courses(
          (_) async =>
              fail('An existing CAS session should not request a password'),
          CancellationToken(),
        );
        if (stillExpired) {
          await expectLater(reading, throwsA(isA<SessionExpired>()));
        } else {
          expect((await reading).single.title, '数据结构');
        }
        expect(signIns, 1);
        expect(courseRequests, 2);
        expect(network.clients.every((client) => client.closed), isTrue);
      }, network),
    );
  }
}
