import 'package:bitree/ui/app_menu_anchor.dart';
import 'package:bitree/ui/app_dropdown_field.dart';
import 'package:bitree/ui/week_selector.dart';
import 'package:bitree/app_controller.dart';
import 'package:bitree/schedule/model.dart';
import 'package:bitree/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Controller extends ChangeNotifier with Fake implements AppController {
  @override
  final schedule = SemesterSchedule(
    term: '2026-2027-1',
    firstMonday: DateTime.utc(2026, 10, 26),
    courses: const [],
  );
  @override
  int week = 6;
  @override
  List<int> get weeks => List.generate(25, (i) => i + 1);
  @override
  void selectWeek(int week) {
    this.week = week;
    notifyListeners();
  }
}

final _panel = find.byWidgetPredicate(
  (widget) => widget is Material && widget.elevation == 6,
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
            menuChildren: [
              for (var i = 0; i < 8; i++)
                AppMenuItemButton(onPressed: () {}, child: Text('Item $i')),
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

void main() {
  for (final alignment in [Alignment.topLeft, Alignment.bottomRight]) {
    testWidgets('Menu at $alignment closes fully in 200 ms', (tester) async {
      final controller = MenuController();
      await _showMenu(tester, controller: controller, alignment: alignment);
      controller.open();
      await tester.pumpAndSettle();
      final opened = tester.getRect(_panel);
      controller.close();
      await tester.pump();
      for (var elapsed = 25; elapsed < 200; elapsed += 25) {
        await tester.pump(const Duration(milliseconds: 25));
        expect(_panel, findsOneWidget, reason: 'Menu removed at $elapsed ms');
        final closing = tester.getRect(_panel);
        expect(
          closing.height,
          closeTo(
            opened.height *
                (1 - Curves.easeInOutCubic.transform(elapsed / 200)),
            0.1,
          ),
        );
        expect(closing.left, closeTo(opened.left, 0.1));
        expect(
          alignment == Alignment.topLeft ? closing.top : closing.bottom,
          closeTo(
            alignment == Alignment.topLeft ? opened.top : opened.bottom,
            0.1,
          ),
        );
      }
      await tester.pump(const Duration(milliseconds: 25));
      await tester.pump(const Duration(milliseconds: 1));
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
    final closingHeight = tester.getSize(_panel).height;
    await tester.tap(find.text('Toggle'));
    await tester.pump();
    expect(tester.getSize(_panel).height, closeTo(closingHeight, 0.1));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.getSize(_panel).height, greaterThan(closingHeight));
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

  testWidgets('Week selection uses the shared closing transition', (
    tester,
  ) async {
    final controller = _Controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: bitreeTheme(Brightness.light),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => Align(
              alignment: Alignment.topLeft,
              child: WeekSelector(controller: controller),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('第6周'));
    await tester.pumpAndSettle();
    final height = tester.getSize(_panel).height;
    await tester.tap(find.text('8'));
    await tester.pump();
    expect(controller.week, 8);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.getSize(_panel).height,
      closeTo(height * (1 - Curves.easeInOutCubic.transform(0.5)), 0.1),
    );
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(find.text('第8周'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
}
