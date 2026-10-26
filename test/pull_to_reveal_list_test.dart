import 'package:bitree/ui/pull_to_reveal_list.dart';
import 'package:bitree/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _row(String label, {double height = 88}) =>
    SizedBox(key: ValueKey(label), height: height, child: Text(label));

Future<void> _showList(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  int overdue = 12,
  int upcoming = 3,
  bool reducedMotion = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: bitreeTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: child!,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('日程')),
        body: PullToRevealList(
          hiddenLabel: '$overdue项逾期日程',
          hiddenChildren: [
            for (var i = 0; i < overdue; i++) _row('Overdue $i'),
          ],
          children: [for (var i = 0; i < upcoming; i++) _row('Upcoming $i')],
        ),
      ),
    ),
  );
}

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(PullToRevealList),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

Future<void> _reveal(WidgetTester tester) async {
  await tester.drag(find.byType(PullToRevealList), const Offset(0, 260));
  await tester.pumpAndSettle();
  expect(find.text('收回').hitTestable(), findsOneWidget);
}

void main() {
  for (final size in [const Size(390, 844), const Size(1200, 1000)]) {
    testWidgets('Revealed list at $size ends after its last item', (
      tester,
    ) async {
      await _showList(tester, size: size);
      await _reveal(tester);
      final viewport = tester.getRect(find.byType(PullToRevealList));
      final collapse = tester.getRect(find.widgetWithText(TextButton, '收回'));
      expect(
        collapse.bottom,
        inInclusiveRange(viewport.bottom - 48, viewport.bottom),
      );

      final position = _position(tester);
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      final last = tester.getRect(find.byKey(const ValueKey('Upcoming 2')));
      expect(viewport.bottom - last.bottom, closeTo(24, 1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Short history stays compact and does not create a scroll range',
    (tester) async {
      await _showList(tester, overdue: 2, upcoming: 2);
      await _reveal(tester);
      final lastOverdue = tester.getRect(
        find.byKey(const ValueKey('Overdue 1')),
      );
      final collapse = tester.getRect(find.widgetWithText(TextButton, '收回'));
      expect(collapse.top - lastOverdue.bottom, closeTo(0, 1));
      expect(_position(tester).maxScrollExtent, 0);
      expect(_position(tester).pixels, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Collapse and repeated reveal do not accumulate scroll space', (
    tester,
  ) async {
    await _showList(tester);
    for (var cycle = 0; cycle < 2; cycle++) {
      await _reveal(tester);
      await tester.tap(find.widgetWithText(TextButton, '收回'));
      await tester.pumpAndSettle();
      expect(find.text('收回'), findsNothing);
      expect(find.text('Overdue 0'), findsNothing);
      expect(_position(tester).pixels, 0);
      expect(_position(tester).maxScrollExtent, 0);
      expect(
        tester.getRect(find.byKey(const ValueKey('Upcoming 0'))).top,
        tester.getRect(find.byType(PullToRevealList)).top,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reveal scrolls smoothly to the collapse button', (tester) async {
    await _showList(tester);
    await tester.drag(find.byType(PullToRevealList), const Offset(0, 260));
    await tester.pump();
    await tester.pump();
    final start = _position(tester).pixels;
    await tester.pump(const Duration(milliseconds: 160));
    final middle = _position(tester).pixels;
    await tester.pumpAndSettle();
    expect(middle, greaterThan(start));
    expect(middle, lessThan(_position(tester).pixels));
    expect(find.text('收回').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'The first revealed frame preserves the current content position',
    (tester) async {
      await _showList(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PullToRevealList)),
      );
      await gesture.moveBy(const Offset(0, 260));
      await tester.pump();
      final current = find.byKey(const ValueKey('Upcoming 0'));
      final before = tester.getTopLeft(current).dy;
      await gesture.up();
      await tester.pump();
      expect(current, findsOneWidget);
      expect(tester.getTopLeft(current).dy, closeTo(before, 1));
      await tester.pumpAndSettle();
      expect(find.text('收回').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final overdue in [2, 12]) {
    testWidgets('Collapsing $overdue overdue rows moves content continuously', (
      tester,
    ) async {
      await _showList(tester, overdue: overdue);
      await _reveal(tester);
      final position = _position(tester);
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      final current = find.byKey(const ValueKey('Upcoming 0'));
      final before = tester.getTopLeft(current).dy;
      final top = tester.getRect(find.byType(PullToRevealList)).top;
      await tester.tap(find.widgetWithText(TextButton, '收回'));
      await tester.pump();
      expect(tester.getTopLeft(current).dy, closeTo(before, 1));
      await tester.pump(const Duration(milliseconds: 130));
      expect(tester.getTopLeft(current).dy, inExclusiveRange(top, before));
      final middle = tester.getTopLeft(current).dy;
      await tester.pump(const Duration(milliseconds: 114));
      final lastFrame = tester.getTopLeft(current).dy;
      expect(lastFrame, inInclusiveRange(top, middle));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(current).dy, closeTo(top, 1));
      expect(lastFrame - top, lessThan((before - top) / 20));
      expect(find.text('收回'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Collapse can interrupt an opening animation', (tester) async {
    await _showList(tester);
    await tester.drag(find.byType(PullToRevealList), const Offset(0, 260));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    final current = find.byKey(const ValueKey('Upcoming 0'));
    final before = tester.getTopLeft(current).dy;
    await tester.tap(find.widgetWithText(TextButton, '收回'));
    await tester.pump();
    expect(tester.getTopLeft(current).dy, closeTo(before, 1));
    await tester.pumpAndSettle();
    expect(find.text('收回'), findsNothing);
    expect(_position(tester).pixels, 0);
    expect(_position(tester).maxScrollExtent, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A new drag takes control from the reveal animation', (
    tester,
  ) async {
    await _showList(tester);
    await tester.drag(find.byType(PullToRevealList), const Offset(0, 260));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PullToRevealList)),
    );
    await gesture.moveBy(const Offset(0, -120));
    await tester.pump();
    final dragged = _position(tester).pixels;
    await tester.pump(const Duration(milliseconds: 80));
    expect(_position(tester).pixels, closeTo(dragged, 1));
    await gesture.up();
    await tester.pumpAndSettle();
    final position = _position(tester);
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    final viewport = tester.getRect(find.byType(PullToRevealList));
    final last = tester.getRect(find.byKey(const ValueKey('Upcoming 2')));
    expect(viewport.bottom - last.bottom, closeTo(24, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reduced motion still reveals and collapses the natural list', (
    tester,
  ) async {
    await _showList(tester, reducedMotion: true);
    await _reveal(tester);
    await tester.tap(find.widgetWithText(TextButton, '收回'));
    await tester.pumpAndSettle();
    expect(find.text('收回'), findsNothing);
    expect(_position(tester).pixels, 0);
    expect(_position(tester).maxScrollExtent, 0);
    expect(tester.takeException(), isNull);
  });
}
