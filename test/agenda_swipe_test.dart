import 'package:bitree/agenda/model.dart';
import 'package:bitree/agenda/ui/calendar_screen.dart';
import 'package:bitree/agenda/view_mode.dart';
import 'package:bitree/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

void main() {
  Future<TestAppController> showAgenda(WidgetTester tester) async {
    final app = TestAppController(
      entries: [
        AgendaEntry(
          id: 'task',
          title: '第三章作业',
          kind: AgendaKind.deadline,
          startsAt: DateTime.utc(2099, 1, 2, 23, 59),
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
    'A left swipe deletes through the real agenda and list removal animation',
    (tester) async {
      final app = await showAgenda(tester);
      await tester.drag(
        find.byKey(const ValueKey('task')),
        const Offset(-140, 0),
      );
      await tester.pumpAndSettle();
      expect(app.agenda.entries, isEmpty);
      expect(app.agenda.deletedDeadlines.single.id, 'task');
      expect(find.text('第三章作业'), findsNothing);
      expect(find.text('未完成 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('A right swipe moves the deadline to the completed page', (
    tester,
  ) async {
    final app = await showAgenda(tester);
    await tester.drag(find.byKey(const ValueKey('task')), const Offset(140, 0));
    await tester.pumpAndSettle();
    expect(app.agenda.entries.single.done, isTrue);
    expect(find.text('未完成 0'), findsOneWidget);
    await tester.tap(find.text('已完成 1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task')).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Swiping away deletion feedback keeps the deadline deleted', (
    tester,
  ) async {
    final app = await showAgenda(tester);
    await tester.drag(
      find.byKey(const ValueKey('task')),
      const Offset(-140, 0),
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
      await tester.drag(
        find.byKey(const ValueKey('task')),
        const Offset(-140, 0),
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
}
