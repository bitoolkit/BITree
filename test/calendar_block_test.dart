import 'dart:math' as math;

import 'package:bitree/agenda/calendar.dart';
import 'package:bitree/agenda/model.dart';
import 'package:bitree/agenda/ui/calendar_block.dart';
import 'package:bitree/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/system_palette.dart';
import 'support/test_app.dart';

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  final lighter = math.max(first, second);
  final darker = math.min(first, second);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  for (final brightness in Brightness.values) {
    for (final system in [false, true]) {
      testWidgets(
        'Home grid event blocks stay visible with ${system ? 'system' : 'app'} palette in $brightness',
        (tester) async {
          final theme = bitreeTheme(
            brightness,
            systemPalette: system ? testSystemPalette() : null,
          );
          final scheme = theme.colorScheme;
          final controller = TestAppController();
          final startsAt = DateTime.utc(2026, 11, 17, 10);
          final event = AgendaEntry(
            id: 'manual',
            title: '手动日程',
            kind: AgendaKind.event,
            startsAt: startsAt,
            endsAt: startsAt.add(const Duration(hours: 1)),
          );
          final exam = AgendaEntry(
            id: 'exam',
            title: '期末考试',
            kind: AgendaKind.exam,
            startsAt: startsAt.add(const Duration(hours: 2)),
            endsAt: startsAt.add(const Duration(hours: 3)),
          );

          Future<void> show(AgendaEntry entry) async {
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 120,
                      height: 120,
                      child: CalendarBlockTile(
                        items: [CalendarItem.agenda(entry)],
                        controller: controller,
                        isToday: false,
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
          }

          Material block() => tester.widget<Material>(
            find
                .descendant(
                  of: find.byType(CalendarBlockTile),
                  matching: find.byType(Material),
                )
                .first,
          );
          BorderSide side() => (block().shape! as RoundedRectangleBorder).side;

          await show(event);
          final material = block();
          final title = tester.widget<Text>(find.text(event.title));
          expect(material.color, scheme.primaryContainer);
          expect(title.style!.color, scheme.onPrimaryContainer);
          expect(side().color, scheme.primary);
          expect(side().width, 1);
          // The fill is deliberately subtle in light mode; the outline and text
          // must carry visibility under both the app and system palettes.
          expect(_contrast(side().color, material.color!), greaterThan(3));
          expect(_contrast(side().color, scheme.surface), greaterThan(3));
          expect(
            _contrast(title.style!.color!, material.color!),
            greaterThan(4.5),
          );

          await show(exam);
          final examMaterial = block();
          final examTitle = tester.widget<Text>(find.text(exam.title));
          expect(examMaterial.color, scheme.errorContainer);
          expect(examTitle.style!.color, scheme.onErrorContainer);
          expect(side().color, scheme.error);
          expect(_contrast(side().color, examMaterial.color!), greaterThan(3));
          expect(
            _contrast(examTitle.style!.color!, examMaterial.color!),
            greaterThan(4.5),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
