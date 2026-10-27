import 'dart:async';

import 'package:bitree/ui/swipe_action_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> showTile(
    WidgetTester tester,
    Future<bool> Function() invoke,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 390,
              child: SwipeActionTile(
                enabled: true,
                leftAction: TileSwipeAction(
                  label: '删除',
                  releaseLabel: '松手删除',
                  icon: Icons.delete_outline,
                  background: Colors.red,
                  foreground: Colors.white,
                  onInvoke: invoke,
                ),
                child: const SizedBox(
                  key: ValueKey('content'),
                  height: 96,
                  child: Text('第三章实验报告'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'A committed swipe continues offscreen and failure restores its size and position',
    (tester) async {
      final saved = Completer<bool>();
      var calls = 0;
      await showTile(tester, () {
        calls++;
        return saved.future;
      });
      final content = find.byKey(const ValueKey('content'));
      final before = tester.getRect(content);
      await tester.drag(content, const Offset(-120, 0));
      await tester.pump();
      final released = tester.getRect(content);
      expect(released.left, lessThan(before.left));
      expect(released.height, before.height);
      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getRect(content).left, lessThan(released.left));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(tester.getRect(content).right, lessThanOrEqualTo(before.left));
      saved.complete(false);
      await tester.pumpAndSettle();
      expect(tester.getRect(content), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('A short swipe returns without invoking the action', (
    tester,
  ) async {
    var calls = 0;
    await showTile(tester, () async {
      calls++;
      return false;
    });
    final content = find.byKey(const ValueKey('content'));
    final before = tester.getRect(content);
    final gesture = await tester.startGesture(tester.getCenter(content));
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(tester.getRect(content), before);
  });
}
