import 'package:bitree/agenda/calendar.dart';
import 'package:bitree/agenda/controller.dart';
import 'package:bitree/agenda/deadline_source.dart';
import 'package:bitree/agenda/model.dart';
import 'package:bitree/app_controller.dart';
import 'package:bitree/data/agenda_store.dart';
import 'package:bitree/schedule/model.dart';
import 'package:bitree/ui/calendar_list.dart';
import 'package:bitree/ui/completion_text.dart';
import 'package:bitree/ui/sheet_layout.dart';
import 'package:bitree/ui/theme.dart';
import 'package:bitree/ui/timetable_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store extends AgendaStore {
  _Store(this.entries);
  List<AgendaEntry> entries;
  @override
  Future<List<AgendaEntry>> read() async => entries;
  @override
  Future<void> write(List<AgendaEntry> entries) async => this.entries = entries;
}

class _Controller extends ChangeNotifier with Fake implements AppController {
  _Controller(this.agenda);
  @override
  final AgendaController agenda;
  @override
  bool get busy => false;
}

final _date = calendarDate(campusNow()).add(const Duration(days: 5));

AgendaEntry _deadline({
  int id = 1,
  DateTime? date,
  bool done = false,
  bool detailed = false,
}) => AgendaEntry(
  id: 'deadline$id',
  title: detailed ? '第$id章实验报告：线性表与链表的实现、测试及复杂度分析' : '第五章作业$id',
  kind: AgendaKind.deadline,
  startsAt: (date ?? _date).add(
    Duration(hours: id == 1 ? 18 : 23, minutes: id == 1 ? 0 : 59),
  ),
  source: DeadlineSource.eclass,
  course: detailed ? '2026–2027 秋季学期 · 概率论与数理统计中文班' : '高数数学',
  done: done,
);

Future<_Controller> _open(
  WidgetTester tester,
  List<AgendaEntry> entries, {
  Size size = const Size(390, 844),
  double scale = 1,
  Brightness brightness = Brightness.light,
  List<CalendarItem>? picker,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final agenda = AgendaController(_Store(entries));
  await agenda.load();
  final controller = _Controller(agenda);
  addTearDown(agenda.dispose);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: bitreeTheme(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => picker == null
              ? TimetableHeader(
                  controller: controller,
                  monday: mondayOf(_date),
                  now: campusNow(),
                  gutterWidth: 40,
                  todayBackground: Colors.transparent,
                )
              : Center(
                  child: TextButton(
                    onPressed: () => showCalendarItems(
                      context,
                      controller,
                      '选择安排',
                      picker,
                      showDates: true,
                    ),
                    child: const Text('选择安排'),
                  ),
                ),
        ),
      ),
    ),
  );
  if (picker == null) {
    await tester.tap(
      find.bySemanticsLabel(
        RegExp('${_date.month}月${_date.day}日${weekdays[_date.weekday - 1]}'),
      ),
    );
  } else {
    await tester.tap(find.text('选择安排'));
  }
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return controller;
}

void main() {
  testWidgets(
    'Tapping the timetable date shows compact pending entries with prominent times',
    (tester) async {
      final entry = _deadline();
      await _open(tester, [
        entry,
        _deadline(id: 2, done: true),
        _deadline(id: 3, date: _date.add(const Duration(days: 1))),
      ]);
      expect(find.text(agendaDateLabel(_date)), findsOneWidget);
      expect(find.text('1项日程'), findsOneWidget);
      expect(find.text(entry.title), findsWidgets);
      expect(find.text('第五章作业2'), findsNothing);
      expect(find.text('第五章作业3'), findsNothing);
      expect(find.text('DDL · 新延河课堂'), findsOneWidget);
      expect(find.text('高数数学'), findsOneWidget);
      expect(find.text('18:00'), findsOneWidget);
      expect(find.text('截止'), findsOneWidget);
      final time = tester.widget<Text>(find.text('18:00'));
      final source = tester.widget<Text>(find.text('DDL · 新延河课堂'));
      expect(time.style!.fontSize, greaterThan(source.style!.fontSize!));
      expect(tester.getSize(find.byType(BottomSheet)).height, lessThan(350));
    },
  );

  testWidgets(
    'A day entry opens the existing detail sheet without leaving two sheets',
    (tester) async {
      final entry = _deadline();
      await _open(tester, [entry]);
      await tester.tap(find.text(entry.title).first);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('1项日程'), findsNothing);
      expect(find.text('标记完成'), findsOneWidget);
      expect(find.text('18:00  截止', findRichText: true), findsOneWidget);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (size, scale, brightness) in [
    (const Size(320, 640), 1.0, Brightness.light),
    (const Size(320, 640), 1.8, Brightness.dark),
    (const Size(390, 844), 1.6, Brightness.light),
    (const Size(1440, 900), 1.0, Brightness.dark),
  ]) {
    testWidgets(
      'Long day lists scroll with a reachable fixed header at $size, $scale',
      (tester) async {
        final entries = [
          for (var id = 1; id <= 12; id++) _deadline(id: id, detailed: true),
        ];
        await _open(
          tester,
          entries,
          size: size,
          scale: scale,
          brightness: brightness,
        );
        final closeBefore = tester.getRect(find.byTooltip('关闭'));
        await tester.scrollUntilVisible(
          find.text(entries.last.title).first,
          200,
          scrollable: find
              .descendant(
                of: find.byType(SheetLayout),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(tester.getRect(find.byTooltip('关闭')), closeBefore);
        expect(
          tester.getSize(find.byType(SheetLayout)).width,
          lessThanOrEqualTo(560),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('关闭'));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
      },
    );
  }

  testWidgets('An empty date remains compact', (tester) async {
    await _open(tester, []);
    expect(find.text('没有未完成的日程'), findsOneWidget);
    expect(tester.getSize(find.byType(BottomSheet)).height, lessThan(280));
    expect(find.text('0项日程'), findsNothing);
  });

  testWidgets(
    'The shared picker preserves overdue status and course navigation',
    (tester) async {
      final overdue = _deadline(date: DateTime.utc(2020, 1, 1));
      final course = Course(
        id: 'course',
        name: '离散数学',
        weekday: 1,
        startSection: 3,
        endSection: 4,
        weeks: [1],
        room: '理教楼105',
      );
      final done = _deadline(id: 2, done: true);
      await _open(
        tester,
        [overdue, done],
        picker: [
          CalendarItem.agenda(overdue),
          CalendarItem.agenda(done),
          CalendarItem.course(course, _date),
        ],
      );
      expect(find.text('已逾期'), findsOneWidget);
      final overdueTime = tester.widget<Text>(find.text('18:00'));
      expect(
        overdueTime.style!.color,
        bitreeTheme(Brightness.light).colorScheme.error,
      );
      final completed = tester
          .widgetList<CompletionText>(find.byType(CompletionText))
          .where((widget) => widget.completed)
          .toList();
      expect(completed, hasLength(1));
      expect(completed.single.text, done.title);
      await tester.ensureVisible(find.text(course.name).first);
      await tester.tap(find.text(course.name).first);
      await tester.pumpAndSettle();
      expect(find.text('编辑课程'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
