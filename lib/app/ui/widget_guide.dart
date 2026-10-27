import 'package:flutter/material.dart';

import '../../ui/design.dart';
import '../../ui/sheet_layout.dart';

Future<void> showWidgetGuide(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);

        Widget step(int number, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '$number',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
            ],
          ),
        );

        return SafeArea(
          top: false,
          child: SheetLayout(
            header: SheetHeader(
              title: const Text('桌面日程表'),
              actions: [
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
            content: Padding(
              padding: appSheetContentPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _WidgetSize(columns: 1, label: '2×2 单列'),
                        _WidgetSize(columns: 2, label: '2×4 双列'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  step(1, '长按桌面空白处，打开“小组件”。'),
                  step(2, '找到 BITree 日程表，选择单列或双列样式，拖到桌面。'),
                  step(3, '上下滑动，查看课程、考试、DDL 和活动。'),
                  const SizedBox(height: 8),
                  Text(
                    '当天安排结束后，21:00 起显示明天的日程。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            actions: Padding(
              padding: appSheetActionPadding,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了'),
              ),
            ),
          ),
        );
      },
    );

class _WidgetSize extends StatelessWidget {
  const _WidgetSize({required this.columns, required this.label});

  final int columns;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Container(
            width: columns == 1 ? 64 : 112,
            height: 64,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              spacing: 6,
              children: List.generate(
                columns,
                (_) => Expanded(
                  child: Column(
                    spacing: 6,
                    children: List.generate(
                      2,
                      (_) => Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: theme.textTheme.labelLarge),
      ],
    );
  }
}
