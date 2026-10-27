import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../ui/app_menu_anchor.dart';
import '../../ui/app_menu_trigger.dart';
import '../../ui/app_notice.dart';
import '../model.dart';
import '../tasks.dart';
import 'study_common.dart';
import 'study_reader.dart';
import 'study_services.dart';

class StudyReviewScreen extends StatefulWidget {
  const StudyReviewScreen({super.key, required this.app, required this.course});
  final AppController app;
  final StudyCourse course;
  @override
  State<StudyReviewScreen> createState() => _StudyReviewScreenState();
}

class _StudyReviewScreenState extends State<StudyReviewScreen> {
  bool _loading = false;
  late int _count = switch (widget.course.reviewLectureIds.length) {
    1 => 1,
    0 => 3,
    3 => 3,
    _ => -1,
  };
  List<StudyLecture> get _selected {
    final lectures =
        widget.course.lectures
            .where((lecture) => lecture.status != StudyLectureStatus.upcoming)
            .toList()
          ..sort(
            (a, b) => (b.startsAt ?? DateTime(0)).compareTo(
              a.startsAt ?? DateTime(0),
            ),
          );
    return _count < 0 ? lectures : lectures.take(_count).toList();
  }

  Future<void> _generate() async {
    setState(() => _loading = true);
    try {
      await studyOperation(context, '整理复习资料', () async {
        final selected = _selected;
        final materials = await Future.wait(
          selected.map(
            (lecture) => widget.app.study.materials(widget.course, lecture),
          ),
        );
        if (!mounted) return;
        if (!materials.any(
          (item) => item.transcript.isNotEmpty || item.notes.isNotEmpty,
        )) {
          showAppNotice(context, '请先获取字幕或填写笔记');
          return;
        }
        var settings = await widget.app.study.model.readSettings();
        if (settings == null && mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute<bool>(
              builder: (_) => StudyServices(model: widget.app.study.model),
            ),
          );
          settings = await widget.app.study.model.readSettings();
        }
        if (settings != null && mounted) {
          widget.app.study.generate(
            widget.course,
            null,
            settings,
            reviewLectures: selected,
          );
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(StudyLecture lecture, Duration position) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => StudyReader(
            app: widget.app,
            course: widget.course,
            lecture: lecture,
            initial: StudyMaterial.video,
            initialPosition: position,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('复习提纲')),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListenableBuilder(
            listenable: widget.app.study.tasks,
            builder: (context, _) {
              final task = widget.app.study.generation(
                widget.course,
                null,
                'review',
              );
              final active =
                  task != null &&
                  [
                    StudyTaskStatus.running,
                    StudyTaskStatus.queued,
                  ].contains(task.status);
              final text = task?.output.isNotEmpty == true
                  ? task!.output
                  : widget.course.review;
              final theme = Theme.of(context);
              final sourceLectures = active || text.isEmpty
                  ? _selected
                  : widget.course.lectures
                        .where(
                          (lecture) =>
                              widget.course.reviewLectureIds.isEmpty ||
                              widget.course.reviewLectureIds.contains(
                                lecture.id,
                              ),
                        )
                        .toList();
              final sources = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('来源课时', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 12),
                  for (final lecture in sourceLectures)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextButton(
                        onPressed: () => _open(lecture, Duration.zero),
                        child: Text(
                          '${lectureDate(lecture)} · ${studyLectureTitle(lecture)}',
                        ),
                      ),
                    ),
                  const Divider(height: 24),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            StudyServices(model: widget.app.study.model),
                      ),
                    ),
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('学习服务'),
                  ),
                ],
              );
              final document = Theme(
                data: theme.copyWith(
                  textTheme: theme.textTheme.copyWith(
                    bodyMedium: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.8,
                    ),
                  ),
                ),
                child: StudyMarkdown(
                  text: text,
                  onLecture: (id, position) {
                    final lecture = widget.course.lectures
                        .where((lecture) => lecture.id == id)
                        .firstOrNull;
                    if (lecture != null) _open(lecture, position);
                  },
                ),
              );
              return LayoutBuilder(
                builder: (context, size) => ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      widget.course.title,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('资料范围', style: theme.textTheme.bodySmall),
                        AppMenuAnchor(
                          menuChildren: [
                            for (final (count, label) in [
                              (1, '最新1节'),
                              (3, '最近3节'),
                              (-1, '全部课时'),
                            ])
                              AppMenuItemButton(
                                onPressed: active
                                    ? null
                                    : () => setState(() => _count = count),
                                trailingIcon: count == _count
                                    ? const Icon(Icons.check_rounded, size: 18)
                                    : null,
                                child: Text(label),
                              ),
                          ],
                          builder: (context, menu, open) => AppMenuTrigger(
                            label: _count == 1
                                ? '最新1节'
                                : _count == 3
                                ? '最近3节'
                                : '全部课时',
                            isOpen: open,
                            onPressed: () => open ? menu.close() : menu.open(),
                          ),
                        ),
                        active
                            ? TextButton.icon(
                                onPressed: () =>
                                    widget.app.study.tasks.cancel(task),
                                icon: const Icon(Icons.stop_rounded),
                                label: const Text('停止生成'),
                              )
                            : FilledButton.tonal(
                                onPressed: _loading || _selected.isEmpty
                                    ? null
                                    : _generate,
                                child: Text(text.isEmpty ? '生成复习提纲' : '重新整理'),
                              ),
                        TextButton.icon(
                          onPressed: text.isEmpty
                              ? null
                              : () => studyOperation(
                                  context,
                                  '导出复习提纲',
                                  () => FilePicker.saveFile(
                                    dialogTitle: '导出复习提纲',
                                    fileName: '${widget.course.title}-复习提纲.md',
                                    bytes: Uint8List.fromList(
                                      utf8.encode(text),
                                    ),
                                  ),
                                ),
                          icon: const Icon(
                            Icons.file_download_outlined,
                            size: 18,
                          ),
                          label: const Text('导出'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (active && text.isEmpty)
                      const LinearProgressIndicator(minHeight: 2),
                    if (text.isEmpty && !active)
                      const StudyEmpty(text: '选择课时，用已有字幕和笔记整理复习提纲。')
                    else if (size.maxWidth >= 850)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 190, child: sources),
                          const SizedBox(width: 32),
                          Expanded(child: document),
                        ],
                      )
                    else ...[
                      document,
                      const Divider(height: 32),
                      sources,
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}
