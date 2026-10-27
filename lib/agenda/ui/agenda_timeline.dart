import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/controller.dart';
import '../../schedule/model.dart';
import '../model.dart';
import '../timeline_layout.dart';
import 'agenda_detail.dart';

const _microsecondsPerHour = Duration.microsecondsPerSecond * 3600;

/// A viewport-sized timeline: panning changes a date, not a giant scroll offset.
class AgendaTimeline extends StatefulWidget {
  const AgendaTimeline({
    super.key,
    required this.controller,
    required this.entries,
    required this.now,
    this.active = true,
  });

  final AppController controller;
  final List<AgendaEntry> entries;
  final DateTime now;

  /// Reset the date on page re-entry, not when changing list/timeline mode.
  final bool active;

  @override
  State<AgendaTimeline> createState() => _AgendaTimelineState();
}

class _AgendaTimelineState extends State<AgendaTimeline> {
  final ScrollController _lanes = ScrollController();
  late DateTime _center;
  double _zoom = 1;
  double _gestureZoom = 1;
  int _gesturePointers = 0;
  DateTime? _gestureAnchor;
  List<AgendaEntry>? _cachedEntries;
  double? _cachedPixelsPerHour;
  List<AgendaTimelinePlacement> _cachedPlacements = const [];

  List<AgendaTimelinePlacement> _layout(double pixelsPerHour) {
    if (!identical(_cachedEntries, widget.entries) ||
        _cachedPixelsPerHour != pixelsPerHour) {
      _cachedEntries = widget.entries;
      _cachedPixelsPerHour = pixelsPerHour;
      _cachedPlacements = layoutAgendaTimeline(
        widget.entries,
        pixelsPerHour: pixelsPerHour,
        // Tiny real-duration bars get a transparent 24px tap target below.
        gap: 24,
      );
    }
    return _cachedPlacements;
  }

  @override
  void initState() {
    super.initState();
    _center = calendarDate(widget.now).add(const Duration(hours: 12));
    _lanes.addListener(_laneChanged);
  }

