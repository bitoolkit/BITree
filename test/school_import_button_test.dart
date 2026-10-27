import 'package:bitree/school/ui/school_import_button.dart';
import 'package:bitree/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

void main() {
  testWidgets('The shared menu contains schedule and agenda sync actions', (
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
    await tester.tap(find.byTooltip('同步'));
    await tester.pumpAndSettle();
    expect(find.text('同步课表'), findsOneWidget);
    expect(find.text('同步考试安排'), findsOneWidget);
    expect(find.text('同步 DDL'), findsOneWidget);
    expect(find.text('同步乐学 DDL'), findsNothing);
    expect(find.text('同步新延河课堂 DDL'), findsNothing);
    expect(find.byType(Divider), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
