import 'package:bitree/agenda/calendar.dart';
import 'package:bitree/agenda/controller.dart';
import 'package:bitree/agenda/model.dart';
import 'package:bitree/app_controller.dart';
import 'package:bitree/schedule/layout.dart';
import 'package:bitree/schedule/model.dart';
import 'package:bitree/ui/add_menu.dart';
import 'package:bitree/ui/app_dropdown_field.dart';
import 'package:bitree/ui/theme.dart';
import 'package:bitree/ui/timetable_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Agenda extends ChangeNotifier with Fake implements AgendaController {
  _Agenda(this.entries);

  @override
  final List<AgendaEntry> entries;
  @override
  bool get ready => true;
  @override
  bool get busy => false;
}

class _Controller extends ChangeNotifier with Fake implements AppController {
  _Controller(this.schedule, this.agenda);

  @override
  final SemesterSchedule schedule;
  @override
  final _Agenda agenda;
  @override
  bool get busy => false;

  @override
  void dispose() {
    agenda.dispose();
    super.dispose();
  }
}

void main() {
  const rowHeight = 64.0;
  const gutterWidth = 64.0;
  final monday = DateTime.utc(2026, 10, 26);
  final course = Course(
    id: 'course',
    name: '离散数学',
    weekday: DateTime.friday,
    startSection: 3,
    endSection: 4,
    weeks: [1],
  );
  final event = AgendaEntry(
    id: 'event',
    title: '羽毛球',
    kind: AgendaKind.event,
    startsAt: DateTime.utc(2026, 10, 31, 11, 35),
    endsAt: DateTime.utc(2026, 10, 31, 12, 20),
  );
  final schedule = SemesterSchedule(
    term: '2026-2027-1',
    firstMonday: monday,
    courses: [course],
  );
  final addCourse = find.widgetWithText(MenuItemButton, '添加课程');

  Future<void> showGrid(
    WidgetTester tester, {
    VoidCallback? onOutsideTap,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = _Controller(schedule, _Agenda([event]));
    final time = ValueNotifier(DateTime.utc(2026, 10, 27, 8));
    addTearDown(controller.dispose);
    addTearDown(time.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: bitreeTheme(Brightness.light),
        home: Scaffold(
          appBar: AppBar(
            title: const Text('课表'),
            actions: [
              IconButton(
                tooltip: '其他操作',
                onPressed: onOutsideTap ?? () {},
                icon: const Icon(Icons.more_horiz),
              ),
            ],
          ),
          body: SingleChildScrollView(
            child: TimetableGrid(
              controller: controller,
              monday: monday,
              layouts: [
                for (var day = 0; day < 7; day++)
                  groupCalendarItems(
                    calendarItemsOn(monday.add(Duration(days: day)), schedule, [
                      event,
                    ]),
                    monday.add(Duration(days: day)),
                  ),
              ],
              gutterWidth: gutterWidth,
              rowHeight: rowHeight,
              todayColumn: null,
              todayBackground: Colors.transparent,
              currentTime: time,
            ),
          ),
        ),
      ),
    );
  }

  Offset cell(WidgetTester tester, int day, int section) {
    final grid = tester.getRect(find.byType(TimetableGrid));
    final width = (grid.width - gutterWidth) / 7;
    return grid.topLeft +
        Offset(gutterWidth + (day + 0.5) * width, (section - 0.5) * rowHeight);
  }

  Future<void> openMenu(
    WidgetTester tester, {
    int day = 0,
    int section = 2,
  }) async {
    await tester.tapAt(cell(tester, day, section));
    await tester.pumpAndSettle();
    expect(addCourse, findsOneWidget);
  }

  void expectClosed(WidgetTester tester) {
    expect(addCourse, findsNothing);
    expect(tester.widget<AddMenu>(find.byType(AddMenu)).selection, isNull);
    expect(tester.takeException(), isNull);
  }

  for (final sameCell in [true, false]) {
    testWidgets(
      'Tapping ${sameCell ? 'the selected' : 'another'} empty cell only closes the menu',
      (tester) async {
        await showGrid(tester);
        await openMenu(tester);
        await tester.tapAt(
          sameCell
              ? cell(tester, 0, 2) - const Offset(30, 20)
              : cell(tester, 6, 6),
        );
        await tester.pumpAndSettle();
        expectClosed(tester);

        await openMenu(tester, day: 6, section: 6);
        final selection = tester
            .widget<AddMenu>(find.byType(AddMenu))
            .selection!;
        expect(selection.date.weekday, DateTime.sunday);
        expect(selection.startSection, 6);
      },
    );
  }

  for (final occupied in [(day: 4, section: 3), (day: 5, section: 5)]) {
    testWidgets(
      'Tapping an occupied cell ${occupied.day} closes the menu and opens details',
      (tester) async {
        await showGrid(tester);
        await openMenu(tester);
        await tester.tapAt(cell(tester, occupied.day, occupied.section));
        await tester.pumpAndSettle();
        expectClosed(tester);
        expect(find.byType(BottomSheet), findsOneWidget);
      },
    );
  }

  testWidgets('Outside controls still receive their tap', (tester) async {
    var taps = 0;
    await showGrid(tester, onOutsideTap: () => taps++);
    await openMenu(tester);
    await tester.tap(find.byTooltip('其他操作'));
    await tester.pumpAndSettle();
    expectClosed(tester);
    expect(taps, 1);
  });

  testWidgets('Menu actions retain the selected date and section', (
    tester,
  ) async {
    await showGrid(tester);
    await openMenu(tester, day: 6, section: 6);
    await tester.tap(addCourse);
    await tester.pumpAndSettle();
    expect(find.text('保存课程'), findsOneWidget);
    for (final field in [('星期', DateTime.sunday), ('开始节次', 6)]) {
      final finder = find.byWidgetPredicate(
        (widget) => widget is AppDropdownField<int> && widget.label == field.$1,
      );
      expect(tester.widget<AppDropdownField<int>>(finder).value, field.$2);
    }
    expect(tester.takeException(), isNull);
  });
}
