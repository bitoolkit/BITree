import 'package:bitree/study/library.dart';
import 'package:bitree/study/model.dart';
import 'package:bitree/study/ui/study_course.dart';
import 'package:bitree/study/ui/study_screen.dart';
import 'package:bitree/ui/app_menu_anchor.dart';
import 'package:bitree/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

List<StudyCourse> libraryCourses() => [
  StudyCourse(
    id: 'lab',
    title: '大学物理实验 Ⅱ',
    term: '2026-2027-1',
    lectureCount: 0,
  ),
  StudyCourse(
    id: 'old',
    title: '数学分析',
    teacher: '张老师',
    term: '2025-2026-2',
    lectureCount: 20,
  ),
  StudyCourse(
    id: 'math-a',
    title: '数学分析',
    teacher: '张老师',
    term: '2026-2027-1',
    lectureCount: 1,
    lectures: [
      StudyLecture(
        id: 'same-id',
        title: '连续函数与极限',
        startsAt: DateTime(2026, 10, 26),
      ),
    ],
  ),
  StudyCourse(
    id: 'math-b',
    title: '数学分析',
    teacher: '李老师',
    term: '2026-2027-1',
    lectureCount: 1,
    lectures: [
      StudyLecture(
        id: 'same-id',
        title: '微分的应用',
        startsAt: DateTime(2026, 10, 27),
      ),
    ],
  ),
  StudyCourse(
    id: 'physics',
    title: '大学物理 AⅡ',
    teacher: '王老师',
    term: '2026-2027-1',
  ),
];

void main() {
  test('Saved course counts distinguish unknown courses from empty ones', () {
    for (final count in [null, 0, 12]) {
      final course = StudyCourse(
        id: 'course',
        title: '课程',
        lectureCount: count,
      );
      final restored = StudyCourse.fromJson(course.toJson());
      expect(restored.lectureCount, count);
      expect(restored.isEmptyRemote, count == 0);
    }
    final legacy = StudyCourse.fromJson({
      'id': 'old',
      'title': '旧课程',
      'lectures': [],
    });
    expect(legacy.isEmptyRemote, isFalse);
  });

  test('Library groups offerings by title within each term and keeps unknown and local courses', () {
    final courses = libraryCourses();
    courses.addAll([
      StudyCourse(
        id: 'math-c',
        title: '数学 分析',
        teacher: '张老师',
        term: '2026-2027-1',
        lectureCount: 3,
      ),
      StudyCourse(id: 'local-1', title: '数学分析', remote: false),
      StudyCourse(id: 'local-2', title: '数学分析', remote: false),
      StudyCourse(
        id: 'with-notes',
        title: '保留本地资料',
        lectureCount: 0,
        lectures: [const StudyLecture(id: 'local', title: '导入课时')],
      ),
    ]);
    final groups = groupStudyCourses(courses);
    final math = groups
        .where((group) => group.term == '2026-2027-1' && group.title == '数学分析')
        .single;
    expect(math.courses.map((course) => course.id), [
      'math-a',
      'math-b',
      'math-c',
    ]);
    expect(math.lectureCount, 5);
    expect(math.teachers, ['张老师', '李老师']);
    expect(groups.first.term, '2026-2027-1');
    expect(groups.where((group) => !group.remote).length, 2);
    expect(groups.any((group) => group.title.contains('大学物理实验')), isFalse);
    expect(groups.any((group) => group.title == '大学物理 AⅡ'), isTrue);
    expect(groups.any((group) => group.title == '保留本地资料'), isTrue);
    expect(studyTermLabel('2026-2027-1'), '2026-2027 秋季学期');
  });

  testWidgets('Library and course details count the same loaded lectures', (
    tester,
  ) async {
    final app = TestAppController();
    final course = StudyCourse(
      id: 'java',
      title: 'JAVA语言程序设计',
      teacher: '金旭亮',
      term: '2026-2027-1',
      lectureCount: 7,
      lectures: [
        for (var week = 0; week < 5; week++)
          StudyLecture(
            id: 'java-$week',
            title: '第${week + 1}次课',
            startsAt: DateTime(2026, 9, 22 + week * 7),
          ),
      ],
    );
    final store = app.study.store as MemoryStudyStore;
    store.courses = [StudyCourse.fromJson(course.toJson())];
    await app.study.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: bitreeTheme(Brightness.light),
        home: Scaffold(body: StudyScreen(controller: app)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('5 课时'), findsOneWidget);
    expect(find.text('7 课时'), findsNothing);

    // A later library refresh can report a different summary total again.
    store.courses.single.lectureCount = 7;
    await app.study.load();
    await tester.pumpAndSettle();
    expect(find.text('5 课时'), findsOneWidget);
    await tester.tap(find.widgetWithText(InkWell, '金旭亮'));
    await tester.pumpAndSettle();
    expect(find.byType(StudyCourseScreen), findsOneWidget);
    expect(find.text('5 课时'), findsOneWidget);
    for (var week = 1; week <= 5; week++) {
      expect(find.text('第$week次课'), findsOneWidget);
    }
    expect(find.text('7 课时'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('5 课时'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  for (final (size, scale) in [
    (const Size(320, 640), 1.0),
    (const Size(390, 844), 1.8),
    (const Size(1200, 800), 1.0),
  ]) {
    testWidgets(
      'Library groups terms and teacher filters keep material ownership at $size / $scale',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = TestAppController();
        final courses = libraryCourses();
        (app.study.store as MemoryStudyStore).courses = courses;
        await app.study.load();
        final a = courses[2];
        final b = courses[3];
        (await app.study.materials(a, a.lectures.single)).notes = '张老师的极限笔记';
        (await app.study.materials(b, b.lectures.single)).notes = '李老师的微分笔记';
        await app.study.remember(a, a.lectures.single);
        await tester.pumpWidget(
          MaterialApp(
            theme: bitreeTheme(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(body: StudyScreen(controller: app)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(GridView), findsNothing);
        expect(find.text('继续观看'), findsOneWidget);
        expect(find.text('大学物理实验 Ⅱ'), findsNothing);
        expect(find.text('2026-2027 秋季学期'), findsOneWidget);
        final math = find.widgetWithText(InkWell, '张老师、李老师  2 个教学班');
        await tester.ensureVisible(math);
        await tester.tap(math);
        await tester.pumpAndSettle();
        expect(find.byType(StudyCourseScreen), findsOneWidget);
        expect(find.text('连续函数与极限'), findsOneWidget);
        expect(find.text('微分的应用'), findsOneWidget);
        await tester.tap(find.text('全部教师'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(AppMenuItemButton, '李老师'));
        await tester.pumpAndSettle();
        expect(find.text('连续函数与极限'), findsNothing);
        expect(find.text('微分的应用'), findsOneWidget);
        await tester.ensureVisible(find.text('笔记'));
        await tester.tap(find.text('笔记'));
        await tester.pumpAndSettle();
        expect(find.text('李老师的微分笔记'), findsOneWidget);
        expect(find.text('张老师的极限笔记'), findsNothing);
        await tester.enterText(find.byType(TextField).first, '李老师的新笔记');
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          (await app.study.materials(b, b.lectures.single)).notes,
          '李老师的新笔记',
        );
        expect(
          (await app.study.materials(a, a.lectures.single)).notes,
          '张老师的极限笔记',
        );
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
        final oldTerm = find.text('2025-2026 春季学期');
        await tester.ensureVisible(oldTerm);
        await tester.tap(oldTerm);
        await tester.pumpAndSettle();
        expect(find.text('20 课时'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
}
