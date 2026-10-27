import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../core/async/cancelable_request.dart';
import '../../ui/app_menu_anchor.dart';
import '../../ui/app_menu_trigger.dart';
import '../library.dart';
import '../model.dart';
import 'study_common.dart';
import 'study_course_materials.dart';
import 'study_layout.dart';
import 'study_organize.dart';
import 'study_reader.dart';
import 'study_review.dart';

class StudyCourseScreen extends StatefulWidget {
  const StudyCourseScreen({
    super.key,
    required this.app,
    required this.courses,
  });
  final AppController app;
  final List<StudyCourse> courses;
  @override
  State<StudyCourseScreen> createState() => _StudyCourseScreenState();
}

class _StudyCourseScreenState extends State<StudyCourseScreen> {
  late final List<StudyCourse> _courses = List.of(widget.courses);
  String? _teacher;
  final _cancel = CancellationToken();
  bool _loading = false;

  List<StudyCourse> get _selected => _courses
      .where(
        (course) =>
            !course.isEmptyRemote &&
            (_teacher == null || course.teacher == _teacher),
      )
      .toList();

  List<(StudyCourse, StudyLecture)> get _lectures {
    final items = [
      for (final course in _selected)
        for (final lecture in course.lectures) (course, lecture),
    ];
    int rank(StudyLectureStatus status) => switch (status) {
      StudyLectureStatus.live => 0,
      StudyLectureStatus.upcoming => 2,
      _ => 1,
    };
    items.sort((a, b) {
      final status = rank(a.$2.status).compareTo(rank(b.$2.status));
      if (status != 0) return status;
      final date = a.$2.status == StudyLectureStatus.upcoming
          ? (a.$2.startsAt ?? DateTime(0)).compareTo(
              b.$2.startsAt ?? DateTime(0),
            )
          : (b.$2.startsAt ?? DateTime(0)).compareTo(
              a.$2.startsAt ?? DateTime(0),
            );
      return date != 0 ? date : a.$2.id.compareTo(b.$2.id);
    });
    return items;
  }

