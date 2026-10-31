import 'package:bitree/classrooms/ui/classroom_time_field.dart';
import 'package:bitree/schedule/model.dart';
import 'package:bitree/schedule/ui/week_selector.dart';
import 'package:bitree/ui/app_dropdown_field.dart';
import 'package:bitree/ui/app_menu_anchor.dart';
import 'package:bitree/ui/app_page.dart';
import 'package:bitree/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

final _panel = find.byWidgetPredicate(
  (widget) => widget is Material && widget.elevation == 3,
);

Future<void> _showMenu(
  WidgetTester tester, {
  required MenuController controller,
  Alignment alignment = Alignment.topLeft,
  bool reducedMotion = false,
}) => tester.pumpWidget(
  MaterialApp(
    theme: bitreeTheme(Brightness.light),
    home: MediaQuery(
      data: MediaQueryData(
        size: tester.view.physicalSize / tester.view.devicePixelRatio,
        disableAnimations: reducedMotion,
      ),
      child: Scaffold(
        body: Align(
          alignment: alignment,
          child: AppMenuAnchor(
            controller: controller,
            style: const MenuStyle(alignment: AlignmentDirectional.bottomStart),
            menuChildren: [
              for (var i = 0; i < 8; i++)
                MenuItemButton(onPressed: () {}, child: Text('Item $i')),
            ],
            builder: (context, menu, isOpen) => TextButton(
              onPressed: () => isOpen ? menu.close() : menu.open(),
              child: const Text('Toggle'),
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<TestAppController> _showWeekHeader(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final controller = TestAppController(
    schedule: SemesterSchedule(
      term: '2026-2027-1',
      firstMonday: DateTime.utc(2026, 10, 26),
      firstWeek: -3,
      courses: const [],
    ),
    initialWeek: 6,
  );
  await controller.initialize();
  await tester.pumpWidget(
    MaterialApp(
      theme: bitreeTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: ListenableBuilder(
          listenable: controller.timetable,
          builder: (context, _) => AppPage(
            title: WeekSelector(controller: controller),
            actions: [
              for (final (label, icon) in [
                ('添加', Icons.add_rounded),
                ('导入', Icons.input_rounded),
                ('更多', Icons.more_horiz_rounded),
              ])
                IconButton(tooltip: label, onPressed: () {}, icon: Icon(icon)),
            ],
            child: const SizedBox.expand(),
          ),
        ),
      ),
    ),
  );
  return controller;
}

void main() {
  for (final alignment in [Alignment.topLeft, Alignment.bottomRight]) {
    testWidgets('Menu at $alignment stays anchored while fading out', (
      tester,
    ) async {
      final controller = MenuController();
      await _showMenu(tester, controller: controller, alignment: alignment);
      controller.open();
      await tester.pumpAndSettle();
      final opened = tester.getRect(_panel);
      controller.close();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(_panel, findsOneWidget);
      final closing = tester.getRect(_panel);
      expect(closing.left, closeTo(opened.left, 0.1));
      expect(closing.right, closeTo(opened.right, 0.1));
      expect(
        tester
            .widgetList<FadeTransition>(find.byType(FadeTransition))
            .any((fade) => fade.opacity.value > 0 && fade.opacity.value < 1),
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(_panel, findsNothing);
      expect(controller.isOpen, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Tapping the anchor reverses a closing menu without a jump', (
    tester,
  ) async {
    final controller = MenuController();
    await _showMenu(tester, controller: controller);
    await tester.tap(find.text('Toggle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toggle'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    final closing = tester.getRect(_panel);
    await tester.tap(find.text('Toggle'));
    await tester.pump();
    expect(tester.getRect(_panel).left, closeTo(closing.left, 0.1));
    await tester.pumpAndSettle();
    expect(controller.isOpen, isTrue);
    await tester.tap(find.text('Item 1'));
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reduced motion opens and closes without waiting', (
    tester,
  ) async {
    final controller = MenuController();
    await _showMenu(tester, controller: controller, reducedMotion: true);
    controller.open();
    await tester.pump();
    expect(_panel, findsOneWidget);
    controller.close();
    await tester.pump();
    expect(_panel, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Outside dismissal consumes the tap instead of activating another action',
    (tester) async {
      final controller = MenuController();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: bitreeTheme(Brightness.light),
          home: Scaffold(
            body: Column(
              children: [
                AppMenuAnchor(
                  controller: controller,
                  menuChildren: [
                    MenuItemButton(
                      onPressed: () {},
                      child: const Text('Choice'),
                    ),
                  ],
                  builder: (context, menu, isOpen) => TextButton(
                    onPressed: menu.open,
                    child: const Text('Open'),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => calls++,
                  child: const Text('Other action'),
                ),
              ],
            ),
          ),
        ),
      );
      controller.open();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other action'));
      await tester.pumpAndSettle();
      expect(controller.isOpen, isFalse);
      expect(calls, 0);
      await tester.tap(find.text('Other action'));
      await tester.pumpAndSettle();
      expect(calls, 1);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'Menus use the MD3 surface and lightweight shape in $brightness',
      (tester) async {
        final controller = MenuController();
        await tester.pumpWidget(
          MaterialApp(
            theme: bitreeTheme(brightness),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: Align(
                  alignment: Alignment.topRight,
                  child: AppMenuAnchor(
                    controller: controller,
                    menuChildren: [
                      MenuItemButton(
                        onPressed: () {},
                        child: const Text('Choice'),
                      ),
                    ],
                    builder: (context, menu, isOpen) => IconButton(
                      tooltip: 'More',
                      onPressed: menu.open,
                      icon: const Icon(Icons.more_vert),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final anchor = tester.getRect(find.byTooltip('More'));
        controller.open();
        await tester.pumpAndSettle();
        final material = tester.widget<Material>(_panel);
        final shape = material.shape! as RoundedRectangleBorder;
        expect(
          material.color,
          bitreeTheme(brightness).colorScheme.surfaceContainer,
        );
        expect(shape.borderRadius, BorderRadius.circular(4));
        expect(shape.side, BorderSide.none);
        final panel = tester.getRect(_panel);
        expect(panel.left, lessThanOrEqualTo(anchor.center.dx));
        expect(panel.right, greaterThanOrEqualTo(anchor.center.dx));
        expect(panel.top, closeTo(anchor.bottom, 0.1));
        controller.close();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Week selection uses the shared closing transition', (
    tester,
  ) async {
    final controller = await _showWeekHeader(
      tester,
      size: const Size(390, 844),
    );
    await tester.tap(find.text('第6周'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8'));
    await tester.pump();
    expect(controller.timetable.week, 8);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(_panel, findsOneWidget);
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(find.text('第8周'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (size, textScale) in [
    (const Size(390, 844), 1.0),
    (const Size(1440, 1000), 1.0),
    (const Size(390, 844), 1.5),
  ]) {
    testWidgets(
      'Week trigger stays compact in the real header at $size / $textScale',
      (tester) async {
        await _showWeekHeader(tester, size: size, textScale: textScale);
        final trigger = tester.getRect(find.widgetWithText(TextButton, '第6周'));
        final label = tester.getRect(find.text('第6周'));
        expect(trigger.width, lessThanOrEqualTo(label.width + 48));
        expect(label.left - trigger.left, greaterThanOrEqualTo(8));
        final arrow = tester.getRect(
          find.descendant(
            of: find.byType(WeekSelector),
            matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
          ),
        );
        expect(trigger.right - arrow.right, greaterThanOrEqualTo(8));
        for (final tooltip in ['添加', '导入', '更多']) {
          final action = tester.getRect(find.byTooltip(tooltip));
          expect(action.center.dy, closeTo(trigger.center.dy, 0.1));
          expect(action.left, greaterThanOrEqualTo(trigger.right));
        }
        final firstAction = tester.getRect(find.byTooltip('添加'));
        await tester.tapAt(Offset(firstAction.left - 8, trigger.center.dy));
        await tester.pumpAndSettle();
        expect(_panel, findsNothing);
        await tester.tap(find.text('第6周'));
        await tester.pumpAndSettle();
        final panel = tester.getRect(_panel);
        expect(panel.left, closeTo(trigger.left, 0.1));
        expect(panel.top, closeTo(trigger.bottom, 0.1));
        expect(panel.right, lessThanOrEqualTo(size.width - 8));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Week numbers are centered inside their menu cells', (
    tester,
  ) async {
    await _showWeekHeader(tester, size: const Size(1440, 1000));
    await tester.tap(find.text('第6周'));
    await tester.pumpAndSettle();
    for (final week in [-3, 1, 6, 25]) {
      final item = find.widgetWithText(MenuItemButton, '$week');
      await tester.ensureVisible(item);
      await tester.pumpAndSettle();
      final cell = tester.getRect(item);
      final number = tester.getRect(find.text('$week'));
      expect(number.center.dx, closeTo(cell.center.dx, 0.1));
      expect(number.center.dy, closeTo(cell.center.dy, 0.1));
    }
    expect(tester.takeException(), isNull);
  });

  for (final (size, scale) in [
    (const Size(360, 640), 1.0),
    (const Size(390, 844), 1.0),
    (const Size(390, 844), 1.5),
    (const Size(1440, 900), 1.0),
  ]) {
    testWidgets('All weeks fit without scrolling at $size / $scale', (
      tester,
    ) async {
      final controller = await _showWeekHeader(
        tester,
        size: size,
        textScale: scale,
      );
      controller.timetable.selectWeek(-3);
      await tester.pump();
      await tester.tap(find.text('第-3周'));
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: _panel, matching: find.byType(Scrollable)),
      );
      expect(scrollable.position.maxScrollExtent, 0);
      expect(find.text('-3').hitTestable(), findsOneWidget);
      expect(find.text('25').hitTestable(), findsOneWidget);
      await tester.drag(_panel, const Offset(0, -40));
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'A short viewport keeps weeks accessible within the visible area',
    (tester) async {
      const size = Size(900, 320);
      final controller = await _showWeekHeader(tester, size: size);
      await tester.tap(find.text('第6周'));
      await tester.pumpAndSettle();
      final panel = tester.getRect(_panel);
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: _panel, matching: find.byType(Scrollable)),
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      expect(panel.top, greaterThanOrEqualTo(0));
      expect(panel.bottom, lessThanOrEqualTo(size.height));
      await tester.ensureVisible(find.text('25'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('25'));
      await tester.pumpAndSettle();
      expect(controller.timetable.week, 25);
      expect(_panel, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Dropdown keeps its width, selection and keyboard controls', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var value = 6;
    await tester.pumpWidget(
      MaterialApp(
        theme: bitreeTheme(Brightness.light),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Padding(
              padding: const EdgeInsets.all(20),
              child: AppDropdownField<int>(
                label: '节次',
                value: value,
                entries: [
                  for (var i = 0; i < 13; i++)
                    DropdownMenuEntry(value: i, label: 'Section $i'),
                ],
                onChanged: (next) => setState(() => value = next),
              ),
            ),
          ),
        ),
      ),
    );
    final field = find.byType(AppDropdownField<int>);
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(tester.getSize(_panel).width, tester.getSize(field).width);
    expect(find.text('Section 6').hitTestable(), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(value, 7);
    expect(_panel, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final (size, scale) in [
    (const Size(390, 844), 1.0),
    (const Size(390, 844), 1.8),
    (const Size(1440, 900), 1.0),
  ]) {
    testWidgets('Classroom time menu fits its content at $size / $scale', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      ({int start, int end})? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: bitreeTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: size.width < 600 ? (size.width - 40) / 2 : 220,
                  child: ClassroomTimeField(
                    value: null,
                    date: DateTime.utc(2026, 10, 27),
                    now: DateTime.utc(2026, 10, 27, 6),
                    onChanged: (period) => selected = period,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final field = find.byType(ClassroomTimeField);
      await tester.tap(field);
      await tester.pumpAndSettle();
      final panel = tester.getRect(_panel);
      expect(panel.width, greaterThanOrEqualTo(tester.getSize(field).width));
      expect(panel.top, closeTo(tester.getRect(field).bottom, 0.1));
      expect(panel.left, greaterThanOrEqualTo(0));
      expect(panel.right, lessThanOrEqualTo(size.width));
      if (scale == 1) expect(panel.width, lessThan(340));
      final afternoon = find.text('下午');
      await tester.ensureVisible(afternoon);
      await tester.tap(afternoon);
      await tester.pumpAndSettle();
      expect(selected, (start: 6, end: 10));
      expect(_panel, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
