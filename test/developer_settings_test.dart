import 'package:bitree/app/ui/settings_screen.dart';
import 'package:bitree/main.dart';
import 'package:bitree/ui/app_menu_anchor.dart';
import 'package:bitree/ui/course_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'support/test_app.dart';

void main() {
  test(
    'Palette persists while developer mode resets for each app session',
    () async {
      final preferences = MemoryPreferences();
      final first = TestAppController(preferences: preferences);
      await first.initialize();
      expect(first.developerMode, isFalse);
      expect(first.darkCoursePalette, DarkCoursePalette.standard);
      first.unlockDeveloperMode();
      expect(first.developerMode, isTrue);
      final writes = [
        first.setDarkCoursePalette(DarkCoursePalette.mocha),
        first.setDarkCoursePalette(DarkCoursePalette.macchiato),
        first.setDarkCoursePalette(DarkCoursePalette.frappe),
      ];
      await Future.wait(writes);

      final second = TestAppController(preferences: preferences);
      await second.initialize();
      expect(second.developerMode, isFalse);
      expect(second.darkCoursePalette, DarkCoursePalette.frappe);
      await second.setDarkCoursePalette(DarkCoursePalette.standard);

      final third = TestAppController(preferences: preferences);
      await third.initialize();
      expect(third.darkCoursePalette, DarkCoursePalette.standard);
    },
  );

  test('Unknown saved palette falls back to the current app colours', () async {
    final preferences = MemoryPreferences();
    await preferences.setString('darkCoursePalette', 'retired-palette');
    final controller = TestAppController(preferences: preferences);
    await controller.initialize();
    expect(controller.darkCoursePalette, DarkCoursePalette.standard);
    expect(controller.developerMode, isFalse);
  });

  testWidgets('Five consecutive About icon taps reveal the palette menu', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    PackageInfo.setMockInitialValues(
      appName: 'BITree',
      packageName: 'app.bitree',
      version: '0.3.0',
      buildNumber: '1',
      buildSignature: '',
    );
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TestAppController();
    await controller.setTheme(ThemeMode.dark);
    await tester.pumpWidget(BitreeApp(controller: controller));
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('设置'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('更多设置'), findsNothing);
    final scrollable = find
        .descendant(
          of: find.byType(SettingsScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('关于 BITree'),
      200,
      scrollable: scrollable,
    );
    await tester.tap(find.text('关于 BITree'));
    await tester.pumpAndSettle();
    final icon = find.bySemanticsLabel('BITree 图标');
    for (var i = 0; i < 4; i++) {
      await tester.tap(icon);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(controller.developerMode, isFalse);
    // A pause starts a fresh sequence.
    await tester.pump(const Duration(seconds: 3));
    for (var i = 0; i < 4; i++) {
      await tester.tap(icon);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(controller.developerMode, isFalse);
    await tester.tap(icon);
    await tester.pumpAndSettle();
    expect(controller.developerMode, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.scrollUntilVisible(
      find.text('深色模式调色板'),
      -200,
      scrollable: scrollable,
    );
    expect(find.text('默认'), findsOneWidget);
    await tester.tap(find.text('深色模式调色板'));
    await tester.pumpAndSettle();
    for (final label in ['默认', 'Mocha', 'Macchiato', 'Frappé']) {
      expect(find.widgetWithText(AppMenuItemButton, label), findsOneWidget);
    }
    await tester.tap(find.widgetWithText(AppMenuItemButton, 'Mocha'));
    await tester.pumpAndSettle();
    expect(find.text('Mocha'), findsOneWidget);
    expect(controller.darkCoursePalette, DarkCoursePalette.mocha);
    final theme = Theme.of(tester.element(find.byType(SettingsScreen)));
    expect(
      theme.extension<CoursePaletteTheme>()!.darkPalette,
      DarkCoursePalette.mocha,
    );
    expect(theme.colorScheme.surface, const Color(0xFF171717));
    expect(theme.colorScheme.surfaceContainer, const Color(0xFF282828));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
