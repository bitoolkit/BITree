import 'package:bitree/study/ui/study_video.dart';
import 'package:bitree/ui/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

// Native decoding is exercised separately; use the SDK's real state and streams
// to check the controls without requiring a platform video texture.
class _Player extends PlatformPlayer {
  _Player() : super(configuration: const PlayerConfiguration()) {
    state = state.copyWith(
      duration: const Duration(minutes: 95),
      position: const Duration(minutes: 28),
    );
  }

  @override
  Future<void> playOrPause() async {
    state = state.copyWith(playing: !state.playing);
    playingController.add(state.playing);
  }

  @override
  Future<void> setRate(double rate) async {
    state = state.copyWith(rate: rate);
    rateController.add(rate);
  }

  @override
  Future<void> seek(Duration position) async {
    state = state.copyWith(position: position);
    positionController.add(position);
  }
}

class _VideoController extends Fake implements VideoController {
  _VideoController(this.player);
  @override
  final Player player;
  @override
  final notifier = ValueNotifier<PlatformVideoController?>(null);
  @override
  final id = ValueNotifier<int?>(null);
  @override
  final rect = ValueNotifier<Rect?>(null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const fullscreenChannel = MethodChannel('com.alexmercerind/media_kit_video');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(fullscreenChannel, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(fullscreenChannel, null);
  });

  for (final (width, platform, scale) in [
    (390.0, TargetPlatform.android, 1.0),
    (390.0, TargetPlatform.android, 1.6),
    (320.0, TargetPlatform.android, 1.6),
    (1200.0, TargetPlatform.linux, 1.0),
  ]) {
    testWidgets(
      'Video keeps a full main frame and working inset at $width / $scale',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final backend = _Player();
        final player = Player(platformPlayer: backend);
        final main = _VideoController(player);
        final secondary = _VideoController(player);
        addTearDown(() async {
          await player.dispose();
          main.notifier.dispose();
          secondary.notifier.dispose();
          main.id.dispose();
          main.rect.dispose();
          secondary.id.dispose();
          secondary.rect.dispose();
        });
        var dual = true;
        var source = 'screen';
        var collapsed = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: bitreeTheme(Brightness.light).copyWith(platform: platform),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => Align(
                  alignment: Alignment.topCenter,
                  child: StudyVideo(
                    controller: main,
                    secondary: dual ? secondary : null,
                    onRetry: () {},
                    onCollapse: () => collapsed++,
                    sources: const {'screen', 'classroom'},
                    source: source,
                    onView: (next, inset) => setState(() {
                      source = next;
                      dual = inset;
                    }),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final mainRect = tester.getRect(find.byType(StudyVideo));
        final insetRect = tester.getRect(find.byTooltip('交换主画面'));
        expect(mainRect.width / mainRect.height, closeTo(16 / 9, .01));
        expect(insetRect.width, lessThan(mainRect.width / 2));
        expect(mainRect.contains(insetRect.topLeft), isTrue);
        expect(mainRect.contains(insetRect.bottomRight), isTrue);
        await tester.tap(find.byTooltip('交换主画面'));
        await tester.pumpAndSettle();
        expect(source, 'classroom');
        await tester.tap(find.byTooltip('关闭小窗'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('交换主画面'), findsNothing);

        // Source switching and speed remain available through the common menus.
        await tester.tap(find.byTooltip('切换画面'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byWidgetPredicate(
            (widget) =>
                widget is CheckedPopupMenuItem<String> &&
                widget.value == 'screen',
          ),
        );
        await tester.pumpAndSettle();
        expect(source, 'screen');
        await tester.tap(find.text('1.0×'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byWidgetPredicate(
            (widget) =>
                widget is CheckedPopupMenuItem<double> && widget.value == 1.5,
          ),
        );
        await tester.pumpAndSettle();
        expect(player.state.rate, 1.5);

        if (platform == TargetPlatform.linux) {
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: const Offset(1, 1));
          await mouse.moveTo(mainRect.center);
          await tester.pumpAndSettle();
          await tester.tap(find.byType(MaterialDesktopFullscreenButton));
          await tester.pumpAndSettle();
          expect(find.byType(FullscreenInheritedWidget), findsOneWidget);
          await tester.tap(find.byTooltip('开启画中画'));
          await tester.pumpAndSettle();
          expect(find.byTooltip('交换主画面'), findsOneWidget);
          await tester.tap(find.byTooltip('交换主画面'));
          await tester.pumpAndSettle();
          expect(source, 'classroom');
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pumpAndSettle();
          expect(player.state.playing, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
          expect(
            player.state.position,
            greaterThan(const Duration(minutes: 28)),
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.byType(FullscreenInheritedWidget), findsNothing);
          await mouse.moveTo(mainRect.center + const Offset(1, 0));
          await tester.pumpAndSettle();
          await tester.tap(find.byType(MaterialDesktopFullscreenButton));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('更多播放操作'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byWidgetPredicate(
              (widget) =>
                  widget is PopupMenuItem<String> && widget.value == 'collapse',
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(FullscreenInheritedWidget), findsNothing);
          expect(collapsed, 1);
          await mouse.removePointer();
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        // The SDK's controls leave their guarded auto-hide timers running on dispose.
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      },
    );
  }
}
