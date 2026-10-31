import 'package:bitree/agenda/model.dart';
import 'package:bitree/agenda/ui/calendar_screen.dart';
import 'package:bitree/agenda/view_mode.dart';
import 'package:bitree/ui/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/held_swipe.dart';
import 'support/test_app.dart';

void main() {
  Future<TestAppController> showAgenda(
    WidgetTester tester, {
    AgendaKind kind = AgendaKind.deadline,
    int count = 1,
    bool deleted = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final app = TestAppController(
      entries: [
        for (var index = 0; index < count; index++)
          AgendaEntry(
            id: index == 0 ? 'task' : 'task$index',
            title: index == 0 ? '第三章作业' : '作业 $index',
            kind: kind,
            startsAt: DateTime.utc(2099, 1, 2, 20),
            endsAt: kind == AgendaKind.deadline
                ? null
                : DateTime.utc(2099, 1, 2, 21),
            deleted: deleted,
          ),
      ],
    );
    await app.initialize();
    await app.setAgendaViewMode(AgendaViewMode.list);
    await tester.pumpWidget(
      MaterialApp(
        theme: bitreeTheme(Brightness.light),
        home: Scaffold(
          body: CalendarScreen(controller: app, now: DateTime.utc(2099, 1, 1)),
        ),
      ),
    );
    return app;
  }

  testWidgets(
    'A held right swipe deletes through the real agenda and list removal animation',
    (tester) async {
      final app = await showAgenda(tester);
      await heldSwipe(
        tester,
        find.byKey(const ValueKey('task')),
        const Offset(200, 0),
      );
      await tester.pumpAndSettle();
      expect(app.agenda.entries, isEmpty);
      expect(app.agenda.deletedDeadlines.single.id, 'task');
      expect(find.text('第三章作业'), findsNothing);
      expect(find.text('未完成 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('A held left swipe moves the deadline to the completed page', (
    tester,
  ) async {
    final app = await showAgenda(tester);
    await heldSwipe(
      tester,
      find.byKey(const ValueKey('task')),
      const Offset(-200, 0),
    );
    await tester.pumpAndSettle();
    expect(app.agenda.entries.single.done, isTrue);
    expect(find.text('未完成 0'), findsOneWidget);
    await tester.tap(find.text('已完成 1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task')).hitTestable(), findsOneWidget);
    await heldSwipe(
      tester,
      find.byKey(const ValueKey('task')).hitTestable(),
      const Offset(-200, 0),
    );
    await tester.pumpAndSettle();
    expect(app.agenda.entries.single.done, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Swiping away deletion feedback keeps the deadline deleted', (
    tester,
  ) async {
    final app = await showAgenda(tester);
    await heldSwipe(
      tester,
      find.byKey(const ValueKey('task')),
      const Offset(200, 0),
    );
    await tester.pumpAndSettle();
    await tester.fling(find.text('已删除“第三章作业”'), const Offset(240, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('撤销'), findsNothing);
    expect(app.agenda.entries, isEmpty);
    expect(app.agenda.deletedDeadlines.single.id, 'task');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Undo restores the deadline and recovery feedback expires after two seconds',
    (tester) async {
      final app = await showAgenda(tester);
      await heldSwipe(
        tester,
        find.byKey(const ValueKey('task')),
        const Offset(200, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(app.agenda.entries.single.id, 'task');
      expect(app.agenda.deletedDeadlines, isEmpty);
      expect(find.text('已恢复“第三章作业”'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('已恢复“第三章作业”'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Deleted deadlines can be restored from the agenda header', (
    tester,
  ) async {
    final app = await showAgenda(tester, deleted: true);
    final restoreButton = find.byTooltip('已删除的 DDL');
    expect(restoreButton, findsOneWidget);

    await tester.tap(restoreButton);
    await tester.pumpAndSettle();
    expect(find.text('已删除的 DDL'), findsOneWidget);

    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    expect(app.agenda.entries.single.id, 'task');
    expect(app.agenda.deletedDeadlines, isEmpty);
    expect(restoreButton, findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets('An ordinary $kind swipe on a row changes page, not data', (
      tester,
    ) async {
      final app = await showAgenda(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('task'))),
        kind: kind,
      );
      await gesture.moveBy(
        const Offset(-35, 0),
        timeStamp: const Duration(milliseconds: 50),
      );
      await tester.pump();
      // A pause during an ongoing page drag must not turn it into a row action.
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.moveBy(
        const Offset(-210, 0),
        timeStamp: const Duration(milliseconds: 350),
      );
      await gesture.up(timeStamp: const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
      expect(app.agenda.entries.single.done, isFalse);
      expect(app.agenda.deletedDeadlines, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('A held diagonal drag scrolls without row actions', (
    tester,
  ) async {
    final app = await showAgenda(tester, count: 20);
    final row = find.byKey(const ValueKey('task11'));
    final before = tester.getTopLeft(row);
    final gesture = await tester.startGesture(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 250));
    await gesture.moveBy(
      const Offset(-20, -30),
      timeStamp: const Duration(milliseconds: 250),
    );
    await tester.pump();
    await gesture.moveBy(
      const Offset(0, -150),
      timeStamp: const Duration(milliseconds: 500),
    );
    await gesture.up(timeStamp: const Duration(milliseconds: 550));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(row).dy, lessThan(before.dy - 100));
    expect(app.agenda.entries, hasLength(20));
    expect(app.agenda.entries.every((entry) => !entry.done), isTrue);
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A trackpad swipe pages even after a pause on a row', (
    tester,
  ) async {
    final app = await showAgenda(tester);
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    final origin = tester.getCenter(find.byKey(const ValueKey('task')));
    await gesture.panZoomStart(origin);
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.panZoomUpdate(
      origin,
      pan: const Offset(-30, 0),
      timeStamp: const Duration(milliseconds: 300),
    );
    await gesture.panZoomUpdate(
      origin,
      pan: const Offset(-260, 0),
      timeStamp: const Duration(milliseconds: 600),
    );
    await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 650));
    await tester.pumpAndSettle();
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
    expect(app.agenda.entries.single.done, isFalse);
    expect(app.agenda.deletedDeadlines, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A schedule has only a right swipe delete action', (
    tester,
  ) async {
    final app = await showAgenda(tester, kind: AgendaKind.event);
    await heldSwipe(
      tester,
      find.byKey(const ValueKey('task')),
      const Offset(-240, 0),
    );
    await tester.pumpAndSettle();
    expect(app.agenda.entries.single.kind, AgendaKind.event);
    expect(app.agenda.entries.single.done, isFalse);
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
    await tester.tap(find.text('未完成 1'));
    await tester.pumpAndSettle();
    await heldSwipe(
      tester,
      find.byKey(const ValueKey('task')).hitTestable(),
      const Offset(200, 0),
    );
    await tester.pumpAndSettle();
    expect(app.agenda.entries, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
