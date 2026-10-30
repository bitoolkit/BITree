import 'dart:async';
import 'dart:io';

import 'package:bitree/agenda/controller.dart';
import 'package:bitree/agenda/model.dart';
import 'package:bitree/core/async/cancelable_request.dart';
import 'package:bitree/mooc/credentials.dart';
import 'package:bitree/schedule/model.dart';
import 'package:bitree/school/service.dart';
import 'package:bitree/school/session.dart';
import 'package:bitree/school/storage.dart';
import 'package:bitree/school/ui/school_import_button.dart';
import 'package:bitree/school/verification.dart';
import 'package:bitree/sync/controller.dart';
import 'package:bitree/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/http.dart';
import 'support/test_app.dart';

class _SchoolService extends SchoolService {
  final started = <String>[];
  final began = Completer<void>();
  final gates = <String, Completer<void>>{};
  bool smsRequired = false;

  @override
  Future<({SemesterSchedule schedule, List<String> terms})> synchronize(
    SchoolSession session, {
    required String account,
    String? term,
  }) async {
    final selected = term ?? '2026-2027-1';
    started.add('schedule:$selected');
    if (!began.isCompleted) began.complete();
    await gates[selected]?.future;
    if (smsRequired) {
      throw const SchoolVerificationRequired(SchoolVerificationKind.sms);
    }
    return (
      schedule: SemesterSchedule(
        term: selected,
        firstMonday: DateTime.utc(2026, 10, 26),
        courses: const [],
      ),
      terms: [selected],
    );
  }

  @override
  Future<({String term, List<AgendaEntry> exams})> exams(
    SchoolSession session, {
    required String account,
    String? term,
  }) async {
    started.add('exams');
    return (term: term ?? '2026-2027-1', exams: <AgendaEntry>[]);
  }
}

