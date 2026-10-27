import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../core/async/cancelable_request.dart';
import '../../ui/app_menu_anchor.dart';
import '../model.dart';
import 'study_common.dart';
import 'study_organize.dart';
import 'study_reader.dart';
import 'study_review.dart';

class StudyCourseScreen extends StatefulWidget {
  const StudyCourseScreen({super.key, required this.app, required this.course});
  final AppController app;
  final StudyCourse course;
  @override
  State<StudyCourseScreen> createState() => _StudyCourseScreenState();
}

class _StudyCourseScreenState extends State<StudyCourseScreen> {
  late StudyCourse _course = widget.course;
  final _cancel = CancellationToken();
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    if (_course.remote && _course.lectures.isEmpty) {
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
    final course = await studyOperation(
      context,
      '读取课程课时',
      () => widget.app.study.refreshCourse(
        _course.id,
        studyVerify(context),
        _cancel,
      ),
    );
    if (mounted) {
      setState(() {
        if (course != null) _course = course;
        _loading = false;
      });
    }
  }

  Future<void> _import() async {
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
        _course,
        path,
        result!.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
      ),
    );
    if (mounted && lecture != null) {
      setState(() {});
      _open(lecture, StudyMaterial.video);
    }
  }

  void _open(StudyLecture lecture, StudyMaterial material) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => StudyReader(
            app: widget.app,
            course: _course,
            lecture: lecture,
            initial: material,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_course.title),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  StudyReviewScreen(app: widget.app, course: _course),
            ),
          ),
          child: const Text('复习'),
        ),
        TextButton(
          onPressed: _course.lectures.isEmpty
              ? null
              : () => showStudyOrganize(context, widget.app, _course),
          child: const Text('整理'),
        ),
        AppMenuAnchor(
          menuChildren: [
            if (_course.remote)
              AppMenuItemButton(
                onPressed: _loading ? null : _refresh,
                leadingIcon: const Icon(Icons.refresh_rounded),
                child: const Text('更新课时'),
              ),
            AppMenuItemButton(
              onPressed: _import,
              leadingIcon: const Icon(Icons.video_file_outlined),
              child: const Text('导入本地录播'),
            ),
            AppMenuItemButton(
              onPressed: _course.lectures.isEmpty
                  ? null
                  : () => showStudyOrganize(context, widget.app, _course),
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
              if (_loading) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: _course.lectures.isEmpty
                    ? StudyEmpty(
                        text: _loading ? '正在读取课时' : '暂无课时',
                        action: _loading
                            ? null
                            : OutlinedButton(
                                onPressed: _course.remote ? _refresh : _import,
                                child: Text(_course.remote ? '重新获取' : '导入录播'),
                              ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: _course.lectures.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final lecture = _course.lectures[index];
                          return Padding(
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
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      InkWell(
                                        onTap: () =>
                                            _open(lecture, StudyMaterial.video),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  lecture.title,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              const Icon(
                                                Icons.play_arrow_rounded,
                                                size: 22,
                                              ),
                                            ],
                                          ),
                                        ),
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
                                            (
                                              StudyMaterial.notes,
                                              '笔记',
                                              Icons.edit_note_rounded,
                                            ),
                                          ])
                                            TextButton.icon(
                                              onPressed: () =>
                                                  _open(lecture, kind),
                                              icon: Icon(icon, size: 17),
                                              label: Text(label),
                                              style: TextButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                    ),
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
