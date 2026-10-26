import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'swipe_pager.dart';
import 'timetable.dart';

class WeekPager extends StatefulWidget {
  const WeekPager({super.key, required this.controller, this.active = true});

  final AppController controller;
  final bool active;

  @override
  State<WeekPager> createState() => _WeekPagerState();
}

class _WeekPagerState extends State<WeekPager> {
  double _scrollOffset = 0;

  @override
  Widget build(BuildContext context) {
    final weeks = widget.controller.weeks;
    return SwipePager(
      index: weeks.indexOf(widget.controller.week),
      itemCount: weeks.length,
      onChanged: (page) => widget.controller.selectWeek(weeks[page]),
      itemBuilder: (context, page) => Timetable(
        controller: widget.controller,
        week: weeks[page],
        initialScrollOffset: _scrollOffset,
        onScroll: (offset) => _scrollOffset = offset,
        active: widget.active && weeks[page] == widget.controller.week,
      ),
    );
  }
}
