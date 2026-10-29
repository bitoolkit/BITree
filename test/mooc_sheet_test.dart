import 'dart:io';

import 'package:bitree/mooc/credentials.dart';
import 'package:bitree/mooc/ui/mooc_sheet.dart';
import 'package:bitree/school/ui/school_import_button.dart';
import 'package:bitree/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    TestAppController model, {
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await model.initialize();
    await tester.pumpWidget(
      MaterialApp(
        theme: bitreeTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: MoocAccountTile(controller: model.mooc)),
      ),
    );
    await tester.tap(find.text('中国大学MOOC'));
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'Cookie fallback validates locally and fits a narrow $brightness screen',
      (tester) async {
        final model = TestAppController();
        await pump(tester, model, scale: 1.4, brightness: brightness);
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.text('网页登录'), findsOneWidget);
        await tester.tap(find.text('使用 Cookie'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.widgetWithText(FilledButton, '连接'));
        await tester.tap(find.widgetWithText(FilledButton, '连接'));
        await tester.pump();
        expect(find.text('请粘贴 Cookie'), findsOneWidget);
        await tester.enterText(find.byType(TextFormField), 'not-a-cookie');
        await tester.tap(find.widgetWithText(FilledButton, '连接'));
        await tester.pumpAndSettle();
        expect(find.text('没有读取到中国大学MOOC 会话，请先完成登录。'), findsOneWidget);
        expect(model.mooc.account, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Disconnect keeps imported data and removes the saved account', (
    tester,
  ) async {
    final storage = MemoryMoocStorage()
      ..account = MoocAccount(
        id: '8',
        name: '姓名很长的中国大学MOOC 测试账号',
        credentials: MoocCredentials(
          userAgent: 'test',
          cookies: [Cookie('NTESSTUDYSI', 'csrf')],
        ),
      );
    final model = TestAppController(moocStorage: storage);
    await pump(tester, model, scale: 1.3);
    expect(find.text('同步 DDL'), findsOneWidget);
    await tester.tap(find.text('退出账号'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '退出'));
    await tester.pumpAndSettle();
    expect(storage.account, isNull);
    expect(find.text('网页登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('The existing import menu opens MOOC without a school login', (
    tester,
  ) async {
    final model = TestAppController();
    await model.initialize();
    await tester.pumpWidget(
      MaterialApp(
        theme: bitreeTheme(Brightness.light),
        home: Scaffold(body: SchoolImportButton(controller: model)),
      ),
    );
    await tester.tap(find.byTooltip('导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同步中国大学MOOC DDL'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('网页登录'), findsOneWidget);
    expect(find.text('学号'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dismissing the login choices returns to the same screen', (
    tester,
  ) async {
    final model = TestAppController();
    await pump(tester, model);
    await tester.tap(find.text('网页登录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('登录中国大学MOOC'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('网页登录'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(MoocAccountTile), findsOneWidget);
    await tester.tap(find.text('中国大学MOOC'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(model.mooc.account, isNull);
    expect(model.agenda.entries, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