  @override
  void initState() {
    super.initState();
    widget.app.study.addListener(_changed);
    if (_courses.any(
      (course) =>
          course.remote &&
          ((course.lectures.isEmpty && course.lectureCount != 0) ||
              course.lectures.any(
                (lecture) => lecture.status != StudyLectureStatus.recorded,
              )),
    )) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_refresh()),
      );
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.app.study.removeListener(_changed);
    _cancel.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading || !await studyAccount(context, widget.app) || !mounted) {
      return;
    }
    setState(() => _loading = true);
    final verify = studyVerify(context);
    await studyOperation(context, '读取课程课时', () async {
      for (var index = 0; index < _courses.length; index++) {
        if (!_courses[index].remote) continue;
        _cancel.check();
        _courses[index] = await widget.app.study.refreshCourse(
          _courses[index].id,
          verify,
          _cancel,
        );
      }
    });
    if (mounted) setState(() => _loading = false);
  }

  Future<StudyCourse?> _chooseCourse({bool recordingsOnly = false}) async {
    final selected = _selected
        .where(
          (course) =>
              !recordingsOnly ||
              course.lectures.any(
                (lecture) => lecture.status == StudyLectureStatus.recorded,
              ),
        )
        .toList();
    if (selected.isEmpty) return null;
    if (selected.length == 1) return selected.single;
    return showDialog<StudyCourse>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择授课班级'),
        children: [
          for (final course in selected)
            ListTile(
              title: Text(course.teacher.isEmpty ? '未标注教师' : course.teacher),
              subtitle: Text('${course.lectures.length} 课时'),
              onTap: () => Navigator.pop(context, course),
            ),
        ],
      ),
    );
  }

  Future<void> _review() async {
    final course = await _chooseCourse();
    if (course != null && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => StudyReviewScreen(app: widget.app, course: course),
        ),
      );
    }
  }

  Future<void> _organize() async {
    final course = await _chooseCourse(recordingsOnly: true);
    if (course != null && mounted) {
      await showStudyOrganize(context, widget.app, course);
    }
  }

  Future<void> _import() async {
    final course = await _chooseCourse();
    if (course == null || !mounted) return;
    final result = await studyOperation(
      context,
      '选择本地录播',
      () => FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['mp4', 'mkv', 'mov', 'webm'],
      ),
    );
    if (result?.path == null || !mounted) return;
    final lecture = await studyOperation(
      context,
      '导入录播',
      () => widget.app.study.importRecording(
        course,
        result!.path!,
        result.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
      ),
    );
    if (lecture != null && mounted) _open(course, lecture, StudyMaterial.video);
  }

  void _open(
    StudyCourse course,
    StudyLecture lecture,
    StudyMaterial material, {
    Duration? position,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => StudyReader(
        app: widget.app,
        course: course,
        lecture: lecture,
        initial: material,
        initialPosition: position,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final lectures = _lectures;
    final teachers =
        _courses
            .where((course) => !course.isEmptyRemote)
            .map((course) => course.teacher)
            .toSet()
            .toList()
          ..sort();
    final recordings = lectures
        .where((item) => item.$2.status == StudyLectureStatus.recorded)
        .toList();
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(title: const Text('学习', style: TextStyle(fontSize: 14))),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1380),
              child: StudyContent(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StudyHeading(
                      _courses.first.title,
                      subtitle: [
                        if (_courses.first.term.isNotEmpty)
                          studyTermLabel(_courses.first.term),
                        if (teachers.length == 1 && teachers.single.isNotEmpty)
                          teachers.single,
                        '${lectures.length} 课时',
                      ].join(' · '),
                      leading: StudyCourseMark(
                        _courses.first.title,
                        large: true,
                      ),
                    ),
                    if (teachers.length > 1)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(61, 4, 0, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (teachers.length > 1)
                                AppMenuAnchor(
                                  menuChildren: [
                                    for (final teacher in [null, ...teachers])
                                      AppMenuItemButton(
                                        trailingIcon: teacher == _teacher
                                            ? const Icon(
                                                Icons.check_rounded,
                                                size: 18,
                                              )
                                            : const SizedBox(width: 18),
                                        onPressed: () =>
                                            setState(() => _teacher = teacher),
                                        child: Text(
                                          teacher == null
                                              ? '全部教师'
                                              : teacher.isEmpty
                                              ? '未标注教师'
                                              : teacher,
                                        ),
                                      ),
                                  ],
                                  builder: (context, menu, open) =>
                                      AppMenuTrigger(
                                        label: _teacher == null
                                            ? '全部教师'
                                            : _teacher!.isEmpty
                                            ? '未标注教师'
                                            : _teacher!,
                                        semanticsLabel: '筛选授课教师',
                                        isOpen: open,
                                        onPressed: () =>
                                            open ? menu.close() : menu.open(),
                                      ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    const TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      tabs: [
                        Tab(text: '课时'),
                        Tab(text: '课件与字幕'),
                        Tab(text: '课程笔记'),
                      ],
                    ),
                    if (_loading) const LinearProgressIndicator(minHeight: 2),
                    Expanded(
                      child: TabBarView(
                        children: [
                          Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  0,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Wrap(
                                    spacing: 8,
                                    children: [
                                      if (_courses.any(
                                        (course) => course.remote,
                                      ))
                                        TextButton.icon(
                                          onPressed: _loading ? null : _refresh,
                                          icon: const Icon(
                                            Icons.sync_rounded,
                                            size: 17,
                                          ),
                                          label: const Text('更新课时'),
                                        ),
                                      TextButton.icon(
                                        onPressed: _selected.isEmpty
                                            ? null
                                            : _import,
                                        icon: const Icon(
                                          Icons.video_file_outlined,
                                          size: 17,
                                        ),
                                        label: const Text('导入本地录播'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Expanded(
                                child: lectures.isEmpty
                                    ? StudyEmpty(
                                        text: _loading ? '正在读取课时' : '暂无课时',
                                        action: _loading
                                            ? null
                                            : OutlinedButton(
                                                onPressed: _courses.first.remote
                                                    ? _refresh
                                                    : _import,
                                                child: Text(
                                                  _courses.first.remote
                                                      ? '重新获取'
                                                      : '导入录播',
                                                ),
                                              ),
                                      )
                                    : ListView.separated(
                                        padding: const EdgeInsets.fromLTRB(
                                          0,
                                          8,
                                          0,
                                          24,
                                        ),
                                        itemCount: lectures.length,
                                        separatorBuilder: (_, _) =>
                                            const Divider(height: 1),
                                        itemBuilder: (context, index) {
                                          final (course, lecture) =
                                              lectures[index];
                                          final resume =
                                              widget.app.study.lastReading;
                                          return _LectureRow(
                                            key: ValueKey(
                                              '${course.id}/${lecture.id}',
                                            ),
                                            course: course,
                                            lecture: lecture,
                                            showTeacher:
                                                teachers.length > 1 &&
                                                _teacher == null,
                                            resume:
                                                resume?.course == course.id &&
                                                resume?.lecture == lecture.id,
                                            onOpen: (kind) =>
                                                _open(course, lecture, kind),
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                          Builder(
                            builder: (materialContext) => StudyCourseMaterials(
                              app: widget.app,
                              entries: recordings,
                              onOpen: _open,
                              onOrganize: recordings.isEmpty ? null : _organize,
                              onReview: _selected.isEmpty ? null : _review,
                              onNotes: () =>
                                  DefaultTabController.of(materialContext)
                                      .animateTo(2),
                            ),
                          ),
                          StudyCourseMaterials(
                            app: widget.app,
                            entries: lectures,
                            notesOnly: true,
                            onOpen: _open,
                            onOrganize: recordings.isEmpty ? null : _organize,
                            onReview: _selected.isEmpty ? null : _review,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LectureRow extends StatelessWidget {
  const _LectureRow({
    super.key,
    required this.course,
    required this.lecture,
    required this.showTeacher,
    required this.resume,
    required this.onOpen,
  });
  final StudyCourse course;
  final StudyLecture lecture;
  final bool showTeacher;
  final bool resume;
  final ValueChanged<StudyMaterial> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = lecture.startsAt?.toUtc().add(const Duration(hours: 8));
    final live = lecture.status == StudyLectureStatus.live;
    final label = live
        ? '观看直播'
        : resume
        ? '继续观看'
        : '观看回放';
    final icon = Icon(
      live ? Icons.live_tv_rounded : Icons.play_arrow_rounded,
      size: 18,
    );
    final play = !lecture.status.canPlay
        ? Text(lecture.status.label, style: theme.textTheme.bodySmall)
        : resume && !live
        ? FilledButton.icon(
            onPressed: () => onOpen(StudyMaterial.video),
            icon: icon,
            label: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: () => onOpen(StudyMaterial.video),
            icon: icon,
            label: Text(label),
            style: live
                ? OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(color: theme.colorScheme.error),
                  )
                : null,
          );
    return LayoutBuilder(
      builder: (context, size) {
        final narrow =
            size.maxWidth < 550 ||
            MediaQuery.textScalerOf(context).scale(14) > 19;
        return Container(
          padding: EdgeInsets.symmetric(
            vertical: 15,
            horizontal: live ? 16 : 0,
          ),
          decoration: live
              ? BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(
                    alpha: .16,
                  ),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 54,
                child: Column(
                  children: [
                    Text(
                      date == null ? '—' : '${date.day}',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (date != null)
                      Text('${date.month}月', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: lecture.status.canPlay
                          ? () => onOpen(StudyMaterial.video)
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          studyLectureTitle(lecture),
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ),
                    if (showTeacher)
                      Text(course.teacher, style: theme.textTheme.bodySmall),
                    if (lecture.status == StudyLectureStatus.recorded || live)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          [
                            if (lecture.startsAt case final start?)
                              studyClock(start) +
                                  (lecture.endsAt == null
                                      ? ''
                                      : '–${studyClock(lecture.endsAt!)}'),
                            lecture.status.label,
                          ].join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: live
                                ? theme.colorScheme.error
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 0,
                      children: [
                        for (final (kind, label, icon) in [
                          if (lecture.status ==
                              StudyLectureStatus.recorded) ...[
                            (
                              StudyMaterial.slides,
                              '课件',
                              Icons.slideshow_outlined,
                            ),
                            (
                              StudyMaterial.transcript,
                              '字幕',
                              Icons.subtitles_outlined,
                            ),
                          ],
                          (StudyMaterial.notes, '笔记', Icons.edit_note_rounded),
                        ])
                          TextButton.icon(
                            onPressed: () => onOpen(kind),
                            icon: Icon(icon, size: 16),
                            label: Text(label),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              foregroundColor:
                                  theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    if (narrow) play,
                  ],
                ),
              ),
              if (!narrow) ...[const SizedBox(width: 16), play],
            ],
          ),
        );
      },
    );
  }
}
