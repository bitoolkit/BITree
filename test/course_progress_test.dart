import 'package:bitree/agenda/calendar.dart';
import 'package:bitree/schedule/layout.dart';
import 'package:bitree/schedule/model.dart';
import 'package:bitree/schedule/selection.dart';
import 'package:bitree/schedule/ui/course_tile.dart';
import 'package:bitree/schedule/ui/current_time_indicator.dart';
import 'package:bitree/schedule/ui/timetable_grid.dart';
import 'package:bitree/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

void main() {
  final date = DateTime.utc(2026, 10, 27);
  DateTime at(int hour, int minute) =>
      date.add(Duration(hours: hour, minutes: minute));
  final occurrence = TimetableSelection(
    date: date,
    startSection: 3,
    endSection: 4,
  );

  test('Progress follows section heights, including breaks, only during this occurrence', () {
    expect(occurrence.progressAt(at(9, 54)), isNull);
    expect(occurrence.progressAt(at(9, 55)), 0);
    expect(occurrence.progressAt(at(10, 10)), closeTo(1 / 6, 0.0001));
    expect(occurrence.progressAt(at(10, 42)), 0.5);
    expect(occurrence.progressAt(at(10, 55)), closeTo(0.5 + 1 / 9, 0.0001));
    expect(occurrence.progressAt(at(11, 28)), closeTo(1 - 1 / 45, 0.0001));
    expect(occurrence.progressAt(at(11, 30)), isNull);
    expect(occurrence.progressAt(at(21, 20)), isNull);
    expect(
      occurrence.progressAt(at(10, 10).add(const Duration(days: 7))),
      isNull,
    );
    expect(
      occurrence.progressAt(at(10, 10).subtract(const Duration(days: 7))),
      isNull,
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'Fill and line share the same frontier without changing text width in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(390, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final course = Course(
          id: 'probability',
          name: '概率论与数理统计',
          room: '文萃楼F704',
          weekday: 2,
          startSection: 3,
          endSection: 4,
          weeks: [1],
        );
        final schedule = SemesterSchedule(
          term: '2026-2027-1',
          firstMonday: mondayOf(date),
          courses: [course],
        );
        final controller = TestAppController(schedule: schedule);
        await controller.initialize();
        final time = ValueNotifier(at(9, 54));
        addTearDown(time.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: bitreeTheme(brightness),
            home: Scaffold(
              body: SingleChildScrollView(
                child: TimetableGrid(
                  controller: controller,
                  monday: mondayOf(date),
                  layouts: [
                    for (var day = 0; day < 7; day++)
                      groupCalendarItems(
                        calendarItemsOn(
                          mondayOf(date).add(Duration(days: day)),
                          schedule,
                          [],
                        ),
                        mondayOf(date).add(Duration(days: day)),
                      ),
                  ],
                  gutterWidth: 64,
                  rowHeight: 64,
                  todayColumn: 1,
                  todayBackground: Colors.transparent,
                  currentTime: time,
                ),
              ),
            ),
          ),
        );
        final title = find.text(course.name);
        final room = find.text(course.room);
        final initialWidth = tester.getSize(title).width;
        final initialRoomWidth = tester.getSize(room).width;
        final initialCard = tester.getRect(find.byType(CourseTile));
        final fill = find.descendant(
          of: find.byType(CourseTile),
          matching: find.byType(FractionallySizedBox),
        );
        expect(fill, findsNothing);
        for (final clock in [(10, 10), (10, 42), (10, 55), (11, 28)]) {
          time.value = at(clock.$1, clock.$2);
          await tester.pump();
          final layer = find.descendant(
            of: fill,
            matching: find.byType(ColoredBox),
          );
          final frontier = tester.getRect(layer).bottom;
          final line = find.descendant(
            of: fill,
            matching: find.byType(DecoratedBox),
          );
          expect(tester.getRect(line).center.dy, closeTo(frontier, 0.001));
          expect(tester.getSize(line).height, 2);
          final color =
              (tester.widget<DecoratedBox>(line).decoration as BoxDecoration)
                  .color;
          expect(color, courseColors(tester.element(title), course).accent);
          expect(tester.getSize(title).width, initialWidth);
          expect(tester.getSize(room).width, initialRoomWidth);
          expect(tester.getRect(find.byType(CourseTile)), initialCard);
          final material = tester.widget<Material>(
            find
                .descendant(
                  of: find.byType(CourseTile),
                  matching: find.byType(Material),
                )
                .first,
          );
          final side = (material.shape! as RoundedRectangleBorder).side;
          expect(side.width, 1.5);
          expect(
            side.color,
            courseColors(tester.element(title), course).accent,
          );
          expect(tester.takeException(), isNull);
        }
        time.value = at(11, 30);
        await tester.pump();
        expect(fill, findsNothing);
        final cardMaterial = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(CourseTile),
                matching: find.byType(Material),
              )
              .first,
        );
        expect((cardMaterial.shape! as RoundedRectangleBorder).side.width, 1.5);
        time.value = at(21, 20);
        await tester.pump();
        expect(fill, findsNothing);
        final line = find.descendant(
          of: find.byType(CurrentTimeIndicator),
          matching: find.byType(DecoratedBox),
        );
        final grid = tester.getRect(find.byType(TimetableGrid));
        expect(tester.getRect(line).top, grid.top);
        expect(
          tester.getRect(line).left,
          closeTo(grid.left + 64 + 2 * (326 / 7) + 3, 0.001),
        );
        time.value = at(10, 55).add(const Duration(days: 7));
        await tester.pump();
        expect(fill, findsNothing);
        expect(line, findsNothing);
      },
    );
  }
}
