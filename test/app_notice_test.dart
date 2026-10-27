import 'package:bitree/ui/app_notice.dart';
import 'package:bitree/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Feedback blocks taps to content below it and releases its timer with the overlay',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: bitreeTheme(Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (context) => Stack(
                children: [
                  Positioned.fill(
                    child: TextButton(
                      onPressed: () => taps++,
                      child: const Text('底部内容'),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topCenter,
                    child: TextButton(
                      onPressed: () => showAppNotice(context, '消息反馈'),
                      child: const Text('显示提示'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('显示提示'));
      await tester.pump();
      await tester.tap(find.text('消息反馈'));
      expect(taps, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Replacing a notice cancels its old timeout without closing the new notice',
    (tester) async {
      late BuildContext page;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                page = context;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      showAppNotice(page, '旧消息');
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      showAppNotice(page, '新消息', action: (label: '撤销', onPressed: () {}));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('旧消息'), findsNothing);
      expect(find.text('新消息'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.text('新消息'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
