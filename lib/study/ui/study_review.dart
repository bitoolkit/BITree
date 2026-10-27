import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../app/controller.dart';
import '../../ui/app_menu_anchor.dart';
import '../../ui/app_menu_trigger.dart';
import '../../ui/app_notice.dart';
import '../model.dart';
import '../tasks.dart';
import 'study_common.dart';
import 'study_layout.dart';
import 'study_reader.dart';
import 'study_services.dart';

class _ReviewHeadingBuilder extends MarkdownElementBuilder {
  _ReviewHeadingBuilder(this.keys);
  final List<GlobalKey> keys;
  int _index = 0;
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => Text(
    element.textContent,
    key: keys[(_index++) % keys.length],
    style: preferredStyle,
  );
}

class StudyReviewScreen extends StatefulWidget {
  const StudyReviewScreen({super.key, required this.app, required this.course});
  final AppController app;
  final StudyCourse course;
  @override
  State<StudyReviewScreen> createState() => _StudyReviewScreenState();
}

class _StudyReviewScreenState extends State<StudyReviewScreen> {
  bool _loading = false;
  final _headingKeys = <GlobalKey>[];
  int _heading = 0;
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
    appBar: StudyAppBar('复习提纲', subtitle: widget.course.title),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: StudyContent(
          maxWidth: 1280,
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
              final headings = <String>[];
              void visit(md.Node node) {
                if (node is! md.Element) return;
                if (RegExp(r'^h[1-6]$').hasMatch(node.tag)) {
                  headings.add(node.textContent);
                }
                for (final child in node.children ?? <md.Node>[]) {
                  visit(child);
                }
              }

              for (final node in md.Document().parseLines(text.split('\n'))) {
                visit(node);
              }
              while (_headingKeys.length < headings.length) {
                _headingKeys.add(GlobalKey());
              }
              final headingBuilder = _ReviewHeadingBuilder(
                _headingKeys.take(headings.length).toList(),
              );
              final sources = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (headings.isNotEmpty) ...[
                    Text('目录', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 12),
                    for (final (index, title) in headings.indexed)
                      TextButton(
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          backgroundColor: index == _heading
                              ? theme.colorScheme.primaryContainer
                              : null,
                        ),
                        onPressed: () {
                          setState(() => _heading = index);
                          final target = _headingKeys[index].currentContext;
                          if (target != null) {
                            Scrollable.ensureVisible(
                              target,
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 220),
                              alignment: .1,
                            );
                          }
                        },
                        child: Text(title),
                      ),
                    const Divider(height: 32),
                  ],
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
                  builders: {
                    for (var level = 1; level <= 6; level++)
                      'h$level': headingBuilder,
                  },
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
                  children: [
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
                          Expanded(child: StudyAside(child: document)),
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
