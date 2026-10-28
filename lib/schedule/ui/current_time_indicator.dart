import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../model.dart';
import '../time_position.dart';

/// One non-interactive time line over the grid, masked by the cards it crosses.
class CurrentTimeIndicator extends StatelessWidget {
  const CurrentTimeIndicator({
    super.key,
    required this.now,
    required this.monday,
    required this.columnWidth,
    required this.rowHeight,
    required this.cards,
  });

  static const _lineHeight = 2.0;

  final DateTime now;
  final DateTime monday;
  final double columnWidth;
  final double rowHeight;
  final List<({RRect shape, Color color})> cards;

  /// Shared grid-space center for the time line and the elapsed course fill.
  static double centerAt(double section, double rowHeight) {
    final gridHeight = rowHeight * sectionTimes.length;
    return (section * rowHeight - _lineHeight / 2)
            .clamp(0.0, gridHeight - _lineHeight)
            .toDouble() +
        _lineHeight / 2;
  }

  @override
  Widget build(BuildContext context) {
    final position = timeIndicatorPositionAt(now);
    final day = calendarDate(position.time)
        .difference(calendarDate(monday))
        .inDays;
    final gridHeight = rowHeight * sectionTimes.length;
    if (day < 0 || day >= 7 || columnWidth <= 0 || gridHeight < _lineHeight) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: ExcludeSemantics(
        child: CustomPaint(
          painter: _TimeLinePainter(
            center: centerAt(position.section, rowHeight),
            day: day,
            columnWidth: columnWidth,
            color: Theme.of(context).colorScheme.primary,
            cards: cards,
          ),
        ),
      ),
    );
  }
}

class _TimeLinePainter extends CustomPainter {
  const _TimeLinePainter({
    required this.center,
    required this.day,
    required this.columnWidth,
    required this.color,
    required this.cards,
  });

  final double center;
  final int day;
  final double columnWidth;
  final Color color;
  final List<({RRect shape, Color color})> cards;

  @override
  void paint(Canvas canvas, Size size) {
    final crossed = cards
        .where(
          (card) =>
              card.shape.top < center + 1 && card.shape.bottom > center - 1,
        )
        .toList();
    final outlines = Path();
    for (final card in crossed) {
      outlines.addRRect(card.shape);
    }

    // Keep the original colour in the gaps and around the rounded corners.
    canvas.save();
    canvas.clipPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        outlines,
      ),
    );
    _drawLine(canvas, size, color, BlendMode.srcOver);
    canvas.restore();

    // Overlay preserves the card's hue and the light/dark text under the line.
    for (final card in crossed) {
      canvas.save();
      canvas.clipRRect(card.shape);
      _drawLine(canvas, size, card.color, BlendMode.overlay);
      canvas.restore();
    }
  }

  void _drawLine(Canvas canvas, Size size, Color color, BlendMode blendMode) {
    final paint = Paint()
      ..blendMode = blendMode
      ..color = color.withValues(alpha: 0.28);
    canvas.drawRect(Rect.fromLTWH(0, center - 0.5, size.width, 1), paint);
    canvas.drawRect(
      Rect.fromLTWH(day * columnWidth, center - 1, columnWidth, 2),
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_TimeLinePainter oldDelegate) =>
      center != oldDelegate.center ||
      day != oldDelegate.day ||
      columnWidth != oldDelegate.columnWidth ||
      color != oldDelegate.color ||
      !listEquals(cards, oldDelegate.cards);
}
