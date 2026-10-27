import 'package:flutter/material.dart';

/// Keeps native text layout while revealing the strike through each line.
class CompletionText extends StatelessWidget {
  const CompletionText(
    this.text, {
    super.key,
    required this.completed,
    this.style,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final bool completed;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final baseStyle = DefaultTextStyle.of(context).style.merge(style);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final target = completed ? 1.0 : 0.0;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: target, end: target),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : Duration(milliseconds: completed ? 220 : 180),
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) {
        final textStyle = baseStyle.copyWith(
          color: Color.lerp(baseStyle.color, muted, progress),
          decoration: TextDecoration.none,
        );
        return Stack(
          children: [
            Text(
              text,
              style: textStyle,
              maxLines: maxLines,
              overflow: overflow,
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: SelectionContainer.disabled(
                    child: ClipRect(
                      clipper: _StrikeClipper(
                        progress,
                        Directionality.of(context),
                      ),
                      child: Text(
                        text,
                        style: textStyle.copyWith(
                          color: Colors.transparent,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: muted,
                          decorationThickness: 1.1,
                        ),
                        maxLines: maxLines,
                        overflow: overflow,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StrikeClipper extends CustomClipper<Rect> {
  const _StrikeClipper(this.progress, this.direction);

  final double progress;
  final TextDirection direction;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(
    direction == TextDirection.ltr ? 0 : size.width * (1 - progress),
    0,
    size.width * progress,
    size.height,
  );

  @override
  bool shouldReclip(_StrikeClipper oldClipper) =>
      progress != oldClipper.progress || direction != oldClipper.direction;
}
