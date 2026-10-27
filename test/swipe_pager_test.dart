import 'package:bitree/ui/swipe_pager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets('$kind reports the nearest page while the pointer is held', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var index = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SwipePager(
                index: index,
                itemCount: 3,
                onChanged: (value) => setState(() => index = value),
                itemBuilder: (_, page) => Center(child: Text('Page $page')),
              ),
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        const Offset(350, 300),
        kind: kind,
      );
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-120, 0));
      await tester.pump();
      expect(index, 0);
      await gesture.moveBy(const Offset(-120, 0));
      await tester.pump();
      expect(index, 1);
      await gesture.moveBy(const Offset(150, 0));
      await tester.pump();
      expect(index, 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(index, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('A short fling reports the next page before snapping finishes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var index = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwipePager(
            index: 0,
            itemCount: 3,
            onChanged: (value) => index = value,
            itemBuilder: (_, page) => Center(child: Text('Page $page')),
          ),
        ),
      ),
    );
    await tester.fling(find.byType(SwipePager), const Offset(-120, 0), 1000);
    expect(index, 0);
    for (var frame = 0; frame < 30 && index == 0; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(index, 1);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.isScrollingNotifier.value, isTrue);
    await tester.pumpAndSettle();
    expect(index, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Programmatic jumps do not report intermediate pages', (
    tester,
  ) async {
    var index = 0;
    final changes = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                TextButton(
                  onPressed: () => setState(() => index = 4),
                  child: const Text('Jump'),
                ),
                Expanded(
                  child: SwipePager(
                    index: index,
                    itemCount: 5,
                    onChanged: (value) {
                      changes.add(value);
                      setState(() => index = value);
                    },
                    itemBuilder: (_, page) => Center(child: Text('Page $page')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Jump'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(index, 4);
    expect(changes, isEmpty);
    await tester.pumpAndSettle();
    expect(index, 4);
    expect(changes, isEmpty);
    expect(find.text('Page 4').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
