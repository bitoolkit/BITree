import 'package:bitree/app_controller.dart';
import 'package:bitree/schedule/model.dart';
import 'package:bitree/ui/course_tile.dart';
import 'package:bitree/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// Rendering the card never calls the controller; opening details is separate.
class _Controller extends Fake implements AppController {}

void main() {
  final course = Course(
    id: 'course',
    name: '概率论与数理统计',
    room: '物理实验楼309-310',
    weekday: DateTime.monday,
    startSection: 3,
    endSection: 4,
    weeks: [1],
  );

  Future<void> showCard(
    WidgetTester tester, {
    required double width,
    required double height,
    double scale = 1,
    bool bold = false,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: bitreeTheme(Brightness.light),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale), boldText: bold),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                height: height,
                child: CourseTile(
                  course: course,
                  controller: _Controller(),
                  isToday: false,
                  isCurrent: false,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  void expectFullText(WidgetTester tester) {
    final card = tester.getRect(find.byType(CourseTile));
    for (final text in [course.name, course.room]) {
      final finder = find.text(text);
      final paragraph = tester.renderObject<RenderParagraph>(finder);
      expect(paragraph.didExceedMaxLines, isFalse, reason: text);
      expect(tester.getRect(finder).bottom, lessThanOrEqualTo(card.bottom - 6));
    }
    expect(tester.takeException(), isNull);
  }

  testWidgets('Narrow cards show all wrapped text when it fits', (
    tester,
  ) async {
    await showCard(tester, width: 52, height: 180);
    expectFullText(tester);
    expect(tester.getSize(find.text(course.name)).height, greaterThan(20));
    expect(tester.getSize(find.text(course.room)).height, greaterThan(20));
  });

  testWidgets('Text reflows after resizing and accessibility changes', (
    tester,
  ) async {
    await showCard(tester, width: 42, height: 360);
    expectFullText(tester);
    await showCard(tester, width: 86, height: 360, scale: 1.6, bold: true);
    expectFullText(tester);
    await showCard(tester, width: 52, height: 180);
    expectFullText(tester);
  });

  testWidgets('Short cards ellipsize without overflowing', (tester) async {
    await showCard(tester, width: 52, height: 48);
    final title = tester.renderObject<RenderParagraph>(find.text(course.name));
    expect(title.didExceedMaxLines, isTrue);
    final card = tester.getRect(find.byType(CourseTile));
    expect(
      tester.getRect(find.text(course.room)).bottom,
      lessThanOrEqualTo(card.bottom - 6),
    );
    expect(tester.takeException(), isNull);
  });
}
