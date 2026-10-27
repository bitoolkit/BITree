import 'package:bitree/study/model.dart';
import 'package:bitree/study/ui/study_course_materials.dart';
import 'package:bitree/study/ui/study_layout.dart';
import 'package:bitree/study/ui/study_review.dart';
import 'package:bitree/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

void main() {
  testWidgets('Saved notes retain free text and timestamp playback links', (
    tester,
  ) async {
    Duration? position;
    await tester.pumpWidget(
      MaterialApp(
        theme: bitreeTheme(Brightness.light),
        home: Scaffold(
          body: StudyContent(
            child: StudyNotes(
              text: '随堂记录\n\n[12:35] 类定义对象的结构。\n\n[28:15] 两个引用可以指向同一个对象。',
              onSeek: (value) => position = value,
            ),
          ),
        ),
      ),
    );
    expect(find.text('随堂记录'), findsOneWidget);
    expect(find.text('类定义对象的结构。'), findsOneWidget);
    expect(find.text('两个引用可以指向同一个对象。'), findsOneWidget);
    await tester.tap(find.text('28:15'));
    expect(position, const Duration(minutes: 28, seconds: 15));
  });

  testWidgets(
    'Course note selection keeps same-ID lessons in their teaching class',
    (tester) async {
      final app = TestAppController();
      final a = StudyCourse(
        id: 'a',
        title: '数学分析',
        teacher: '张老师',
        lectures: [const StudyLecture(id: 'same', title: '极限')],
      );
      final b = StudyCourse(
        id: 'b',
        title: '数学分析',
        teacher: '李老师',
        lectures: [const StudyLecture(id: 'same', title: '微分')],
      );
      (await app.study.materials(a, a.lectures.single)).notes = '[12:35] 极限笔记';
      final material = await app.study.materials(b, b.lectures.single);
      material.notes = '[28:15] 微分笔记';
      material.summary = '微分整理';
      (String, String, StudyMaterial, Duration?)? opened;
      await tester.pumpWidget(
        MaterialApp(
          theme: bitreeTheme(Brightness.light),
          home: Scaffold(
            body: StudyContent(
              child: StudyCourseMaterials(
                app: app,
                entries: [(a, a.lectures.single), (b, b.lectures.single)],
                notesOnly: true,
                onOrganize: null,
                onReview: null,
                onOpen: (course, lecture, kind, {position}) =>
                    opened = (course.id, lecture.id, kind, position),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final choose = find.widgetWithText(TextButton, '微分');
      await tester.scrollUntilVisible(
        choose,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(choose);
      await tester.pumpAndSettle();
      expect(find.text('极限笔记'), findsNothing);
      expect(find.text('微分笔记'), findsOneWidget);
      expect(find.text('微分整理'), findsOneWidget);
      await tester.ensureVisible(find.text('28:15'));
      await tester.tap(find.text('28:15'));
      expect(opened, (
        'b',
        'same',
        StudyMaterial.video,
        const Duration(minutes: 28, seconds: 15),
      ));
    },
  );

  testWidgets(
    'Review contents use real Markdown headings and scroll to the document section',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = TestAppController();
      final course = StudyCourse(
        id: 'review',
        title: '数据结构',
        review:
            '## 线性表\n\n${List.filled(24, '线性表按顺序保存元素。\n\n').join()}## 树与二叉树\n\n课堂练习：画出二叉树。',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: bitreeTheme(Brightness.light),
          home: StudyReviewScreen(app: app, course: course),
        ),
      );
      await tester.pumpAndSettle();
      final section = find.widgetWithText(TextButton, '树与二叉树');
      await tester.tap(section);
      await tester.pumpAndSettle();
      expect(find.text('课堂练习：画出二叉树。').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