class _SlowAgendaStore extends MemoryAgendaStore {
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> write(List<AgendaEntry> entries) async {
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    await super.write(entries);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('bitree-sync-tests-');
    messenger.setMockMethodCallHandler(channel, (_) async => directory.path);
  });
  tearDownAll(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  late HttpServer probes;
  HttpOverrides? previousNetwork;
  setUp(() async {
    probes = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    probes.listen((request) async {
      await request.drain<void>();
      request.response.write('ok');
      await request.response.close();
    });
    previousNetwork = HttpOverrides.current;
    HttpOverrides.global = LocalHttpOverrides(probes.port);
  });
  tearDown(() async {
    HttpOverrides.global = previousNetwork;
    await probes.close(force: true);
  });

  TestAppController app(_SchoolService service, {bool mooc = false}) =>
      TestAppController(
        school: service,
        schoolStorage: MemorySchoolStorage(
          credentials: const SchoolCredentials(
            username: 'student',
            password: 'test',
          ),
        ),
        moocStorage: mooc
            ? (MemoryMoocStorage()
                ..account = MoocAccount(
                  id: '8',
                  name: '测试账号',
                  credentials: MoocCredentials(
                    userAgent: 'test',
                    cookies: [Cookie('NTESSTUDYSI', 'csrf')],
                  ),
                ))
            : null,
      );

  test('School tasks serialize, deduplicate and cancel queued work without starting it', () async {
    final service = _SchoolService();
    final gate = service.gates['2026-2027-1'] = Completer<void>();
    final model = app(service);
    await model.initialize();
    final first = model.sync.enqueue(SyncTarget.schedule, term: '2026-2027-1');
    final second = model.sync.enqueue(SyncTarget.exams);
    expect(model.sync.enqueue(SyncTarget.exams), same(second));
    await service.began.future;
    expect(first.phase, SyncPhase.running);
    expect(second.phase, SyncPhase.queued);
    expect(service.started, ['schedule:2026-2027-1']);
    model.sync.cancel(second);
    expect(await second.finished, isFalse);
    gate.complete();
    expect(await first.finished, isTrue);
    expect(service.started, ['schedule:2026-2027-1']);
    expect(model.timetable.schedule!.term, '2026-2027-1');
  });

  test('Cancelling a running school task does not publish it and releases the next task', () async {
    final service = _SchoolService();
    final gate = service.gates['2026-2027-1'] = Completer<void>();
    final model = app(service);
    await model.initialize();
    final first = model.sync.enqueue(SyncTarget.schedule);
    final next = model.sync.enqueue(SyncTarget.exams);
    await service.began.future;
    model.sync.cancel(first);
    gate.complete();
    expect(await first.finished, isFalse);
    expect(first.phase, SyncPhase.cancelled);
    expect(await next.finished, isTrue);
    expect(model.timetable.schedule, isNull);
  });

  test('Verification pauses the school queue until explicit verification and retry', () async {
    final service = _SchoolService()..smsRequired = true;
    final model = app(service);
    await model.initialize();
    final first = model.sync.enqueue(SyncTarget.schedule);
    final next = model.sync.enqueue(SyncTarget.exams);
    expect(await first.finished, isFalse);
    expect(first.phase, SyncPhase.attention);
    expect(model.school.verificationRequired, isTrue);
    expect(next.phase, SyncPhase.queued);
    expect(service.started, ['schedule:2026-2027-1']);
    service.smsRequired = false;
    await model.school.read(
      '手动验证',
      (_) async => true,
      verify: (_) async => null,
    );
    final retried = model.sync.retry(first);
    expect(await next.finished, isTrue);
    expect(await retried.finished, isTrue);
    expect(model.sync.activeCount, 0);
  });

  test('Concurrent platform writes retain all imports and cancelled waiting writes do not publish', () async {
    final store = _SlowAgendaStore();
    final agenda = AgendaController(store);
    addTearDown(agenda.dispose);
    await agenda.load();
    AgendaEntry entry(String id) => AgendaEntry(
      id: id,
      title: id,
      kind: AgendaKind.deadline,
      startsAt: DateTime.utc(2026, 11),
    );
    final first = agenda.mergeDeadlines([entry('school')]);
    await store.started.future;
    final second = agenda.mergeDeadlines([entry('mooc')]);
    final token = CancellationToken();
    final cancelled = expectLater(
      agenda.mergeDeadlines([entry('cancelled')], checkActive: token.check),
      throwsA(isA<RequestCancelled>()),
    );
    token.cancel();
    store.release.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    await cancelled;
    expect(agenda.entries.map((entry) => entry.id), ['school', 'mooc']);
    expect(store.entries.map((entry) => entry.id), ['school', 'mooc']);
  });

  Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
    final elapsed = Stopwatch()..start();
    while (!ready() && elapsed.elapsed < const Duration(seconds: 5)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(ready(), isTrue);
  }

  testWidgets(
    'Silent sync survives route changes, and the toolbar reopens its existing task',
    (tester) async {
      final service = _SchoolService();
      final gate = service.gates['2026-2027-1'] = Completer<void>();
      final model = app(service);
      await model.initialize();
      await tester.pumpWidget(
        MaterialApp(
          theme: bitreeTheme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(actions: [SchoolImportButton(controller: model)]),
              body: TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        Scaffold(appBar: AppBar(title: const Text('其他页面'))),
                  ),
                ),
                child: const Text('切换页面'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('导入'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('同步课表'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await waitFor(tester, () => service.began.isCompleted);
      expect(find.byType(BottomSheet), findsNothing);
      expect(model.sync.activeCount, 1);
      await tester.tap(find.byTooltip('查看同步进度'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('同步任务'), findsOneWidget);
      await tester.tap(find.text('收起'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(model.school.busy, isTrue);
      await tester.tap(find.text('切换页面'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      gate.complete();
      await waitFor(tester, () => model.sync.activeCount == 0);
      expect(model.timetable.schedule, isNotNull);
      expect(find.text('其他页面'), findsOneWidget);
      expect(find.text('课表同步完成'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'Task drawer appends work, runs MOOC alongside school, and fits a narrow $brightness screen',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final server = (await tester.runAsync(
          () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
        ))!;
        var requests = 0;
        server.listen((request) async {
          await request.drain<void>();
          if (!request.uri.path.startsWith('/www.icourse163.org/')) {
            request.response.write('ok');
            await request.response.close();
            return;
          }
          requests++;
          // Keep the real HTTP read pending until it is explicitly cancelled.
        });
        final previous = HttpOverrides.current;
        HttpOverrides.global = LocalHttpOverrides(server.port);
        addTearDown(() async {
          HttpOverrides.global = previous;
          await server.close(force: true);
        });
        final service = _SchoolService();
        final gate = service.gates['2026-2027-1'] = Completer<void>();
        final model = app(service, mooc: true);
        await model.initialize();
        model.sync.enqueue(SyncTarget.schedule);
        await tester.pumpWidget(
          MaterialApp(
            theme: bitreeTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.4)),
              child: child!,
            ),
            home: Scaffold(body: SchoolImportButton(controller: model)),
          ),
        );
        await tester.pump();
        await tester.tap(find.byTooltip('查看同步进度'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.byTooltip('添加同步任务'));
        await tester.pump();
        await tester.tap(find.text('考试安排'));
        await tester.ensureVisible(find.text('中国大学MOOC DDL'));
        await tester.tap(find.text('中国大学MOOC DDL'));
        await tester.pump();
        await tester.ensureVisible(find.text('添加 2 项同步'));
        await tester.tap(find.text('添加 2 项同步'));
        await tester.pump();
        await waitFor(tester, () => requests > 0);
        await waitFor(tester, () => service.began.isCompleted);
        expect(
          model.sync.tasks.where((task) => task.phase == SyncPhase.running),
          hasLength(2),
        );
        expect(
          model.sync.tasks
              .singleWhere((task) => task.target == SyncTarget.exams)
              .phase,
          SyncPhase.queued,
        );
        expect(find.text('等待学校请求完成'), findsOneWidget);
        await tester.ensureVisible(find.byTooltip('取消考试安排同步'));
        await tester.tap(find.byTooltip('取消考试安排同步'));
        await tester.pump();
        expect(service.started, ['schedule:2026-2027-1']);
        await tester.ensureVisible(find.text('重试'));
        await tester.tap(find.text('重试'));
        await tester.pump();
        expect(
          model.sync.tasks
              .singleWhere((task) => task.target == SyncTarget.exams)
              .phase,
          SyncPhase.queued,
        );
        await tester.tap(find.byTooltip('取消考试安排同步'));
        await tester.pump();
        await tester.ensureVisible(find.byTooltip('取消中国大学MOOC DDL同步'));
        await tester.tap(find.byTooltip('取消中国大学MOOC DDL同步'));
        await waitFor(tester, () => !model.mooc.busy);
        expect(model.school.busy, isTrue);
        expect(model.sync.activeCount, 1);
        await tester.tap(find.text('收起'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        gate.complete();
        await waitFor(tester, () => model.sync.activeCount == 0);
        await tester.pump(const Duration(seconds: 6));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