  @override
  void didUpdateWidget(covariant AgendaTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      _center = calendarDate(widget.now).add(const Duration(hours: 12));
    }
  }

  void _laneChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _lanes.removeListener(_laneChanged);
    _lanes.dispose();
    super.dispose();
  }

  DateTime _timeAt(double x, double width, double pixelsPerHour) =>
      _center.add(Duration(
        microseconds: ((x - width / 2) / pixelsPerHour *
                _microsecondsPerHour)
            .round(),
      ));

  void _scrollLanes(double delta) {
    if (!_lanes.hasClients) return;
    _lanes.jumpTo((_lanes.offset + delta)
        .clamp(0.0, _lanes.position.maxScrollExtent)
        .toDouble());
  }

  void _zoomAt(double zoom, double x, double width, double baseline) {
    final anchor = _timeAt(x, width, baseline * _zoom);
    final next = zoom.clamp(1.0, 24.0).toDouble();
    setState(() {
      _zoom = next;
      _center = anchor.subtract(Duration(
        microseconds: ((x - width / 2) / (baseline * next) *
                _microsecondsPerHour)
            .round(),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final fontScale = math.max(1.0, textScaler.scale(14) / 14);
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final cellWidth = (width / 5).clamp(80.0, 140.0).toDouble();
      final baseline = cellWidth / 24;
      final pixelsPerHour = baseline * _zoom;
      final hoursPerCell = 24 / _zoom;
      final scaleLabel = _zoom == 1
          ? '1 天 / 格'
          : _zoom == 24
              ? '1 小时 / 格'
              : '${hoursPerCell.toStringAsFixed(1)} 小时 / 格';
      final headerHeight = 60.0 * fontScale;
      final laneHeight = 82.0 * fontScale;
      final placements = _layout(pixelsPerHour);
      final laneCount = placements.fold<int>(
        0,
        (count, placement) => math.max(count, placement.lane + 1),
      );
      final left = _timeAt(0, width, pixelsPerHour);
      final right = _timeAt(width, width, pixelsPerHour);
      final painter = _TimelineGridPainter(
        center: _center,
        now: widget.now,
        pixelsPerHour: pixelsPerHour,
        scheme: theme.colorScheme,
        textStyle: theme.textTheme.labelMedium ?? const TextStyle(fontSize: 12),
        textScaler: textScaler,
        header: true,
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () => setState(() {
                    _center = calendarDate(widget.now)
                        .add(const Duration(hours: 12));
                  }),
                  icon: const Icon(Icons.today_outlined, size: 18),
                  label: const Text('今天'),
                ),
                Text(
                  '${_center.year}年${_center.month}月${_center.day}日',
                  style: theme.textTheme.labelLarge,
                ),
                Tooltip(
                  message: '缩放：从每天一格到每小时一格',
                  child: SizedBox(
                    width: math.min(220.0, math.max(100.0, width - 48)),
                    child: Slider(
                      value: _zoom,
                      min: 1,
                      max: 24,
                      label: scaleLabel,
                      semanticFormatterCallback: (_) => scaleLabel,
                      onChanged: (value) =>
                          _zoomAt(value, width / 2, width, baseline),
                    ),
                  ),
                ),
                Text(scaleLabel, style: theme.textTheme.labelMedium),
                Tooltip(
                  message: '拖动浏览时间；双指缩放。滚轮平移，Ctrl + 滚轮缩放，'
                      'Shift + 滚轮或上下拖动浏览日程行。',
                  child: Icon(
                    Icons.help_outline,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Listener(
              onPointerSignal: (event) {
                if (event is! PointerScrollEvent) return;
                GestureBinding.instance.pointerSignalResolver.register(
                  event,
                  (resolved) {
                    final scroll = resolved as PointerScrollEvent;
                    final keys = HardwareKeyboard.instance.logicalKeysPressed;
                    final control = keys.contains(LogicalKeyboardKey.controlLeft) ||
                        keys.contains(LogicalKeyboardKey.controlRight);
                    final shift = keys.contains(LogicalKeyboardKey.shiftLeft) ||
                        keys.contains(LogicalKeyboardKey.shiftRight);
                    final delta = scroll.scrollDelta.dy != 0
                        ? scroll.scrollDelta.dy
                        : scroll.scrollDelta.dx;
                    if (control) {
                      _zoomAt(
                        _zoom * math.exp(-delta / 350),
                        scroll.localPosition.dx,
                        width,
                        baseline,
                      );
                    } else if (shift) {
                      _scrollLanes(delta);
                    } else {
                      setState(() {
                        _center = _center.add(Duration(
                          microseconds: ((scroll.scrollDelta.dx +
                                      scroll.scrollDelta.dy) /
                                  pixelsPerHour *
                                  _microsecondsPerHour)
                              .round(),
                        ));
                      });
                    }
                  },
                );
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: (details) {
                  _gesturePointers = details.pointerCount;
                  _gestureZoom = _zoom;
                  _gestureAnchor = _timeAt(
                    details.localFocalPoint.dx,
                    width,
                    pixelsPerHour,
                  );
                },
                onScaleUpdate: (details) {
                  // Adding/removing a finger changes the focal point. Rebase so
                  // that transition does not jump to another calendar time.
                  if (_gesturePointers != details.pointerCount) {
                    _gestureAnchor = _timeAt(
                      details.localFocalPoint.dx,
                      width,
                      baseline * _zoom,
                    );
                    _gestureZoom = _zoom / details.scale;
                    _gesturePointers = details.pointerCount;
                  }
                  final next = (_gestureZoom * details.scale)
                      .clamp(1.0, 24.0)
                      .toDouble();
                  final anchor = _gestureAnchor;
                  if (anchor == null) return;
                  setState(() {
                    _zoom = next;
                    _center = anchor.subtract(Duration(
                      microseconds: ((details.localFocalPoint.dx - width / 2) /
                              (baseline * next) *
                              _microsecondsPerHour)
                          .round(),
                    ));
                  });
                  if (details.pointerCount == 1) {
                    _scrollLanes(-details.focalPointDelta.dy);
                  }
                },
                onScaleEnd: (_) => _gestureAnchor = null,
                child: Column(
                  children: [
                    SizedBox(
                      height: headerHeight,
                      width: width,
                      child: CustomPaint(painter: painter),
                    ),
                    Expanded(
                      child: LayoutBuilder(builder: (context, laneConstraints) {
                        final height = laneConstraints.maxHeight;
                        final contentHeight = math.max(
                          height,
                          laneCount * laneHeight + 24,
                        );
                        final offset = _lanes.hasClients ? _lanes.offset : 0.0;
                        final visible = placements.where((placement) =>
                            placement.end.isAfter(left) &&
                            placement.start.isBefore(right) &&
                            (placement.lane + 1) * laneHeight >= offset &&
                            placement.lane * laneHeight <= offset + height);
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            CustomPaint(
                              painter: _TimelineGridPainter(
                                center: _center,
                                now: widget.now,
                                pixelsPerHour: pixelsPerHour,
                                scheme: theme.colorScheme,
                                textStyle: theme.textTheme.labelMedium ??
                                    const TextStyle(fontSize: 12),
                                textScaler: textScaler,
                                header: false,
                              ),
                            ),
                            Scrollbar(
                              controller: _lanes,
                              thumbVisibility: contentHeight > height,
                              interactive: true,
                              child: SingleChildScrollView(
                                controller: _lanes,
                                physics: const NeverScrollableScrollPhysics(),
                                child: SizedBox(
                                  height: contentHeight,
                                  width: width,
                                  child: Stack(
                                    clipBehavior: Clip.hardEdge,
                                    children: [
                                      for (final placement in visible)
                                        _buildEntry(
                                          context,
                                          placement,
                                          width,
                                          pixelsPerHour,
                                          laneHeight,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (widget.entries.isEmpty)
                              Center(
                                child: IgnorePointer(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      '暂无此类日程\n可拖动时间轴，或添加新的日程',
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodyLarge?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _buildEntry(
    BuildContext context,
    AgendaTimelinePlacement placement,
    double width,
    double pixelsPerHour,
    double laneHeight,
  ) {
    final entry = placement.entry;
    final scheme = Theme.of(context).colorScheme;
    double x(DateTime time) => width / 2 +
        time.difference(_center).inMicroseconds /
            _microsecondsPerHour * pixelsPerHour;
    final actualLeft = x(placement.start);
    final actualRight = x(placement.end);
    // Crop long ordinary events before creating widgets; no huge canvas/boxes.
    final left = entry.isDeadline ? actualLeft : math.max(0.0, actualLeft);
    final right = entry.isDeadline ? actualRight : math.min(width, actualRight);
    final barWidth = math.max(1.0, right - left);
    final overdue = entry.overdue(widget.now);
    final finished = entry.isFinished(widget.now);
    final color = finished
        ? scheme.surfaceContainerHighest
        : overdue
            ? scheme.errorContainer
            : switch (entry.kind) {
                AgendaKind.event => scheme.primaryContainer,
                AgendaKind.exam => scheme.tertiaryContainer,
                AgendaKind.deadline => scheme.secondaryContainer,
              };
    final foreground = finished
        ? scheme.onSurfaceVariant
        : overdue
            ? scheme.onErrorContainer
            : switch (entry.kind) {
                AgendaKind.event => scheme.onPrimaryContainer,
                AgendaKind.exam => scheme.onTertiaryContainer,
                AgendaKind.deadline => scheme.onSecondaryContainer,
              };
    final icon = finished
        ? Icons.check_circle_outline
        : overdue
            ? Icons.warning_amber_rounded
            : switch (entry.kind) {
                AgendaKind.event => Icons.event_outlined,
                AgendaKind.exam => Icons.school_outlined,
                AgendaKind.deadline => Icons.flag_outlined,
              };
    final status = entry.done
        ? '已完成'
        : overdue
            ? '已逾期'
            : finished
                ? '已结束'
                : '';
    final date = entry.startsAt;
    final description = '${entry.kind.label}，${entry.title}，'
        '${date.year}年${date.month}月${date.day}日 '
        '${entry.timeLabel}${status.isEmpty ? '' : '，$status'}'
        '${entry.location.isEmpty ? '' : '，${entry.location}'}';
    return Positioned(
      left: left,
      top: placement.lane * laneHeight + 8,
      width: math.max(24.0, barWidth),
      height: laneHeight - 16,
      child: Semantics(
        button: true,
        label: description,
        onTap: () => showAgendaEntry(context, widget.controller, entry),
        child: Tooltip(
          message: description,
          excludeFromSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: () => showAgendaEntry(context, widget.controller, entry),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: barWidth,
                height: laneHeight - 16,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: entry.isDeadline ? null : color,
                    gradient: entry.isDeadline
                        ? LinearGradient(
                            colors: [color.withValues(alpha: 0), color, color],
                            stops: const [0, 0.35, 1],
                          )
                        : null,
                    borderRadius: entry.isDeadline
                        ? null
                        : BorderRadius.circular(8),
                    border: entry.isDeadline
                        ? Border(right: BorderSide(color: foreground, width: 3))
                        : Border.all(
                            color: foreground.withValues(alpha: 0.35),
                          ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      excludeFromSemantics: true,
                      onTap: () => showAgendaEntry(
                        context,
                        widget.controller,
                        entry,
                      ),
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: entry.isDeadline ? 66 : 8,
                          right: 8,
                          top: 4,
                          bottom: 4,
                        ),
                        child: barWidth < 48
                            ? const SizedBox.shrink()
                            : Column(
                                crossAxisAlignment: entry.isDeadline
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Text(
                                      entry.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: entry.isDeadline
                                          ? TextAlign.right
                                          : TextAlign.left,
                                      style: TextStyle(
                                        fontSize: 14,
                                        height: 1.2,
                                        fontWeight: FontWeight.w600,
                                        color: foreground,
                                        decoration: entry.done
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(icon, size: 13, color: foreground),
                                      const SizedBox(width: 3),
                                      Flexible(
                                        child: Text(
                                          '${entry.kind.label}'
                                          '${status.isEmpty ? '' : ' · $status'}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: foreground,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
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
    );
  }
}

class _TimelineGridPainter extends CustomPainter {
  const _TimelineGridPainter({
    required this.center,
    required this.now,
    required this.pixelsPerHour,
    required this.scheme,
    required this.textStyle,
    required this.textScaler,
    required this.header,
  });

  final DateTime center;
  final DateTime now;
  final double pixelsPerHour;
  final ColorScheme scheme;
  final TextStyle textStyle;
  final TextScaler textScaler;
  final bool header;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    double x(DateTime time) => size.width / 2 +
        time.difference(center).inMicroseconds /
            _microsecondsPerHour * pixelsPerHour;
    final left = center.subtract(Duration(
      microseconds: (size.width / 2 / pixelsPerHour *
              _microsecondsPerHour)
          .ceil(),
    ));
    final right = center.add(Duration(
      microseconds: (size.width / 2 / pixelsPerHour *
              _microsecondsPerHour)
          .ceil(),
    ));
    final today = calendarDate(now);
    final dayWidth = 24 * pixelsPerHour;
    canvas.drawRect(
      Rect.fromLTRB(x(today), 0, x(today) + dayWidth, size.height),
      Paint()..color = scheme.primary.withValues(alpha: 0.06),
    );
    final gridPaint = Paint()
      ..strokeWidth = 1
      ..color = scheme.outlineVariant.withValues(alpha: 0.65);
    // Adaptive clock ticks remain readable even with large accessibility text.
    final minLabelWidth = math.max(60.0, textScaler.scale(46));
    final hourStep = <int>[1, 2, 3, 6, 12, 24].firstWhere(
      (hours) => hours * pixelsPerHour >= minLabelWidth,
      orElse: () => 24,
    );
    var day = calendarDate(left);
    while (!day.isAfter(right)) {
      final dayX = x(day);
      canvas.drawLine(Offset(dayX, 0), Offset(dayX, size.height), gridPaint);
      if (header) {
        final nextX = x(day.add(const Duration(days: 1)));
        final visibleLeft = math.max(0.0, dayX);
        final visibleRight = math.min(size.width, nextX);
        if (visibleRight - visibleLeft > minLabelWidth) {
          _label(
            canvas,
            '${day.month}/${day.day}${day == today ? ' 今天' : ''}',
            Offset(visibleLeft + 6, 3),
            math.max(1.0, visibleRight - visibleLeft - 10),
            bold: true,
          );
        }
      }
      for (var hour = hourStep; hour < 24; hour += hourStep) {
        final tick = day.add(Duration(hours: hour));
        final tickX = x(tick);
        if (tickX < 0 || tickX > size.width) continue;
        canvas.drawLine(
          Offset(tickX, header ? size.height * 0.6 : 0),
          Offset(tickX, size.height),
          gridPaint,
        );
        if (header) {
          _label(
            canvas,
            '${hour.toString().padLeft(2, '0')}:00',
            Offset(tickX + 4, size.height * 0.53),
            math.max(1.0, hourStep * pixelsPerHour - 8),
          );
        }
      }
      day = day.add(const Duration(days: 1));
    }
    final nowX = x(now);
    if (nowX >= 0 && nowX <= size.width) {
      canvas.drawLine(
        Offset(nowX, 0),
        Offset(nowX, size.height),
        Paint()..color = scheme.error..strokeWidth = 1.5,
      );
      if (header) {
        canvas.drawCircle(Offset(nowX, size.height - 3), 3, Paint()..color = scheme.error);
      }
    }
    if (header) {
      canvas.drawLine(
        Offset(0, size.height),
        Offset(size.width, size.height),
        gridPaint,
      );
    }
    canvas.restore();
  }

  void _label(
    Canvas canvas,
    String text,
    Offset offset,
    double maxWidth, {
    bool bold = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: textStyle.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _TimelineGridPainter oldDelegate) =>
      oldDelegate.center != center ||
      oldDelegate.now != now ||
      oldDelegate.pixelsPerHour != pixelsPerHour ||
      oldDelegate.scheme != scheme ||
      oldDelegate.textStyle != textStyle ||
      oldDelegate.textScaler != textScaler ||
      oldDelegate.header != header;
}
