import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bitree/core/async/cancelable_request.dart';
import 'package:bitree/core/diagnostics.dart';
import 'package:bitree/school/errors.dart';
import 'package:bitree/school/network.dart';
import 'package:bitree/school/storage.dart';
import 'package:bitree/study/controller.dart';
import 'package:bitree/study/legacy_yanhekt.dart';
import 'package:bitree/study/media.dart';
import 'package:bitree/study/model.dart';
import 'package:bitree/study/playback.dart';
import 'package:bitree/study/tasks.dart';
import 'package:bitree/study/ui/study_course.dart';
import 'package:bitree/study/ui/study_live.dart';
import 'package:bitree/study/yanhekt.dart';
import 'package:bitree/ui/app_menu_anchor.dart';
import 'package:bitree/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/http.dart';
import 'support/test_app.dart';

const oldToken = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.old-signature';
const newToken = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.new-signature';

class _NativeHttpOverrides extends HttpOverrides {}

Future<void> pumpHttp(WidgetTester tester, Future<void> served) async {
  var completed = false;
  unawaited(served.then((_) => completed = true));
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    if (completed &&
        find.byType(LinearProgressIndicator).evaluate().isEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
  expect(
    completed,
    isTrue,
    reason: 'The request should reach the local HTTP server',
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late LocalHttpOverrides network;
  late MemorySchoolStorage storage;
  late YanhektRepository repository;
  late Future<void> Function(HttpRequest) respond;
  late Directory logs;

  setUpAll(() async {
    logs = await Directory.systemTemp.createTemp('bitree-live-logs-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => logs.path,
        );
  });

  tearDownAll(() async {
    await AppDiagnostics.instance.recentLines();
    await logs.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

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

  Map<String, dynamic> legacyLive(String id, {int status = 2}) => {
    'id': int.parse(id),
    'title': '旧版测试课程',
    'subtitle': '文萃楼 A302',
    'status': status,
    'schedule_started_at': '2026-10-27 18:30:00',
    'schedule_ended_at': '2026-10-27 20:55:00',
    'target': r'https:\\/\\/clive11.yanhekt.cn\\/live/camera.m3u8',
    'target_vga': r'https:\\/\\/clive11.yanhekt.cn\\/live/slides.m3u8',
    'session': {'id': 850101, 'course_id': 70101},
    'course': {'id': 70101},
  };

  test(
    'Old Yanhekt searches and pages the public list without signing in',
    () => HttpOverrides.runWithHttpOverrides(() async {
      respond = (request) async {
        expect(request.uri.path, '/cbiz.yanhekt.cn/v2/live/list');
        expect(request.headers.value('Authorization'), isNull);
        expect(request.headers.value('Origin'), 'https://www.yanhekt.cn');
        expect(request.headers.value('Xdomain-Client'), 'web_user');
        expect(
          request.headers.value('Xclient-Signature'),
          '72b77856f6df3f563ab6e658631cac3d',
        );
        expect(request.uri.queryParameters['keyword'], '测试');
        final page = int.parse(request.uri.queryParameters['page']!);
        await reply(request, {
          'code': '0',
          'data': {
            'data': [legacyLive('$page')],
            'last_page': 2,
          },
        });
      };
      final legacy = LegacyYanhektRepository();
      final first = await legacy.lives(CancellationToken(), keyword: '测试');
      expect(first.items.single.id, '1');
      expect(first.items.single.startsAt, DateTime.utc(2026, 10, 27, 10, 30));
      expect(first.more, isTrue);
      final second = await legacy.lives(
        CancellationToken(),
        keyword: '测试',
        page: 2,
      );
      expect(second.items.single.id, '2');
      expect(second.more, isFalse);
      expect(network.clients.every((client) => client.closed), isTrue);
    }, network),
  );

  test(
    'Old playback resolves the broadcast ID and cleans the actual escaped stream URLs',
    () => HttpOverrides.runWithHttpOverrides(() async {
      var status = 1;
      respond = (request) async {
        expect(request.uri.path, '/cbiz.yanhekt.cn/v1/live');
        expect(request.uri.queryParameters, {
          'id': '760101',
          'with_session': 'true',
          'with_course': 'true',
        });
        expect(request.headers.value('Authorization'), isNull);
        await reply(request, {
          'code': 0,
          'data': legacyLive('760101', status: status),
        });
      };
      final legacy = LegacyYanhektRepository();
      final streams = await legacy.streams('760101', CancellationToken());
      expect(streams.status, StudyLectureStatus.live);
      expect(streams.referer, 'https://www.yanhekt.cn/');
      expect(
        streams.urls['classroom'],
        Uri.https('clive11.yanhekt.cn', '/live/camera.m3u8'),
      );
      expect(
        streams.urls['screen'],
        Uri.https('clive11.yanhekt.cn', '/live/slides.m3u8'),
      );
      expect(
        streams.sign(streams.urls['classroom']!),
        streams.urls['classroom'],
      );
      status = 3;
      final ended = await legacy.streams('760101', CancellationToken());
      expect(ended.status, StudyLectureStatus.ended);
      expect(ended.urls, isEmpty);
    }, network),
  );

  test(
    'Old live search cancels its transport instead of reporting a network failure',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final requested = Completer<void>();
      respond = (request) async {
        requested.complete();
      };
      final cancel = CancellationToken();
      final pending = LegacyYanhektRepository().lives(cancel);
      await requested.future;
      final cancelled = expectLater(pending, throwsA(isA<RequestCancelled>()));
      cancel.cancel();
      await cancelled;
      expect(network.clients.every((client) => client.closed), isTrue);
    }, network),
  );

  for (final (size, scale) in [
    (const Size(320, 640), 1.0),
    (const Size(390, 844), 1.8),
    (const Size(1200, 800), 1.0),
  ]) {
    testWidgets(
      'Old live entry stays public and uses its broadcast ID at $size / $scale',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final listed = Completer<void>();
        final opened = Completer<void>();
        respond = (request) async {
          expect(request.headers.value('Authorization'), isNull);
          if (request.uri.path == '/cbiz.yanhekt.cn/v2/live/list') {
            await reply(request, {
              'code': 0,
              'data': {
                'data': [legacyLive('760101')],
                'last_page': 1,
              },
            });
            if (!listed.isCompleted) listed.complete();
          } else {
            expect(request.uri.path, '/cbiz.yanhekt.cn/v1/live');
            expect(request.uri.queryParameters['id'], '760101');
            await reply(request, {
              'code': 0,
              'data': legacyLive('760101', status: 3),
            });
            if (!opened.isCompleted) opened.complete();
          }
        };
        final app = TestAppController();
        await HttpOverrides.runWithHttpOverrides(() async {
          await tester.pumpWidget(
            MaterialApp(
              theme: bitreeTheme(Brightness.light),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: StudyLiveScreen(app: app),
            ),
          );
          await pumpHttp(tester, listed.future);
          expect(find.text('旧版直播'), findsOneWidget);
          expect(find.text('旧版测试课程'), findsOneWidget);
          await tester.tap(find.text('旧版直播'));
          await tester.pumpAndSettle();
          expect(find.text('延河课堂（新版）'), findsOneWidget);
          await tester.tap(find.widgetWithText(AppMenuItemButton, '延河课堂（旧版）'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('旧版测试课程'));
          await tester.pump();
          await pumpHttp(tester, opened.future);
          expect(find.text('直播已结束'), findsOneWidget);
          expect(find.text('打开延河课堂'), findsOneWidget);
          expect(find.byType(Slider), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        }, network);
      },
    );
  }

  Map<String, dynamic> courseDetail() => {
    'code': 0,
    'data': {
      'id': '17',
      'title': '大学物理 AⅡ',
      'realname': '张老师',
      'term_name': '2026-2027-1',
      'sub_list': {
        '2026': {
          '10': {
            '4': [
              for (final (id, status, hour) in [
                ('101', '1', 8),
                ('102', '2', 13),
                ('103', '6', 6),
                ('104', '3', 10),
                ('105', '5', 11),
              ])
                {
                  'id': id,
                  'sub_title': '第$id课时',
                  'sub_status': status,
                  'playback_status': status == '6' ? '1' : '0',
                  'class_begin':
                      '${DateTime.utc(2026, 10, 27, hour - 8).millisecondsSinceEpoch ~/ 1000}',
                  'class_over':
                      '${DateTime.utc(2026, 10, 27, hour - 7).millisecondsSinceEpoch ~/ 1000}',
                },
            ],
          },
        },
      },
    },
  };

  Map<String, dynamic> today() => {
    'success': true,
    'result': {
      'code': 200,
      'list': [
        {
          'day': '2026-10-27',
          'course': [
            for (final (id, status, hour) in [
              ('101', '1', 8),
              ('102', '2', 13),
              ('103', '6', 6),
            ])
              {
                'id': id,
                'course_id': '17',
                'course_title': '大学物理 AⅡ',
                'lecturer_name': '张老师',
                'status': status,
                'start_at':
                    '${DateTime.utc(2026, 10, 27, hour - 8).millisecondsSinceEpoch ~/ 1000}',
                'end_at':
                    '${DateTime.utc(2026, 10, 27, hour - 7).millisecondsSinceEpoch ~/ 1000}',
              },
          ],
        },
      ],
    },
  };

  Map<String, dynamic> liveStreams() => {
    'code': 0,
    'data': {
      'sub_status': '1',
      'video_list': {
        '0': {
          'type': '2',
          'status': '2',
          'preview_url': 'https://aita.yanhekt.cn/play/placeholder.mp4',
        },
      },
      'live_url': {
        'output': {
          'm3u8': 'https://clive11.yanhekt.cn/live/305_Video1.m3u8?auth_key=cdn-token',
        },
        'output_ppt': {
          'm3u8': 'https://clive11.yanhekt.cn/live/305_VideoVga.m3u8',
        },
        'output_tts': {
          'm3u8':
              'https://clive11.yanhekt.cn/live/unavailable-translation.m3u8',
        },
      },
    },
  };

  test(
    'Course details preserve live, upcoming and ended sessions next to recordings',
    () => HttpOverrides.runWithHttpOverrides(() async {
      respond = (request) => request.uri.path.endsWith('/infosimple')
          ? profile(request)
          : reply(request, courseDetail());
      final course = await repository.course(
        '17',
        (_) async => null,
        CancellationToken(),
      );
      expect(course.lectureCount, 5);
      expect(
        course.lectures.map((lecture) => lecture.status).toSet(),
        StudyLectureStatus.values.toSet(),
      );
      final live = course.lectures.firstWhere((lecture) => lecture.id == '101');
      expect(live.endsAt!.difference(live.startsAt!), const Duration(hours: 1));
      final saved = StudyCourse.fromJson(
        jsonDecode(jsonEncode(course.toJson())) as Map<String, dynamic>,
      );
      expect(
        saved.lectures.firstWhere((lecture) => lecture.id == '101').status,
        StudyLectureStatus.live,
      );
      expect(
        StudyLecture.fromJson({'id': 'old', 'title': '旧录播'}).status,
        StudyLectureStatus.recorded,
      );
    }, network),
  );

  test(
    'Live sources use HLS camera and screen feeds without recording signatures or duration',
    () => HttpOverrides.runWithHttpOverrides(() async {
      var body = liveStreams();
      respond = (request) => request.uri.path.endsWith('/infosimple')
          ? profile(request)
          : reply(request, body);
      final streams = await repository.streams(
        '17',
        '101',
        (_) async => null,
        CancellationToken(),
      );
      expect(streams.status, StudyLectureStatus.live);
      expect(streams.duration, Duration.zero);
      expect(streams.urls.keys, ['classroom', 'screen']);
      final camera = streams.urls['classroom']!;
      expect(streams.sign(camera), camera);
      expect(camera.queryParameters['auth_key'], 'cdn-token');
      expect(
        streams.urls.values.any((url) => url.path.contains('placeholder')),
        isFalse,
      );
      body = {
        'code': 0,
        'data': {'sub_status': '3'},
      };
      final ended = await repository.streams(
        '17',
        '101',
        (_) async => null,
        CancellationToken(),
      );
      expect(ended.status, StudyLectureStatus.processing);
      expect(ended.urls, isEmpty);
      body = {
        'code': 0,
        'data': {
          'sub_status': '6',
          'duration': '120',
          'video_list': [
            {
              'type': '2',
              'status': '2',
              'preview_url': 'https://aita.yanhekt.cn/play/screen.mp4',
            },
          ],
        },
      };
      final recorded = await repository.streams(
        '17',
        '101',
        (_) async => null,
        CancellationToken(),
      );
      expect(recorded.status, StudyLectureStatus.recorded);
      expect(recorded.duration, const Duration(minutes: 2));
      expect(
        recorded.sign(recorded.urls['screen']!).queryParameters,
        contains('t'),
      );
    }, network),
  );

  test(
    'Today uses the enrolled schedule and accepts both upstream empty-day formats',
    () => HttpOverrides.runWithHttpOverrides(() async {
      var body = today();
      respond = (request) async {
        if (request.uri.path.endsWith('/infosimple')) return profile(request);
        expect(
          request.uri.path,
          endsWith('/courseapi/v2/schedule/get-week-schedules'),
        );
        expect(request.uri.queryParameters, {
          'user_id': '1',
          'tenant_id': '21',
          'start_at': '2026-10-27',
          'end_at': '2026-10-27',
        });
        return reply(request, body);
      };
      final classes = await repository.broadcasts(
        DateTime(2026, 10, 27),
        (_) async => null,
        CancellationToken(),
      );
      expect(classes.map((item) => item.lecture.status), [
        StudyLectureStatus.live,
        StudyLectureStatus.upcoming,
        StudyLectureStatus.recorded,
      ]);
      expect(classes.first.course.id, '17');
      body = {
        'success': true,
        'result': {'code': 400, 'msg': '课表为空'},
      };
      expect(
        await repository.broadcasts(
          DateTime(2026, 10, 27),
          (_) async => null,
          CancellationToken(),
        ),
        isEmpty,
      );
      body = {
        'success': true,
        'result': {
          'code': 200,
          'list': [
            {'day': '2026-10-27', 'course': []},
          ],
        },
      };
      expect(
        await repository.broadcasts(
          DateTime(2026, 10, 27),
          (_) async => null,
          CancellationToken(),
        ),
        isEmpty,
      );
    }, network),
  );

  test('Live playlists are fetched afresh and their relative segments retain the CDN route', () async {
    var sequence = 0;
    respond = (request) async {
      expect(request.headers.value('Referer'), 'https://aita.yanhekt.cn/');
      expect(request.uri.queryParameters.containsKey('t'), isFalse);
      if (request.uri.path.endsWith('.m3u8')) {
        expect(request.uri.queryParameters['auth_key'], 'cdn-token');
        request.response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
        );
        request.response.write(
          '#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:${++sequence}\n#EXTINF:10,\nsegment-$sequence.ts\n',
        );
      } else {
        expect(request.uri.path, '/clive11.yanhekt.cn/live/segment-2.ts');
        request.response.write('latest segment');
      }
      await request.response.close();
    };
    final proxy = HttpOverrides.runWithHttpOverrides(
      StudyMediaProxy.new,
      network,
    );
    addTearDown(proxy.close);
    final client = _NativeHttpOverrides().createHttpClient(null);
    addTearDown(client.close);
    const streams = LectureStreams(
      urls: {},
      duration: Duration.zero,
      signing: (user: '1', tenant: '21', phone: '123'),
      status: StudyLectureStatus.live,
    );
    final url = await proxy.open(
      Uri.parse(
        'https://clive11.yanhekt.cn/live/camera.m3u8?auth_key=cdn-token',
      ),
      streams,
    );
    String playlist = '';
    for (var index = 1; index <= 2; index++) {
      playlist = await utf8.decoder
          .bind(await (await client.getUrl(url)).close())
          .join();
      expect(playlist, contains('#EXT-X-MEDIA-SEQUENCE:$index'));
    }
    final segment = Uri.parse(playlist.trim().split('\n').last);
    expect(segment.host, '127.0.0.1');
    expect(
      await utf8.decoder
          .bind(await (await client.getUrl(segment)).close())
          .join(),
      'latest segment',
    );
  });

  test(
    'Saving a recording stops if the server reports a live stream',
    () => HttpOverrides.runWithHttpOverrides(() async {
      respond = (request) => request.uri.path.endsWith('/infosimple')
          ? profile(request)
          : reply(request, liveStreams());
      final controller = StudyController(
        store: MemoryStudyStore(),
        repository: repository,
      );
      addTearDown(controller.dispose);
      final course = StudyCourse(id: '17', title: '大学物理');
      const lecture = StudyLecture(id: '101', title: '课堂');
      final finished = Completer<void>();
      controller.tasks.addListener(() {
        if (controller.tasks.items.firstOrNull?.status ==
                StudyTaskStatus.failed &&
            !finished.isCompleted) {
          finished.complete();
        }
      });
      controller.download(course, lecture, (_) async => null, 'screen');
      await finished.future.timeout(const Duration(seconds: 5));
      expect((await controller.materials(course, lecture)).recordings, isEmpty);
    }, network),
  );

  for (final (size, scale) in [
    (const Size(320, 640), 1.0),
    (const Size(390, 844), 1.8),
    (const Size(1200, 800), 1.0),
  ]) {
    testWidgets('Live course, notes and today states at $size / $scale', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final detailServed = Completer<void>();
      final streamServed = Completer<void>();
      final dayServed = Completer<void>();
      respond = (request) async {
        if (request.uri.path.endsWith('/infosimple')) return profile(request);
        if (request.uri.path.endsWith('/get-course-detail')) {
          await reply(request, courseDetail());
          if (!detailServed.isCompleted) detailServed.complete();
        } else if (request.uri.path.endsWith('/get-week-schedules')) {
          await reply(request, today());
          if (!dayServed.isCompleted) dayServed.complete();
        } else {
          expect(request.uri.path, endsWith('/get-sub-info'));
          await reply(request, {
            'code': 0,
            'data': {'sub_status': '3'},
          });
          if (!streamServed.isCompleted) streamServed.complete();
        }
      };
      final app = TestAppController(schoolStorage: storage);
      await app.school.loadAccount();
      final course = StudyCourse(
        id: '17',
        title: '大学物理 AⅡ',
        lectures: [
          const StudyLecture(
            id: '101',
            title: '直播课时',
            status: StudyLectureStatus.live,
          ),
        ],
      );
      (app.study.store as MemoryStudyStore).courses = [course];
      await app.study.load();
      Widget screen(Widget home) => MaterialApp(
        theme: bitreeTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: home,
      );

      await HttpOverrides.runWithHttpOverrides(() async {
        await tester.pumpWidget(
          screen(StudyCourseScreen(app: app, courses: [course])),
        );
        await pumpHttp(tester, detailServed.future);
        expect(find.text('观看直播'), findsOneWidget);
        expect(find.text('录播'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('尚未开始'),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('尚未开始'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('录播生成中'),
          -160,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('录播生成中'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('观看直播'),
          -160,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('观看直播'));
        await tester.pump();
        await pumpHttp(tester, streamServed.future);
        expect(find.text('录播生成中'), findsOneWidget);
        expect(find.text('刷新状态'), findsOneWidget);
        expect(find.byType(Slider), findsNothing);
        expect(find.text('1.0×'), findsNothing);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('笔记').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('字幕'));
        await tester.pumpAndSettle();
        expect(find.text('直播结束后可获取平台字幕'), findsOneWidget);
        expect(find.text('获取平台字幕'), findsNothing);
        await tester.tap(find.text('课件'));
        await tester.pumpAndSettle();
        expect(find.text('直播结束后可提取课件'), findsOneWidget);
        expect(find.text('从课件录播提取'), findsNothing);
        await tester.tap(find.text('笔记'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, '直播中的笔记');
        await tester.pageBack();
        await tester.pumpAndSettle();
        final lecture = course.lectures.firstWhere(
          (lecture) => lecture.id == '101',
        );
        expect((await app.study.materials(course, lecture)).notes, '直播中的笔记');
        expect(app.study.lastReading, isNull);
        await tester.pumpWidget(
          screen(Scaffold(body: StudyTodayLiveList(app: app))),
        );
        await pumpHttp(tester, dayServed.future);
        expect(find.text('正在直播'), findsOneWidget);
        expect(find.text('即将开始'), findsOneWidget);
        expect(find.text('已结束 1'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }, network);
    });
  }

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
