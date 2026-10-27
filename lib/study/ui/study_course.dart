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
    final lectures = [
      for (final course in _selected)
        for (final lecture in course.lectures) (course, lecture),
    ];
    lectures.sort((a, b) {
      final date = (b.$2.startsAt ?? DateTime(0)).compareTo(
        a.$2.startsAt ?? DateTime(0),
      );
      return date != 0 ? date : a.$2.id.compareTo(b.$2.id);
    });
    return lectures;
  }

  @override
  void initState() {
    super.initState();
    if (_courses.any(
      (course) =>
          course.remote && course.lectures.isEmpty && course.lectureCount != 0,
    )) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }
  }

  @override
  void dispose() {
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
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<StudyCourse?> _chooseCourse() async {
    final selected = _selected;
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
    if (course == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StudyReviewScreen(app: widget.app, course: course),
      ),
    );
  }

  Future<void> _organize() async {
    final course = await _chooseCourse();
    if (course != null && mounted && course.lectures.isNotEmpty) {
      await showStudyOrganize(context, widget.app, course);
    }
  }

  Future<void> _import() async {
    final course = await _chooseCourse();
    if (course == null || !mounted) return;
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['mp4', 'mkv', 'mov', 'webm'],
    );
    final path = result?.path;
    if (path == null || !mounted) return;
    final lecture = await studyOperation(
      context,
      '导入录播',
      () => widget.app.study.importRecording(
        course,
        path,
        result!.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
      ),
    );
    if (mounted && lecture != null) {
      setState(() {});
      _open(course, lecture, StudyMaterial.video);
    }
  }

  void _open(
    StudyCourse course,
    StudyLecture lecture,
    StudyMaterial material,
  ) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => StudyReader(
        app: widget.app,
        course: course,
        lecture: lecture,
        initial: material,
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_courses.first.title),
        actions: [
          TextButton(
            onPressed: _selected.isEmpty ? null : _review,
            child: const Text('复习'),
          ),
          TextButton(
            onPressed: lectures.isEmpty ? null : _organize,
            child: const Text('整理'),
          ),
          AppMenuAnchor(
            menuChildren: [
              if (_courses.any((course) => course.remote))
                AppMenuItemButton(
                  onPressed: _loading ? null : _refresh,
                  leadingIcon: const Icon(Icons.refresh_rounded),
                  child: const Text('更新课时'),
                ),
              AppMenuItemButton(
                onPressed: _selected.isEmpty ? null : _import,
                leadingIcon: const Icon(Icons.video_file_outlined),
                child: const Text('导入本地录播'),
              ),
              AppMenuItemButton(
                onPressed: lectures.isEmpty ? null : _organize,
                leadingIcon: const Icon(Icons.download_outlined),
                child: const Text('整理资料'),
              ),
            ],
            builder: (context, menu, open) => IconButton(
              tooltip: '更多选项',
              onPressed: () => open ? menu.close() : menu.open(),
              icon: const Icon(Icons.more_horiz_rounded),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (_courses.first.term.isNotEmpty)
                          Text(
                            studyTermLabel(_courses.first.term),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
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
                            builder: (context, menu, open) => AppMenuTrigger(
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
                          )
                        else if (teachers.firstOrNull?.isNotEmpty == true)
                          Text(
                            teachers.single,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        Text(
                          '${lectures.length} 课时',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_loading) const LinearProgressIndicator(minHeight: 2),
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
                                    _courses.first.remote ? '重新获取' : '导入录播',
                                  ),
                                ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: lectures.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final (course, lecture) = lectures[index];
                            return _LectureRow(
                              course: course,
                              lecture: lecture,
                              showTeacher:
                                  teachers.length > 1 && _teacher == null,
                              onOpen: (kind) => _open(course, lecture, kind),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LectureRow extends StatelessWidget {
  const _LectureRow({
    required this.course,
    required this.lecture,
    required this.showTeacher,
    required this.onOpen,
  });
  final StudyCourse course;
  final StudyLecture lecture;
  final bool showTeacher;
  final ValueChanged<StudyMaterial> onOpen;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              lectureDate(lecture),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: () => onOpen(StudyMaterial.video),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          lecture.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.play_arrow_rounded, size: 22),
                    ],
                  ),
                ),
              ),
              if (showTeacher)
                Text(
                  course.teacher,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              Wrap(
                spacing: 4,
                children: [
                  for (final (kind, label, icon) in [
                    (
                      StudyMaterial.video,
                      '录播',
                      Icons.play_circle_outline_rounded,
                    ),
                    (StudyMaterial.slides, '课件', Icons.slideshow_outlined),
                    (StudyMaterial.transcript, '字幕', Icons.subtitles_outlined),
                    (StudyMaterial.notes, '笔记', Icons.edit_note_rounded),
                  ])
                    TextButton.icon(
                      onPressed: () => onOpen(kind),
                      icon: Icon(icon, size: 17),
                      label: Text(label),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
