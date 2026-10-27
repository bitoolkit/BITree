import 'dart:convert';
import 'dart:io';

import 'package:bitree/schedule/model.dart';
import 'package:bitree/schedule/ui/home_screen.dart';
import 'package:bitree/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Clock labels need normal digit widths rather than Ahem's square glyphs.
    final config = File('.dart_tool/package_config.json');
    final packages =
        (jsonDecode(await config.readAsString()) as Map)['packages'] as List;
    final flutter = packages.cast<Map>().firstWhere(
      (item) => item['name'] == 'flutter',
    );
    final root = config.absolute.uri.resolve('${flutter['rootUri']}/');
    final file = File.fromUri(
      root.resolve(
        '../../bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
    );
    await (FontLoader(
      'HomeTest',
    )..addFont(file.readAsBytes().then(ByteData.sublistView))).load();
  });
  final now = DateTime.utc(2026, 10, 27, 12);
  final current = SemesterSchedule(
    term: '2026-2027-1',
    firstMonday: DateTime.utc(2026, 9, 21),
    firstWeek: -3,
    courses: const [],
  );
  final history = SemesterSchedule(
    term: '2025-2026-1',
    firstMonday: DateTime.utc(2025, 9, 22),
    courses: const [],
  );
  final overlappingHistory = SemesterSchedule(
    term: '2025-2026-2',
    firstMonday: DateTime.utc(2026, 3, 2),
    lastWeek: 40,
    courses: const [],
  );
  final future = SemesterSchedule(
    term: '2026-2027-2',
    firstMonday: DateTime.utc(2027, 3, 1),
    courses: const [],
  );
  final returnAction = find.byWidgetPredicate(
    (widget) =>
        widget is TextButton &&
            widget.child is Text &&
            (widget.child! as Text).data == '回到本周' ||
        widget is IconButton && widget.tooltip == '回到本周',
  );

  Future<void> showHome(
    WidgetTester tester,
    TestAppController controller, {
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await controller.initialize();
    final theme = bitreeTheme(Brightness.light);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'HomeTest'),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (_, _) =>
                HomeScreen(controller: controller, now: now, active: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final (selected, week, library) in [
    (current, 6, [history, current]),
    (history, 3, [history, current]),
    (history, 3, [history]),
    (overlappingHistory, 6, [current, overlappingHistory]),
    (future, 1, [current, future]),
  ]) {
    testWidgets('Return is hidden for ${selected.term}, week $week', (
      tester,
    ) async {
      await showHome(
        tester,
        TestAppController(
          schedule: selected,
          schedules: library,
          initialWeek: week,
        ),
      );
      expect(returnAction, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (size, scale) in [
    (const Size(320, 640), 1.0),
    (const Size(390, 844), 1.0),
    (const Size(390, 844), 1.5),
    (const Size(1200, 800), 1.0),
  ]) {
    testWidgets('Return selects this week and disappears at $size / $scale', (
      tester,
    ) async {
      final controller = TestAppController(
        schedule: current,
        schedules: [history, current],
        initialWeek: -3,
      );
      await showHome(tester, controller, size: size, scale: scale);
      expect(returnAction, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(returnAction);
      await tester.pumpAndSettle();
      expect(controller.timetable.week, 6);
      expect(find.text('第6周'), findsOneWidget);
      expect(find.text('27').hitTestable(), findsOneWidget);
      expect(returnAction, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('The home week heading follows the drag before pointer release', (
    tester,
  ) async {
    final controller = TestAppController(
      schedule: current,
      schedules: [history, current],
      initialWeek: 6,
    );
    await showHome(tester, controller);
    final gesture = await tester.startGesture(const Offset(350, 400));
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();
    expect(controller.timetable.week, 6);
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();
    expect(controller.timetable.week, 7);
    expect(find.text('第7周'), findsOneWidget);
    expect(returnAction, findsOneWidget);
    await gesture.moveBy(const Offset(150, 0));
    await tester.pump();
    expect(controller.timetable.week, 6);
    expect(returnAction, findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Showing return preserves the week menu closing animation', (
    tester,
  ) async {
    final controller = TestAppController(
      schedule: current,
      schedules: [history, current],
      initialWeek: 6,
    );
    await showHome(tester, controller);
    await tester.tap(find.text('第6周'));
    await tester.pumpAndSettle();
    final panel = find.byWidgetPredicate(
      (widget) => widget is Material && widget.elevation == 6,
    );
    final height = tester.getSize(panel).height;
    await tester.tap(find.widgetWithText(MenuItemButton, '7'));
    await tester.pump();
    expect(controller.timetable.week, 7);
    await tester.pump();
    expect(returnAction, findsOneWidget);
    expect(panel, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.getSize(panel).height,
      allOf(greaterThan(0), lessThan(height)),
    );
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
