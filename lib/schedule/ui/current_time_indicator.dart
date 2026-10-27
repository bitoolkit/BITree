import 'package:flutter/material.dart';

import '../model.dart';
import '../time_position.dart';

/// A non-interactive overlay for the timetable's equal-height section grid.
class CurrentTimeIndicator extends StatelessWidget {
  const CurrentTimeIndicator({
    super.key,
    required this.now,
    required this.monday,
    required this.columnWidth,
    required this.rowHeight,
  });

  static const _lineHeight = 2.0;
  static const _horizontalInset = 3.0;

  final DateTime now;
  final DateTime monday;
  final double columnWidth;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    final position = timeIndicatorPositionAt(now);
    final day = calendarDate(position.time)
        .difference(calendarDate(monday))
        .inDays;
    final gridHeight = rowHeight * sectionTimes.length;
    if (day < 0 ||
        day >= 7 ||
        columnWidth <= _horizontalInset * 2 ||
        gridHeight < _lineHeight) {
      return const SizedBox.shrink();
    }

    final top = (position.section * rowHeight - _lineHeight / 2)
        .clamp(0.0, gridHeight - _lineHeight)
        .toDouble();
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Stack(
          children: [
            Positioned(
              left: day * columnWidth + _horizontalInset,
              top: top,
              width: columnWidth - _horizontalInset * 2,
              height: _lineHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(_lineHeight / 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
