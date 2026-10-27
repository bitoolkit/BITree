import 'package:bitree/ui/app_notice.dart';
import 'package:bitree/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<BuildContext> showPage(
    WidgetTester tester, {
    bool accessibleNavigation = false,
    double textScale = 1,
    VoidCallback? onBackgroundTap,
  }) async {
    late BuildContext page;
    await tester.pumpWidget(
      MaterialApp(
        theme: bitreeTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            accessibleNavigation: accessibleNavigation,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              page = context;
              return SizedBox.expand(
                child: TextButton(
                  onPressed: onBackgroundTap ?? () {},
                  child: const Text('底部内容'),
                ),
              );
            },
          ),
        ),
      ),
    );
    return page;
  }

  testWidgets(
    'Feedback blocks taps to content below it and releases its timer with the overlay',
    (tester) async {
      var taps = 0;
      final page = await showPage(tester, onBackgroundTap: () => taps++);
      showAppNotice(page, '消息反馈');
      await tester.pump();
      await tester.tap(find.text('消息反馈'));
      expect(taps, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  for (final accessible in [false, true]) {
    testWidgets(
      'Ordinary feedback expires after two seconds with accessible navigation $accessible',
      (tester) async {
        final page = await showPage(tester, accessibleNavigation: accessible);
        showAppNotice(page, '消息反馈');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1999));
        expect(find.text('消息反馈'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 1));
        expect(find.text('消息反馈'), findsNothing);
      },
    );

    testWidgets(
      'Actionable feedback expires after five seconds with accessible navigation $accessible',
      (tester) async {
        var actions = 0;
        final page = await showPage(tester, accessibleNavigation: accessible);
        showAppNotice(
          page,
          '已删除课程',
          action: (label: '撤销', onPressed: () => actions++),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 4999));
        expect(find.text('已删除课程'), findsOneWidget);
        expect(find.text('撤销'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 1));
        expect(find.text('已删除课程'), findsNothing);
        expect(find.text('撤销'), findsNothing);
        expect(actions, 0);
      },
    );
  }

  testWidgets(
    'Replacing a notice cancels its old timeout without closing the new notice',
    (tester) async {
      final page = await showPage(tester);
      showAppNotice(page, '旧消息');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      showAppNotice(page, '新消息', action: (label: '撤销', onPressed: () {}));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('旧消息'), findsNothing);
      expect(find.text('新消息'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2999));
      expect(find.text('新消息'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('新消息'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('An action runs once and its replacement gets its own timeout', (
    tester,
  ) async {
    var actions = 0;
    final page = await showPage(tester);
    showAppNotice(
      page,
      '已删除课程',
      action: (
        label: '撤销',
        onPressed: () {
          actions++;
          showAppNotice(page, '已恢复课程');
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 4500));
    await tester.tap(find.text('撤销'));
    await tester.pump();
    expect(actions, 1);
    expect(find.text('撤销'), findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('已恢复课程'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1400));
    expect(find.text('已恢复课程'), findsNothing);
  });

  for (final direction in [-1.0, 1.0]) {
    testWidgets('Swiping feedback in direction $direction dismisses it', (
      tester,
    ) async {
      var actions = 0;
      var backgroundTaps = 0;
      final page = await showPage(
        tester,
        onBackgroundTap: () => backgroundTaps++,
      );
      showAppNotice(
        page,
        '已删除课程',
        action: (label: '撤销', onPressed: () => actions++),
      );
      await tester.pump();
      final width = tester.getSize(find.byType(Dismissible)).width;
      await tester.fling(
        find.text('撤销'),
        Offset(direction * width * .7, 0),
        1000,
      );
      await tester.pumpAndSettle();
      expect(find.text('已删除课程'), findsNothing);
      expect(find.text('撤销'), findsNothing);
      expect(actions, 0);
      expect(backgroundTaps, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Feedback can expire while a swipe is active', (tester) async {
    final page = await showPage(tester);
    showAppNotice(page, '已删除课程', action: (label: '撤销', onPressed: () {}));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 4900));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('已删除课程')),
    );
    await gesture.moveBy(const Offset(-25, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('已删除课程'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Assistive technology can dismiss feedback without its action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      var actions = 0;
      final page = await showPage(tester, accessibleNavigation: true);
      showAppNotice(
        page,
        '已删除课程',
        action: (label: '撤销', onPressed: () => actions++),
      );
      await tester.pump();
      final node = tester.getSemantics(find.byType(Dismissible));
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.dismiss),
        isTrue,
      );
      node.owner!.performAction(node.id, SemanticsAction.dismiss);
      await tester.pump();
      expect(find.text('已删除课程'), findsNothing);
      expect(actions, 0);
    } finally {
      semantics.dispose();
    }
  });

  for (final scale in [1.0, 1.8]) {
    testWidgets('Actions keep feedback height at text scale $scale', (
      tester,
    ) async {
      final page = await showPage(tester, textScale: scale);
      showAppNotice(page, '消息反馈');
      await tester.pump();
      final ordinary = tester.getSize(find.byType(Dismissible));
      showAppNotice(page, '消息反馈', action: (label: '撤销', onPressed: () {}));
      await tester.pump();
      final actionable = tester.getSize(find.byType(Dismissible));
      expect(actionable.height, closeTo(ordinary.height, .1));
      expect(actionable.height, greaterThanOrEqualTo(48));
      expect(ordinary.width, lessThan(560));
      expect(tester.takeException(), isNull);
    });
  }
}
