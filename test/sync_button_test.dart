import 'package:bitree/sync/ui/sync_button.dart';
import 'package:bitree/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

void main() {
  testWidgets('The shared menu offers all, custom and deleted deadlines', (
    tester,
  ) async {
    final app = TestAppController();
    await app.initialize();
    await tester.pumpWidget(
      MaterialApp(
        theme: bitreeTheme(Brightness.light),
        home: Scaffold(body: SyncButton(controller: app)),
      ),
    );
    await tester.tap(find.byTooltip('同步'));
    await tester.pumpAndSettle();
    final labels = find.descendant(
      of: find.byType(MenuItemButton),
      matching: find.byType(Text),
    );
    expect(tester.widgetList<Text>(labels).map((text) => text.data), [
      '同步全部',
      '自定义同步',
      '已删除的 DDL',
    ]);
    expect(find.byType(Divider), findsOneWidget);
    expect(
      tester.getBottomLeft(find.text('自定义同步')).dy,
      lessThan(tester.getTopLeft(find.byType(Divider)).dy),
    );
    expect(
      tester.getBottomLeft(find.byType(Divider)).dy,
      lessThan(tester.getTopLeft(find.text('已删除的 DDL')).dy),
    );
    expect(tester.takeException(), isNull);
  });
}
