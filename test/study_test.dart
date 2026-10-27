import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bitree/app/ui/app_screen.dart';
import 'package:bitree/core/async/cancelable_request.dart';
import 'package:bitree/study/controller.dart';
import 'package:bitree/study/llm.dart';
import 'package:bitree/study/media.dart';
import 'package:bitree/study/model.dart';
import 'package:bitree/study/store.dart';
import 'package:bitree/study/tasks.dart';
import 'package:bitree/study/ui/study_course.dart';
import 'package:bitree/study/yanhekt.dart';
import 'package:bitree/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

class _NativeHttpOverrides extends HttpOverrides {}

void main() {
  test('Lecture materials round trip without crossing course or lecture boundaries', () async {
    final directory = await Directory.systemTemp.createTemp('bitree-study-');
    addTearDown(() => directory.delete(recursive: true));
    final store = StudyStore(directory: directory);
    await Future.wait([
      store.writeMaterials('physics', 'first', LectureMaterials(notes: '机械振动')),
      store.writeMaterials('physics', 'second', LectureMaterials(notes: '波动')),
      store.writeMaterials('math', 'first', LectureMaterials(notes: '概率')),
    ]);
    expect((await store.readMaterials('physics', 'first')).notes, '机械振动');
    expect((await store.readMaterials('physics', 'second')).notes, '波动');
    expect((await store.readMaterials('math', 'first')).notes, '概率');
    expect(
      () => store.lectureDirectory('../other', 'first'),
      throwsFormatException,
    );
  });

  test('Transcript imports retain timestamps, multiline cues and ordering', () {
    final subtitles = parseTranscript(
      'WEBVTT\n\n00:01:02.300 --> 00:01:08.500\n第一行\n第二行\n\n',
    );
    expect(subtitles.single.start, const Duration(milliseconds: 62300));
    expect(subtitles.single.end, const Duration(milliseconds: 68500));
    expect(subtitles.single.text, '第一行\n第二行');
    final text = parseTranscript('[12:40] 后一段\n[00:05] 前一段');
    expect(text.map((row) => row.text), ['前一段', '后一段']);
  });

  test(
    'HLS resolves variants, segments, encryption keys and initialization maps',
    () async {
      final result = await rewritePlaylist(
        '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n'
        '#EXT-X-MAP:URI="init.mp4"\n#EXTINF:10,\nsegment.ts\n',
        (url) async => 'local/$url',
      );
      expect(result, contains('URI="local/key.bin"'));
      expect(result, contains('URI="local/init.mp4"'));
      expect(result, contains('\nlocal/segment.ts\n'));
    },
  );

  test('Task queue limits concurrency, rejects duplicate active work and resumes pauses', () async {
    final queue = StudyTasks();
    addTearDown(queue.dispose);
    final releases = List.generate(3, (_) => Completer<void>());
    final started = <int>[];
    var active = 0;
    var maximum = 0;
    StudyTask job(int index) => StudyTask(
      key: '$index',
      title: 'job',
      course: 'course',
      lecture: '$index',
      operation: (cancel, _) async {
        started.add(index);
        active++;
        if (active > maximum) maximum = active;
        final stopped = Completer<void>();
        final detach = cancel.onCancel(() => stopped.complete());
        try {
          await Future.any([releases[index].future, stopped.future]);
          cancel.check();
        } finally {
          detach();
          active--;
        }
      },
    );
    final first = job(0);
    queue.add(first);
    queue.add(job(0));
    queue.add(job(1));
    queue.add(job(2));
    expect(started, [0, 1]);
    expect(queue.items.length, 3);
    queue.pause(first);
    await Future<void>.delayed(Duration.zero);
    expect(first.status, StudyTaskStatus.paused);
    expect(started, [0, 1, 2]);
    queue.resume(first);
    releases[1].complete();
    releases[2].complete();
    await Future<void>.delayed(Duration.zero);
    releases[0].complete();
    await Future<void>.delayed(Duration.zero);
    expect(maximum, 2);
    expect(first.status, StudyTaskStatus.completed);
  });

  test('Interrupted recordings resume their saved bytes', () async {
    final directory = await Directory.systemTemp.createTemp('bitree-download-');
    addTearDown(() => directory.delete(recursive: true));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    var requests = 0;
    server.listen((request) async {
      requests++;
      request.response.bufferOutput = false;
      try {
        if (requests == 1) {
          request.response.contentLength = 6;
          request.response.add([1, 2, 3]);
          await request.response.flush();
          await release.future;
          request.response.add([4, 5, 6]);
        } else {
          expect(request.headers.value('Range'), 'bytes=3-');
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set('Content-Range', 'bytes 3-5/6');
          request.response.contentLength = 3;
          request.response.add([4, 5, 6]);
        }
        await request.response.close();
      } catch (failure) {
        if (failure is! HttpException && failure is! SocketException) rethrow;
      }
    });
    const streams = LectureStreams(
      urls: {},
      duration: Duration(seconds: 1),
      user: '1',
      tenant: '21',
      phone: '123',
    );
    final url = Uri.parse('http://127.0.0.1:${server.port}/recording.mp4');
    final cancel = CancellationToken();
    final received = Completer<void>();
    await HttpOverrides.runWithHttpOverrides(() async {
      final first = StudyDownloader().download(
        url,
        streams,
        directory,
        cancel,
        (value, _) {
          if (value != null && value >= .5 && !received.isCompleted) {
            received.complete();
          }
        },
      );
      final stopped = expectLater(first, throwsA(isA<RequestCancelled>()));
      await received.future.timeout(const Duration(seconds: 5));
      cancel.cancel();
      await stopped;
      release.complete();
      final file = await StudyDownloader().download(
        url,
        streams,
        directory,
        CancellationToken(),
        (_, _) {},
      );
      expect(await file.readAsBytes(), [1, 2, 3, 4, 5, 6]);
      expect(requests, 2);
    }, _NativeHttpOverrides());
  });

  test('SDK streams before completion and stopping keeps partial output in its lecture', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final sent = Completer<void>();
    final release = Completer<void>();
    final ended = Completer<void>();
    Map<String, dynamic>? body;
    server.listen((request) async {
      try {
        expect(request.uri.path, '/v1/chat/completions');
        expect(request.headers.value('Authorization'), 'Bearer test-key');
        body = jsonDecode(
          await utf8.decoder.bind(request).join(),
        ) as Map<String, dynamic>;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        request.response.bufferOutput = false;
        request.response.write(
          'data: ${jsonEncode({
            'id': 'reply',
            'object': 'chat.completion.chunk',
            'created': 1,
            'model': 'local-model',
            'choices': [
              {
                'index': 0,
                'delta': {'content': '已生成的部分'},
                'finish_reason': null,
              },
            ],
          })}\n\n',
        );
        await request.response.flush();
        sent.complete();
        await release.future;
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
      } catch (failure) {
        if (failure is! HttpException && failure is! SocketException) rethrow;
      } finally {
        ended.complete();
      }
    });
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    final directory = await Directory.systemTemp.createTemp('bitree-stream-');
    addTearDown(() => directory.delete(recursive: true));
    final controller = StudyController(
      store: StudyStore(directory: directory),
      repository: YanhektRepository(MemorySchoolStorage()),
    );
    addTearDown(controller.dispose);
    final course = await controller.addLocalCourse('大学物理');
    const lecture = StudyLecture(id: 'lecture', title: '机械振动');
    course.lectures = [lecture];
    final material = await controller.materials(course, lecture);
    material.transcript = [
      const TranscriptSegment(
        Duration.zero,
        Duration(seconds: 30),
        '简谐振动的能量守恒',
      ),
    ];
    final received = Completer<void>();
    controller.tasks.addListener(() {
      final task = controller.generation(course, lecture, 'summary');
      if (task?.output == '已生成的部分' && !received.isCompleted) {
        received.complete();
      }
    });
    HttpOverrides.runWithHttpOverrides(
      () => controller.generate(
        course,
        lecture,
        StudyModelSettings(
          endpoint: 'http://127.0.0.1:${server.port}/v1',
          model: 'local-model',
          apiKey: 'test-key',
        ),
      ),
      _NativeHttpOverrides(),
    );
    await sent.future.timeout(const Duration(seconds: 5));
    await received.future.timeout(const Duration(seconds: 5));
    final task = controller.generation(course, lecture, 'summary')!;
    expect(task.status, StudyTaskStatus.running);
    expect(body!['stream'], isTrue);
    expect(jsonEncode(body!['messages']), contains('简谐振动的能量守恒'));
    final saved = Completer<void>();
    controller.tasks.addListener(() {
      if (material.summary == '已生成的部分' && !saved.isCompleted) saved.complete();
    });
    controller.tasks.cancel(task);
    release.complete();
    await ended.future;
    // Wait for the SDK abort and the resulting local write to finish.
    await saved.future.timeout(const Duration(seconds: 5));
    expect(
      (await controller.store.readMaterials(course.id, lecture.id)).summary,
      '已生成的部分',
    );
    expect(task.status, StudyTaskStatus.cancelled);
    expect(
      (await controller.materials(
        course,
        const StudyLecture(id: 'other', title: '另一节'),
      )).summary,
      isEmpty,
    );
  });

  for (final (size, scale) in [
    (const Size(320, 640), 1.0),
    (const Size(390, 844), 1.8),
    (const Size(1200, 800), 1.0),
  ]) {
    testWidgets(
      'Each lecture opens its own notes and materials at $size / $scale',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = TestAppController();
        final course = await app.study.addLocalCourse('大学物理 AⅡ');
        course.lectures = [
          const StudyLecture(id: 'one', title: '机械振动'),
          const StudyLecture(id: 'two', title: '简谐振动的能量'),
        ];
        (await app.study.materials(course, course.lectures[0])).notes =
            '第一节的笔记';
        (await app.study.materials(course, course.lectures[1])).notes =
            '第二节的笔记';
        await tester.pumpWidget(
          MaterialApp(
            theme: bitreeTheme(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: StudyCourseScreen(app: app, course: course),
          ),
        );
        expect(find.text('录播'), findsNWidgets(2));
        expect(find.text('课件'), findsNWidgets(2));
        await tester.tap(find.text('笔记').last);
        await tester.pumpAndSettle();
        expect(find.text('第二节的笔记'), findsOneWidget);
        expect(find.text('第一节的笔记'), findsNothing);
        await tester.enterText(find.byType(TextField).first, '修改后的第二节笔记');
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          (await app.study.materials(course, course.lectures[1])).notes,
          '修改后的第二节笔记',
        );
        expect(
          (await app.study.materials(course, course.lectures[0])).notes,
          '第一节的笔记',
        );
        await tester.tap(find.text('课件').first);
        await tester.pumpAndSettle();
        expect(find.text('还没有课件'), findsOneWidget);
        expect(find.text('观看录播'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('Learning is the central destination among five', (tester) async {
    final app = TestAppController();
    await tester.pumpWidget(
      MaterialApp(
        theme: bitreeTheme(Brightness.light),
        home: AppScreen(controller: app),
      ),
    );
    final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navigation.destinations.length, 5);
    expect((navigation.destinations[2] as NavigationDestination).label, '学习');
    await tester.tap(find.text('学习'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('获取我的课程'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
