import 'package:bitree/study/llm.dart';
import 'package:bitree/study/model.dart';
import 'package:bitree/study/ui/study_course.dart';
import 'package:bitree/study/ui/study_organize.dart';
import 'package:bitree/study/ui/study_services.dart';
import 'package:bitree/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

void main() {
  for (final (size, scale) in [
    (const Size(320, 640), 1.0),
    (const Size(390, 844), 1.8),
    (const Size(1200, 800), 1.0),
  ]) {
    testWidgets(
      'Course resources, timestamp notes and organizer stay with their lesson at $size / $scale',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = TestAppController();
        final course = await app.study.addLocalCourse('数据结构');
        course.lectures = [
          const StudyLecture(id: 'list', title: '线性表'),
          const StudyLecture(id: 'tree', title: '树与二叉树'),
        ];
        final material = await app.study.materials(
          course,
          course.lectures.first,
        );
        material.notes = '已有笔记';
        material.position = const Duration(minutes: 28, seconds: 15);
        material.transcript = [
          const TranscriptSegment(
            Duration.zero,
            Duration(seconds: 5),
            '线性表的定义',
          ),
        ];
        await tester.pumpWidget(
          MaterialApp(
            theme: bitreeTheme(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: StudyCourseScreen(app: app, courses: [course]),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('课件与字幕'));
        await tester.pumpAndSettle();
        expect(find.text('1 段 · 带时间戳'), findsOneWidget);
        await tester.tap(find.text('课堂字幕').first);
        await tester.pumpAndSettle();
        expect(find.text('线性表的定义'), findsOneWidget);
        final tabs = [
          '课件',
          '字幕',
          '笔记',
          '问答',
        ].map((text) => tester.getTopLeft(find.text(text)).dx).toList();
        expect(tabs, orderedEquals([...tabs]..sort()));
        await tester.tap(find.text('笔记'));
        await tester.pumpAndSettle();
        final draft = find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == '新笔记',
        );
        await tester.ensureVisible(draft);
        await tester.enterText(draft, '顺序存储需要连续空间');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('添加笔记'));
        await tester.tap(find.text('添加笔记'));
        await tester.pumpAndSettle();
        expect(material.notes, '已有笔记\n\n[28:15] 顺序存储需要连续空间');
        expect(
          (await app.study.materials(course, course.lectures.last)).notes,
          isEmpty,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('整理课程资料'));
        await tester.pumpAndSettle();
        expect(find.byType(StudyOrganizeScreen), findsOneWidget);
        final clear = find.text('全不选');
        await tester.ensureVisible(clear);
        await tester.tap(clear);
        await tester.pumpAndSettle();
        final start = find.widgetWithText(FilledButton, '开始整理 0 课时');
        await tester.ensureVisible(start);
        expect(tester.widget<FilledButton>(start).onPressed, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'Optional model settings save and disconnect at $size / $scale',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        FlutterSecureStorage.setMockInitialValues({});
        final model = StudyModel();
        await model.saveSettings(
          const StudyModelSettings(
            endpoint: 'http://localhost:11434/v1',
            model: 'local-model',
          ),
        );
        Widget settings() => StudyServices(model: model);
        await tester.pumpWidget(
          MaterialApp(
            theme: bitreeTheme(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => settings())),
                  child: const Text('打开设置'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开设置'));
        await tester.pumpAndSettle();
        expect(find.text('local-model'), findsOneWidget);
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('保存设置'));
        await tester.tap(find.text('保存设置'));
        await tester.pumpAndSettle();
        expect(await model.readSettings(), isNull);
        expect(find.text('打开设置'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
}
