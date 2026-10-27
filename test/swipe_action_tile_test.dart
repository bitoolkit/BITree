import 'dart:async';
import 'dart:ui' as ui;

import 'package:bitree/ui/swipe_action_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> showTile(
    WidgetTester tester,
    Future<bool> Function() invoke,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey('scene'),
            child: Center(
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
                  rightAction: TileSwipeAction(
                    label: '完成',
                    releaseLabel: '松手完成',
                    icon: Icons.check,
                    background: Colors.green,
                    foreground: Colors.white,
                    onInvoke: invoke,
                  ),
                  child: const SizedBox(
                    key: ValueKey('content'),
                    width: double.infinity,
                    height: 96,
                    child: ColoredBox(
                      color: Colors.blue,
                      child: Text('第三章实验报告'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('Swiped content stays inside the row in both directions', (
    tester,
  ) async {
    await showTile(tester, () async => false);
    final content = find.byKey(const ValueKey('content'));
    final bounds = tester.getRect(find.byType(SwipeActionTile));
    for (final distance in [-120.0, 120.0]) {
      final gesture = await tester.startGesture(tester.getCenter(content));
      await gesture.moveBy(Offset(distance.sign * 20, 0));
      await tester.pump();
      await gesture.moveBy(Offset(distance, 0));
      await tester.pump();
      expect(
        tester.getRect(content).left,
        distance < 0 ? lessThan(bounds.left) : greaterThan(bounds.left),
      );
      await tester.runAsync(() async {
        final scene = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('scene')),
        );
        final image = await scene.toImage();
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        Color pixelAt(Offset point) {
          final local = scene.globalToLocal(point);
          final offset =
              (local.dy.floor() * image.width + local.dx.floor()) * 4;
          return Color.fromARGB(
            pixels.getUint8(offset + 3),
            pixels.getUint8(offset),
            pixels.getUint8(offset + 1),
            pixels.getUint8(offset + 2),
          );
        }

        final outsideLeft = pixelAt(Offset(bounds.left - 8, bounds.center.dy));
        final outsideRight = pixelAt(
          Offset(bounds.right + 8, bounds.center.dy),
        );
        final inside = pixelAt(bounds.center);
        image.dispose();
        expect(outsideLeft, Colors.transparent);
        expect(outsideRight, Colors.transparent);
        expect(inside.toARGB32(), Colors.blue.toARGB32());
      });
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.getRect(content), bounds);
    }
  });

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
