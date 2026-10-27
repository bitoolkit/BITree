import 'package:bitree/agenda/model.dart';
import 'package:bitree/agenda/ui/calendar_screen.dart';
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
}
