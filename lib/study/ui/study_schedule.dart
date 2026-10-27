import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../core/async/cancelable_request.dart';
import '../../schedule/model.dart';
import '../../schedule/selection.dart';
import '../../schedule/ui/course_detail.dart';
import '../model.dart';
import 'study_common.dart';
import 'study_course.dart';
import 'study_legacy_live.dart';
import 'study_reader.dart';

Future<void> openScheduledStudy(
  BuildContext context,
  AppController app,
  Course course, {
  DateTime? date,
}) {
  final schedule = app.timetable.schedule;
  final occurrence =
      date ??
      (schedule != null && course.weekday != null
          ? schedule
                .mondayAt(app.timetable.week)
                .add(Duration(days: course.weekday! - 1))
          : null);
  if (occurrence == null || course.startSection == null) {
    return showCourse(context, app, course, date: date);
  }
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _ScheduledStudy(
        app: app,
        course: course,
        selection: TimetableSelection(
          date: occurrence,
          startSection: course.startSection!,
          endSection: course.endSection!,
        ),
      ),
    ),
  );
}

class _ScheduledStudy extends StatefulWidget {
  const _ScheduledStudy({
    required this.app,
    required this.course,
    required this.selection,
  });
  final AppController app;
  final Course course;
  final TimetableSelection selection;
  @override
  State<_ScheduledStudy> createState() => _ScheduledStudyState();
}

class _ScheduledStudyState extends State<_ScheduledStudy> {
  final _cancel = CancellationToken();
  bool _loading = true;

  Widget _details() => Builder(
    builder: (context) => IconButton(
      tooltip: '课表课程详情',
      icon: const Icon(Icons.info_outline_rounded),
      onPressed: () => showCourse(
        context,
        widget.app,
        widget.course,
        date: widget.selection.date,
      ),
    ),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  @override
  void dispose() {
    _cancel.cancel();
    super.dispose();
  }

  String _name(String value) =>
      value.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  bool _offering(StudyCourse course) =>
      course.remote &&
      _name(course.title) == _name(widget.course.name) &&
      course.term == widget.app.timetable.schedule?.term;

  bool _overlaps(DateTime? start, DateTime? end) {
    if (start == null || end == null) return false;
    final from = start.toUtc().add(const Duration(hours: 8));
    final to = end.toUtc().add(const Duration(hours: 8));
    return from.isBefore(widget.selection.endsAt) &&
        to.isAfter(widget.selection.startsAt);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final verify = studyVerify(context);
    await studyOperation(context, '打开课程学习', () async {
      var courses = widget.app.study.courses.where(_offering).toList();
      if (courses.isEmpty && widget.app.school.username != null) {
        courses = (await widget.app.study.repository.courses(
          verify,
          _cancel,
          search: widget.course.name,
        )).where(_offering).toList();
      }
      _cancel.check();
      final teachers = courses
          .where(
            (course) => _name(course.teacher) == _name(widget.course.teacher),
          )
          .toList();
      if (widget.course.teacher.isNotEmpty) courses = teachers;
      Widget? destination;
      final now = campusNow();
      final live =
          !now.isBefore(widget.selection.startsAt) &&
          now.isBefore(widget.selection.endsAt);
      if (courses.length == 1) {
        var course = courses.single;
        if (widget.app.school.username != null) {
          course = await widget.app.study.refreshCourse(
            course.id,
            verify,
            _cancel,
          );
        }
        _cancel.check();
        final lectures = course.lectures
            .where((lecture) => _overlaps(lecture.startsAt, lecture.endsAt))
            .toList();
        if (lectures.length == 1 &&
            (live
                ? lectures.single.status.canPlay
                : now.isAfter(widget.selection.endsAt) &&
                      lectures.single.status == StudyLectureStatus.recorded)) {
          destination = StudyReader(
            app: widget.app,
            course: course,
            lecture: lectures.single,
            initial: StudyMaterial.video,
            courseAction: _details(),
          );
        } else {
          destination = StudyCourseScreen(
            app: widget.app,
            courses: [course],
            courseAction: _details(),
          );
        }
      } else if (courses.isNotEmpty) {
        destination = StudyCourseScreen(
          app: widget.app,
          courses: courses,
          courseAction: _details(),
        );
      }
      // Public classroom broadcasts use a separate playback ID. Only use one
      // when the actual timetable occurrence matches, rather than its name alone.
      if (live && (destination == null || destination is StudyCourseScreen)) {
        await widget.app.study.broadcasts.refresh(
          widget.selection.date,
          verify,
          signedIn: widget.app.school.username != null,
        );
        _cancel.check();
        final public = widget.app.study.broadcasts.items
            .where(
              (item) =>
                  item.legacy != null &&
                  item.status == StudyLectureStatus.live &&
                  _name(item.title) == _name(widget.course.name) &&
                  _overlaps(item.startsAt, item.endsAt) &&
                  (widget.course.room.isEmpty ||
                      item.location.contains(widget.course.room)),
            )
            .toList();
        if (public.length == 1) {
          destination = LegacyLiveScreen(
            item: public.single.legacy!,
            courseAction: _details(),
          );
        }
      }
      if (!mounted || destination == null) return;
      unawaited(
        Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute(builder: (_) => destination!),
        ),
      );
    });
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.course.name), actions: [_details()]),
    body: Center(
      child: _loading
          ? const CircularProgressIndicator()
          : StudyEmpty(
              text: '还没有找到这门课的学习资料',
              action: Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton(
                    onPressed: () async {
                      if (await studyAccount(context, widget.app) && mounted) {
                        await _load();
                      }
                    },
                    child: const Text('获取课程'),
                  ),
                  TextButton(
                    onPressed: () => showCourse(
                      context,
                      widget.app,
                      widget.course,
                      date: widget.selection.date,
                    ),
                    child: const Text('课程详情'),
                  ),
                ],
              ),
            ),
    ),
  );
}
