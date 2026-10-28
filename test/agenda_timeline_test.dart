import 'package:bitree/agenda/model.dart';
import 'package:bitree/agenda/timeline_layout.dart';
import 'package:bitree/agenda/ui/agenda_timeline.dart';
import 'package:bitree/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

final _date = DateTime.utc(2026, 11, 17);

AgendaEntry _event(String id, int hour, {bool exam = false}) => AgendaEntry(
  id: id,
  title: exam ? '数据结构考试' : '短日程$id',
  kind: exam ? AgendaKind.exam : AgendaKind.event,
  startsAt: _date.add(Duration(hours: hour)),
  endsAt: _date.add(Duration(hours: hour, minutes: 5)),
);

Finder _bar(AgendaEntry entry) => find.bySemanticsLabel(
  RegExp('^${RegExp.escape('${entry.kind.label}，${entry.title}，')}'),
);

Finder _paintedBar(AgendaEntry entry) =>
    find.byKey(ValueKey(('agenda-timeline-bar', entry.id)));

Future<TestAppController> _show(
  WidgetTester tester,
  List<AgendaEntry> entries, {
  double scale = 1,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final app = TestAppController(entries: entries);
  await app.initialize();
  await tester.pumpWidget(
    MaterialApp(
      theme: bitreeTheme(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: AgendaTimeline(
          controller: app,
          entries: entries,
          now: _date.add(const Duration(hours: 12)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return app;
}

void main() {
  test('Minimum display spans separate short events without changing their real times', () {
    final first = _event('first', 11);
    final second = _event('second', 14, exam: true);
    final entries = [first, second];
    final zoomedOut = layoutAgendaTimeline(
      entries,
      minimumEventSpan: const Duration(hours: 48),
    );
    expect(zoomedOut.map((placement) => placement.lane), [0, 1]);
    expect(zoomedOut.first.start, first.startsAt);
    expect(zoomedOut.first.end, first.endsAt);
    expect(
      zoomedOut.first.layoutEnd,
      first.startsAt.add(const Duration(hours: 48)),
    );
    final zoomedIn = layoutAgendaTimeline(
      entries,
      minimumEventSpan: const Duration(hours: 2),
    );
    expect(zoomedIn.map((placement) => placement.lane), [0, 0]);
    expect(zoomedIn.map((placement) => placement.end), [
      first.endsAt,
      second.endsAt,
    ]);
  });

  test('Long events and DDL reservations retain their full intervals', () {
    final long = AgendaEntry(
      id: 'long',
      title: '多日日程',
      kind: AgendaKind.event,
      startsAt: _date,
      endsAt: _date.add(const Duration(days: 5)),
    );
    final ddl = AgendaEntry(
      id: 'ddl',
      title: '作业',
      kind: AgendaKind.deadline,
      startsAt: _date.add(const Duration(hours: 13)),
    );
    final placements = layoutAgendaTimeline([
      long,
      ddl,
    ], minimumEventSpan: const Duration(days: 2));
    final eventPlacement = placements.singleWhere(
      (placement) => placement.entry == long,
    );
    final deadlinePlacement = placements.singleWhere(
      (placement) => placement.entry == ddl,
    );
    expect(eventPlacement.layoutEnd, long.endsAt);
    expect(
      deadlinePlacement.start,
      ddl.dueAt.subtract(const Duration(days: 4)),
    );
    expect(deadlinePlacement.layoutEnd, ddl.dueAt);
  });

  for (final (brightness, scale) in [
    (Brightness.light, 1.0),
    (Brightness.dark, 1.6),
  ]) {
    testWidgets(
      'Short cards keep a fixed 2px minimum and stay tappable in $brightness, $scale',
      (tester) async {
        final first = _event('first', 11);
        final second = _event('second', 14, exam: true);
        final ddl = AgendaEntry(
          id: 'ddl',
          title: '第五章作业',
          kind: AgendaKind.deadline,
          startsAt: _date.add(const Duration(hours: 13)),
        );
        final entries = [first, second, ddl];
        final app = await _show(
          tester,
          entries,
          scale: scale,
          brightness: brightness,
        );
        final viewport = tester.getRect(find.byType(AgendaTimeline));
        void checkCards(double eventWidth) {
          final rectangles = entries
              .map((entry) => tester.getRect(_paintedBar(entry)))
              .toList();
          expect(rectangles.first.width, closeTo(eventWidth, .001));
          expect(
            rectangles[1].width,
            closeTo(
              eventWidth.clamp(0, viewport.right - rectangles[1].left),
              .001,
            ),
          );
          expect(rectangles.last.width, closeTo(180, .001));
          for (var index = 0; index < rectangles.length; index++) {
            for (var other = index + 1; other < rectangles.length; other++) {
              expect(rectangles[index].overlaps(rectangles[other]), isFalse);
            }
          }
          expect(
            tester.getSemantics(_bar(first)).label,
            contains('11:00–11:05'),
          );
          expect(tester.takeException(), isNull);
        }

        checkCards(2);
        tester.widget<Slider>(find.byType(Slider)).onChanged!(24);
        await tester.pumpAndSettle();
        // At 48px/hour, the real five-minute duration is 4px, above the 2px floor.
        checkCards(4);
        final short = tester.getRect(_bar(first));
        await tester.tapAt(Offset(short.right - 12, short.center.dy));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text(first.title),
          ),
          findsWidgets,
        );
        expect(app.agenda.entries, orderedEquals(entries));
        expect(first.endsAt, _date.add(const Duration(hours: 11, minutes: 5)));
        await tester.tap(find.byTooltip('关闭'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'A minimum-width card stays visible after its real end leaves the viewport',
    (tester) async {
      final beforeViewport = _date
          .subtract(const Duration(days: 4))
          .add(const Duration(hours: 10));
      final entry = AgendaEntry(
        id: 'edge',
        title: '边缘短日程',
        kind: AgendaKind.event,
        startsAt: beforeViewport,
        endsAt: beforeViewport.add(const Duration(minutes: 5)),
      );
      await _show(tester, [entry]);
      final painted = tester.getRect(_paintedBar(entry));
      expect(painted.left, 0);
      // Half of the 2px bar is clipped at the left edge; its hit target is wider.
      expect(painted.width, closeTo(1, .001));
      final card = tester.getRect(_bar(entry));
      await tester.tapAt(card.center);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
