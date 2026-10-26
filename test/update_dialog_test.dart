import 'dart:ffi' show Abi;
import 'dart:math' as math;

import 'package:bitree/data/app_release.dart';
import 'package:bitree/ui/theme.dart';
import 'package:bitree/ui/update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

AppRelease _release({
  bool development = true,
  String? notes,
}) => AppRelease.fromGitHub({
  'tag_name': development ? 'v0.2.0-dev' : 'v0.2.0',
  'html_url':
      'https://github.com/so1ve/bitree/releases/tag/${development ? 'dev' : 'stable'}',
  'body': notes ?? '## 更新内容\n\n修复课程显示，改进更新下载。',
  'prerelease': development,
  'assets': [
    {
      'name': 'BITree-${development ? 'dev' : 'stable'}-android-arm64-v8a.apk',
      'browser_download_url':
          'https://downloads.example/${development ? 'dev' : 'stable'}-arm64.apk',
    },
  ],
}, abi: Abi.androidArm64);

final dialogSurface = find.byWidgetPredicate(
  (widget) => widget is Material && widget.type == MaterialType.card,
);

Future<void> _show(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
  required List<AppRelease> releases,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: bitreeTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  UpdateDialog(releases: releases, preferDevelopment: true),
            ),
            child: const Text('检查更新'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('检查更新'));
  await tester.pumpAndSettle();
}

void main() {
  final launched = <String>[];
  var launchSucceeds = true;
  setUp(() {
    launched.clear();
    launchSucceeds = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          (call) async {
            if (call.method == 'launch') {
              launched.add((call.arguments as Map)['url'] as String);
            }
            return launchSucceeds;
          },
        );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          null,
        ),
  );

  for (final (size, scale) in [
    (const Size(320, 640), 1.0),
    (const Size(390, 844), 1.0),
    (const Size(1440, 900), 1.0),
    (const Size(390, 844), 1.5),
  ]) {
    testWidgets('Three update actions fit at $size and text scale $scale', (
      tester,
    ) async {
      await _show(tester, size: size, textScale: scale, releases: [_release()]);
      final surface = tester.getRect(dialogSurface);
      expect(surface.width, math.min(360, size.width - 48));
      final later = tester.getRect(find.widgetWithText(TextButton, '稍后'));
      final page = tester.getRect(find.widgetWithText(TextButton, '发布页'));
      final download = tester.getRect(
        find.widgetWithText(FilledButton, '下载测试版'),
      );
      expect(later.right, lessThanOrEqualTo(page.left));
      expect(page.right, lessThanOrEqualTo(download.left));
      expect(later.center.dy, closeTo(download.center.dy, 0.1));
      expect(page.center.dy, closeTo(download.center.dy, 0.1));
      expect(download.bottom, lessThan(size.height));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Release page and APK actions use distinct links', (
    tester,
  ) async {
    final release = _release();
    await _show(tester, releases: [release]);
    await tester.tap(find.text('发布页'));
    await tester.pumpAndSettle();
    expect(launched, [release.url.toString()]);
    expect(find.byType(UpdateDialog), findsOneWidget);
    await tester.tap(find.text('下载测试版'));
    await tester.pumpAndSettle();
    expect(launched, [release.url.toString(), release.downloadUrl.toString()]);
    expect(find.byType(UpdateDialog), findsNothing);
  });

  testWidgets(
    'Selecting a release updates both actions and keeps three buttons',
    (tester) async {
      final stable = _release(development: false);
      final dev = _release();
      await _show(tester, releases: [stable, dev]);
      expect(find.text('下载测试版'), findsOneWidget);
      await tester.tap(find.text('正式版'));
      await tester.pumpAndSettle();
      expect(find.text('下载测试版'), findsNothing);
      expect(find.text('下载正式版'), findsOneWidget);
      expect(
        tester.widget<AlertDialog>(find.byType(AlertDialog)).actions!.length,
        3,
      );
      await tester.tap(find.text('发布页'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载正式版'));
      await tester.pumpAndSettle();
      expect(launched, [stable.url.toString(), stable.downloadUrl.toString()]);
    },
  );

  testWidgets('Long notes leave actions reachable and later opens no link', (
    tester,
  ) async {
    await _show(
      tester,
      releases: [_release(notes: List.filled(50, '- 修复显示问题').join('\n'))],
    );
    expect(find.text('稍后').hitTestable(), findsOneWidget);
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsNothing);
    expect(launched, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A failed download shows the same-width fallback dialog', (
    tester,
  ) async {
    launchSucceeds = false;
    final release = _release();
    await _show(tester, releases: [release]);
    await tester.tap(find.text('下载测试版'));
    await tester.pumpAndSettle();
    expect(find.text('无法打开下载链接'), findsOneWidget);
    expect(tester.getSize(dialogSurface.last).width, 342);
    expect(find.textContaining(release.downloadUrl.toString()), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
