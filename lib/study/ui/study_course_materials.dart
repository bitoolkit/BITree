import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../model.dart';
import '../tasks.dart';
import 'study_common.dart';
import 'study_layout.dart';
import 'study_tasks.dart';

class StudyCourseMaterials extends StatefulWidget {
  const StudyCourseMaterials({
    super.key,
    required this.app,
    required this.entries,
    required this.onOpen,
    required this.onOrganize,
    required this.onReview,
    this.onNotes,
    this.notesOnly = false,
  });
  final AppController app;
  final List<(StudyCourse, StudyLecture)> entries;
  final void Function(
    StudyCourse,
    StudyLecture,
    StudyMaterial, {
    Duration? position,
  })
  onOpen;
  final VoidCallback? onOrganize;
  final VoidCallback? onReview;
  final VoidCallback? onNotes;
  final bool notesOnly;
  @override
  State<StudyCourseMaterials> createState() => _StudyCourseMaterialsState();
}

class _StudyCourseMaterialsState extends State<StudyCourseMaterials> {
  String? _note;
  String _key((StudyCourse, StudyLecture) entry) =>
      '${entry.$1.id}/${entry.$2.id}';

  Future<void> _export({
    (StudyCourse, StudyLecture)? selected,
  }) => studyOperation(context, '导出课程笔记', () async {
    final text = StringBuffer();
    for (final (course, lecture)
        in selected == null ? widget.entries : [selected]) {
      final material = await widget.app.study.materials(course, lecture);
      if (material.notes.isEmpty && material.summary.isEmpty) continue;
      text.writeln(
        '## ${lecture.title}${course.teacher.isEmpty ? '' : ' · ${course.teacher}'}\n\n${material.notes}\n\n${material.summary}\n',
      );
    }
    if (mounted) {
      await FilePicker.saveFile(
        dialogTitle: '导出课程笔记',
        fileName: '课程笔记.md',
        bytes: Uint8List.fromList(utf8.encode(text.toString())),
      );
    }
  });

