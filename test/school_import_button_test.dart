import 'package:bitree/school/ui/school_import_button.dart';
import 'package:bitree/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

void main() {
  testWidgets('The shared import menu contains schedule and agenda imports', (
    tester,
  ) async {
    final controller = TestAppController();
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        theme: bitreeTheme(Brightness.light),
        home: Scaffold(body: SchoolImportButton(controller: controller)),
      ),
    );
    await tester.tap(find.byTooltip('导入'));
    await tester.pumpAndSettle();
    expect(find.text('导入课表'), findsOneWidget);
    expect(find.text('获取考试安排'), findsOneWidget);
    expect(find.text('更新乐学 DDL'), findsOneWidget);
    expect(find.text('更新新延河课堂 DDL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
