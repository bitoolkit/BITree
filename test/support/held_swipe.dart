import 'package:flutter_test/flutter_test.dart';

Future<TestGesture> startHeldSwipe(
  WidgetTester tester,
  Finder finder,
  Offset offset,
) async {
  final gesture = await tester.startGesture(tester.getCenter(finder));
  await tester.pump(const Duration(milliseconds: 250));
  await gesture.moveBy(
    Offset(offset.dx.sign * 24, 0),
    timeStamp: const Duration(milliseconds: 250),
  );
  await tester.pump();
  await gesture.moveBy(
    offset - Offset(offset.dx.sign * 24, 0),
    timeStamp: const Duration(milliseconds: 450),
  );
  await tester.pump();
  return gesture;
}

Future<void> heldSwipe(
  WidgetTester tester,
  Finder finder,
  Offset offset,
) async {
  final gesture = await startHeldSwipe(tester, finder, offset);
  await gesture.up(timeStamp: const Duration(milliseconds: 500));
}
