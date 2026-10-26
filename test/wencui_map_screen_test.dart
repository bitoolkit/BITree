import 'package:bitree/app_controller.dart';
import 'package:bitree/schedule/model.dart';
import 'package:bitree/ui/app_dropdown_field.dart';
import 'package:bitree/ui/course_detail.dart';
import 'package:bitree/ui/theme.dart';
import 'package:bitree/ui/wencui_map_screen.dart';
import 'package:bitree/wencui/atlas.dart';
import 'package:bitree/wencui/place.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Controller extends ChangeNotifier with Fake implements AppController {
  _Controller({List<Course> courses = const []})
    : schedule = SemesterSchedule(
        term: '2026-2027-1',
        firstMonday: DateTime.utc(2026, 10, 26),
        courses: courses,
      );
  @override
  final SemesterSchedule schedule;
  @override
  bool get busy => false;
}

Course _course(String name, String room) => Course(
  id: name,
  name: name,
  room: room,
  weekday: 1,
  startSection: 3,
  endSection: 4,
  weeks: [1, 2],
);

Finder _floor(int floor) => find.byWidgetPredicate(
  (widget) =>
      widget is Image &&
      widget.image is AssetImage &&
      (widget.image as AssetImage).assetName == 'assets/wencui/$floor.jpg',
);

Future<void> _open(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double scale = 1,
  String room = '',
  List<Course> courses = const [],
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final controller = _Controller(courses: courses);
  addTearDown(controller.dispose);
  await tester.runAsync(WencuiAtlas.load);
  await tester.pumpWidget(
    MaterialApp(
      theme: bitreeTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: WencuiMapScreen(controller: controller, initialRoom: room),
    ),
  );
  await tester.runAsync(
    () => precacheImage(
      AssetImage('assets/wencui/${WencuiPlace.parse(room)?.floor ?? 1}.jpg'),
      tester.element(find.byType(WencuiMapScreen)),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.tap(find.byType(SearchBar));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, query);
  await tester.pumpAndSettle();
}

Future<void> _tapFeature(WidgetTester tester, WencuiFeature feature) async {
  final viewer = tester.widget<InteractiveViewer>(
    find.byType(InteractiveViewer),
  );
  final size = tester.getSize(_floor(feature.floor));
  final scene = Offset(
    feature.anchor.dx * size.width,
    feature.anchor.dy * size.height,
  );
  final point =
      tester.getTopLeft(find.byType(InteractiveViewer)) +
      MatrixUtils.transformPoint(viewer.transformationController!.value, scene);
  expect(
    tester.getRect(find.byType(InteractiveViewer)).contains(point),
    isTrue,
  );
  await tester.tapAt(point);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Search highlights a room; tapping an adjacent room selects it', (
    tester,
  ) async {
    await _open(tester);
    await _search(tester, 'ｆ７０４');
    await tester.tap(find.widgetWithText(ListTile, 'F704'));
    await tester.pumpAndSettle();
    expect(_floor(7), findsOneWidget);
    expect(find.text('F704'), findsOneWidget);
    expect(find.text('上东 · 左北'), findsOneWidget);
    final atlas = (await tester.runAsync(WencuiAtlas.load))!;
    await _tapFeature(tester, atlas.room('F703')!);
    expect(find.text('F703'), findsOneWidget);
    expect(find.text('F704'), findsNothing);

    final transform = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    final roomScale = transform.value.getMaxScaleOnAxis();
    await tester.tap(find.text('找楼梯 / 电梯'));
    await tester.pumpAndSettle();
    expect(transform.value.getMaxScaleOnAxis(), lessThan(roomScale));
    final stairs = atlas.features.firstWhere(
      (feature) =>
          feature.floor == 7 &&
          feature.kind == WencuiFeatureKind.stairs &&
          feature.wing == WencuiWing.f,
    );
    await _tapFeature(tester, stairs);
    expect(find.text(stairs.title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Entrance, destination and zoom controls operate on the same map',
    (tester) async {
      await _open(tester, room: 'F704');
      await tester.tap(find.text('一层入口'));
      await tester.pumpAndSettle();
      expect(_floor(1), findsOneWidget);
      await tester.tap(find.text('回到教室'));
      await tester.pumpAndSettle();
      expect(_floor(7), findsOneWidget);
      final transform = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
      final initial = transform.value.getMaxScaleOnAxis();
      await tester.tap(find.byTooltip('放大地图'));
      await tester.pumpAndSettle();
      expect(transform.value.getMaxScaleOnAxis(), greaterThan(initial));
      await tester.tap(find.byTooltip('查看整层'));
      await tester.pumpAndSettle();
      expect(transform.value.getMaxScaleOnAxis(), lessThan(initial));
      await tester.tap(find.byTooltip('回到选中位置'));
      await tester.pumpAndSettle();
      expect(transform.value.getMaxScaleOnAxis(), closeTo(initial, .001));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Cached course search can submit from the keyboard without login',
    (tester) async {
      await _open(tester, courses: [_course('概率论与数理统计', '文萃楼F704')]);
      await _search(tester, '概率');
      await tester.tap(find.widgetWithText(ListTile, '概率论与数理统计').last);
      await tester.pumpAndSettle();
      expect(_floor(7), findsOneWidget);
      await _search(tester, 'J1006');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(_floor(10), findsOneWidget);
      expect(find.text('J1006'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Every floor uses the real plan and an unlisted room stays a wing lookup',
    (tester) async {
      await _open(tester, room: 'F706');
      expect(find.textContaining('图中未找到F706'), findsOneWidget);
      for (var floor = 1; floor <= 10; floor++) {
        await tester.tap(find.byType(AppDropdownField<int>));
        await tester.pumpAndSettle();
        final item = find.text('$floor层').last;
        await tester.ensureVisible(item);
        await tester.tap(item);
        await tester.pumpAndSettle();
        expect(_floor(floor), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final (size, scale) in [
    (const Size(320, 640), 1.0),
    (const Size(390, 844), 1.8),
    (const Size(1200, 800), 1.0),
    (const Size(900, 420), 1.6),
  ]) {
    testWidgets('Room controls remain usable at $size, scale $scale', (
      tester,
    ) async {
      await _open(tester, size: size, scale: scale, room: 'J1006');
      expect(_floor(10), findsOneWidget);
      await tester.ensureVisible(find.text('一层入口'));
      await tester.tap(find.text('一层入口'));
      await tester.pumpAndSettle();
      expect(_floor(1), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('清除目的地'));
      await tester.tap(find.byTooltip('清除目的地'));
      await tester.pumpAndSettle();
      expect(find.text('点房间查看位置，双指缩放地图'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Course detail opens the same map at its actual room', (
    tester,
  ) async {
    final course = _course('概率论与数理统计', '文萃楼F704');
    final controller = _Controller(courses: [course]);
    addTearDown(controller.dispose);
    await tester.runAsync(WencuiAtlas.load);
    await tester.pumpWidget(
      MaterialApp(
        theme: bitreeTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCourse(context, controller, course),
              child: const Text('查看课程'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('查看课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('在文萃地图中查看'));
    await tester.pump();
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/wencui/7.jpg'),
        tester.element(find.byType(Navigator).first),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(WencuiMapScreen), findsOneWidget);
    expect(_floor(7), findsOneWidget);
    expect(find.text('F704'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