  Widget _aside(BuildContext context) {
    if (widget.notesOnly) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('课时', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          for (final entry in widget.entries)
            TextButton(
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                backgroundColor:
                    _key(entry) ==
                        _key(
                          widget.entries
                                  .where((item) => _key(item) == _note)
                                  .firstOrNull ??
                              widget.entries.first,
                        )
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
              ),
              onPressed: () => setState(() => _note = _key(entry)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(lectureDate(entry.$2)),
                    Text(
                      studyLectureTitle(entry.$2),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          const Divider(height: 28),
          TextButton.icon(
            onPressed: widget.onReview,
            icon: const Icon(Icons.auto_stories_outlined, size: 17),
            label: const Text('整理复习提纲'),
          ),
          TextButton.icon(
            onPressed: _export,
            icon: const Icon(Icons.file_download_outlined, size: 17),
            label: const Text('导出课程笔记'),
          ),
        ],
      );
    }
    return ListenableBuilder(
      listenable: widget.app.study.tasks,
      builder: (context, _) {
        final ids = widget.entries.map((entry) => entry.$1.id).toSet();
        final active = widget.app.study.tasks.items
            .where(
              (task) =>
                  ids.contains(task.course) &&
                  [
                    StudyTaskStatus.running,
                    StudyTaskStatus.queued,
                    StudyTaskStatus.paused,
                  ].contains(task.status),
            )
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              active.isEmpty ? '课程资料' : '正在整理',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            if (active.isEmpty)
              Text(
                '${widget.entries.length} 个课时 · 按课时归档',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              for (final task in active.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: task.progress,
                        minHeight: 3,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        task.detail,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => StudyTaskScreen(app: widget.app),
                ),
              ),
              child: const Text('查看任务 ›'),
            ),
            const Divider(height: 28),
            TextButton.icon(
              onPressed: widget.onNotes,
              icon: const Icon(Icons.edit_note_rounded, size: 17),
              label: const Text('查看课程笔记'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) return const StudyEmpty(text: '暂无课时资料');
    return LayoutBuilder(
      builder: (context, size) {
        final wide = size.maxWidth >= 760;
        final aside = _aside(context);
        Widget main;
        if (widget.notesOnly) {
          final selected =
              widget.entries
                  .where((entry) => _key(entry) == _note)
                  .firstOrNull ??
              widget.entries.first;
          final (course, lecture) = selected;
          main = FutureBuilder<LectureMaterials>(
            key: ValueKey((course.id, lecture.id)),
            future: widget.app.study.materials(course, lecture),
            builder: (context, snapshot) => ListView(
              padding: const EdgeInsets.only(top: 20, bottom: 24),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            studyLectureTitle(lecture),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${lectureDate(lecture)}${course.teacher.isEmpty ? '' : ' · ${course.teacher}'}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _export(selected: selected),
                      icon: const Icon(Icons.file_download_outlined, size: 17),
                      label: const Text('导出'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (snapshot.hasError)
                  const Text('无法读取本地笔记')
                else if (!snapshot.hasData)
                  const LinearProgressIndicator(minHeight: 2)
                else if (snapshot.data!.notes.isEmpty)
                  const StudyEmpty(text: '本节还没有笔记')
                else
                  StudyNotes(
                    text: snapshot.data!.notes,
                    timeline: true,
                    onSeek: (position) => widget.onOpen(
                      course,
                      lecture,
                      StudyMaterial.video,
                      position: position,
                    ),
                  ),
                if (snapshot.data?.summary.isNotEmpty == true) ...[
                  const Divider(height: 32),
                  StudyMarkdown(
                    text: snapshot.data!.summary,
                    onSeek: (position) => widget.onOpen(
                      course,
                      lecture,
                      StudyMaterial.video,
                      position: position,
                    ),
                  ),
                ],
                const Divider(height: 32),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: () =>
                        widget.onOpen(course, lecture, StudyMaterial.notes),
                    icon: const Icon(Icons.edit_note_rounded, size: 17),
                    label: const Text('继续记笔记'),
                  ),
                ),
                if (!wide) ...[
                  const SizedBox(height: 28),
                  StudyAside(below: true, child: aside),
                ],
              ],
            ),
          );
        } else {
          main = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text('按课时归档', style: Theme.of(context).textTheme.bodySmall),
                    FilledButton.tonalIcon(
                      onPressed: widget.onOrganize,
                      icon: const Icon(Icons.layers_outlined, size: 17),
                      label: const Text('整理课程资料'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: widget.entries.length + (wide ? 0 : 1),
                  itemBuilder: (context, index) {
                    if (index == widget.entries.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 28),
                        child: StudyAside(below: true, child: aside),
                      );
                    }
                    final (course, lecture) = widget.entries[index];
                    return FutureBuilder<LectureMaterials>(
                      key: ValueKey((course.id, lecture.id)),
                      future: widget.app.study.materials(course, lecture),
                      builder: (context, snapshot) {
                        final material = snapshot.data;
                        final slides =
                            material?.slides
                                .where((slide) => !slide.hidden)
                                .toList() ??
                            [];
                        final theme = Theme.of(context);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '${lectureDate(lecture)} · ${studyLectureTitle(lecture)}',
                                style: theme.textTheme.titleSmall,
                              ),
                              if (course.teacher.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    course.teacher,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                              const SizedBox(height: 15),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: wide ? 100 : 65,
                                    height: wide ? 78 : 60,
                                    child: slides.isEmpty
                                        ? StudyCourseCover(
                                            course: course,
                                            lecture: lecture,
                                          )
                                        : Image.file(
                                            File(slides.first.file),
                                            cacheWidth: 220,
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, _, _) =>
                                                const Icon(
                                                  Icons.slideshow_outlined,
                                                ),
                                          ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      children: [
                                        _ResourceRow(
                                          title: '课件',
                                          detail: snapshot.hasError
                                              ? '无法读取本地资料'
                                              : material == null
                                              ? '正在读取'
                                              : slides.isEmpty
                                              ? '尚未提取'
                                              : '${slides.length} 页 · 已保存',
                                          onTap: () => widget.onOpen(
                                            course,
                                            lecture,
                                            StudyMaterial.slides,
                                          ),
                                        ),
                                        const Divider(height: 18),
                                        _ResourceRow(
                                          title: '课堂字幕',
                                          detail: material == null
                                              ? '正在读取'
                                              : material.transcript.isEmpty
                                              ? '尚未获取'
                                              : '${material.transcript.length} 段 · 带时间戳',
                                          onTap: () => widget.onOpen(
                                            course,
                                            lecture,
                                            StudyMaterial.transcript,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 30),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        }
        if (!wide) return main;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: main),
            const SizedBox(width: 36),
            SizedBox(
              width: widget.notesOnly ? 190 : 270,
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 20),
                child: StudyAside(child: aside),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ResourceRow extends StatelessWidget {
  const _ResourceRow({
    required this.title,
    required this.detail,
    required this.onTap,
  });
  final String title;
  final String detail;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(detail, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, size: 17),
        ],
      ),
    ),
  );
}
