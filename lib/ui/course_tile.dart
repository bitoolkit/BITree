import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../schedule/model.dart';
import 'course_detail.dart';
import 'theme.dart';

class CourseTile extends StatelessWidget {
  const CourseTile({
    super.key,
    required this.course,
    required this.controller,
    required this.isToday,
    required this.isCurrent,
  });

  final Course course;
  final AppController controller;
  final bool isToday;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final colors = courseColors(context, course);

    return Semantics(
      button: true,
      label:
          '${course.name}，${course.timeLabel}，${course.room}${isToday ? '，今天' : ''}，查看详情',
      child: ExcludeSemantics(
        child: Tooltip(
          message: '${course.name}\n${course.room}\n${course.teacher}',
          child: Material(
            color: colors.fill,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: isCurrent
                  ? BorderSide(color: colors.accent, width: 1.5)
                  : BorderSide.none,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => showCourse(context, controller, course),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 100;
                  final fontSize = narrow ? 12.0 : 14.0;
                  final media = MediaQuery.of(context);
                  final padding = narrow ? 3.0 : 10.0;
                  final width = constraints.maxWidth - padding * 2;
                  final available = constraints.maxHeight - 12;
                  final defaults = DefaultTextStyle.of(context);
                  final titleStyle = TextStyle(
                    fontSize: fontSize,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  );
                  final roomStyle = TextStyle(
                    fontSize: fontSize - 1,
                    height: 1.35,
                    color: colors.text.withValues(alpha: 0.8),
                  );

                  TextPainter measure(String text, TextStyle style) =>
                      TextPainter(
                        text: TextSpan(
                          text: text,
                          style: defaults.style
                              .merge(style)
                              .copyWith(
                                fontWeight: media.boldText
                                    ? FontWeight.bold
                                    : null,
                                height: media.lineHeightScaleFactorOverride,
                                letterSpacing: media.letterSpacingOverride,
                                wordSpacing: media.wordSpacingOverride,
                              ),
                        ),
                        textDirection: Directionality.of(context),
                        textScaler: media.textScaler,
                        locale: Localizations.maybeLocaleOf(context),
                        textHeightBehavior:
                            defaults.textHeightBehavior ??
                            DefaultTextHeightBehavior.maybeOf(context),
                        textWidthBasis: defaults.textWidthBasis,
                      )..layout(maxWidth: width);

                  final title = measure(course.name, titleStyle);
                  final room = measure(course.room, roomStyle);
                  var titleLines = title.computeLineMetrics().length;
                  var roomLines = course.room.isEmpty
                      ? 0
                      : room.computeLineMetrics().length;
                  if (title.height + (roomLines > 0 ? room.height + 4 : 0) >
                      available) {
                    title.maxLines = 1;
                    title.layout(maxWidth: width);
                    room.maxLines = 1;
                    room.layout(maxWidth: width);
                    final reserveRoom =
                        roomLines > 0 &&
                        title.height + room.height + 4 <= available;
                    titleLines = _fittingLines(
                      title,
                      width,
                      available - (reserveRoom ? room.height + 4 : 0),
                    );
                    roomLines = reserveRoom
                        ? _fittingLines(
                            room,
                            width,
                            available - title.height - 4,
                          )
                        : 0;
                  }
                  title.dispose();
                  room.dispose();
                  return Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: padding,
                      vertical: 6,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: Text(
                            course.name,
                            textAlign: TextAlign.start,
                            softWrap: true,
                            maxLines: titleLines > 0 ? titleLines : 1,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle,
                          ),
                        ),
                        if (roomLines > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            course.room,
                            textAlign: TextAlign.start,
                            softWrap: true,
                            maxLines: roomLines,
                            overflow: TextOverflow.ellipsis,
                            style: roomStyle,
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

int _fittingLines(TextPainter painter, double width, double height) {
  // Measure every wrapped line before applying a limit and an ellipsis.
  painter.maxLines = null;
  painter.ellipsis = null;
  painter.layout(maxWidth: width);
  var upper = painter.computeLineMetrics().length;
  if (painter.height <= height) return upper;

  var lower = 0;
  painter.ellipsis = '…';
  while (lower < upper) {
    final middle = (lower + upper + 1) ~/ 2;
    painter.maxLines = middle;
    painter.layout(maxWidth: width);
    if (painter.height <= height) {
      lower = middle;
    } else {
      upper = middle - 1;
    }
  }
  painter.maxLines = lower > 0 ? lower : 1;
  painter.layout(maxWidth: width);
  return lower;
}
