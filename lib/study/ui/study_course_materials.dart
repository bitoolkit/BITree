import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../model.dart';
import 'study_common.dart';

class StudyCourseMaterials extends StatelessWidget {
  const StudyCourseMaterials({
    super.key,
    required this.app,
    required this.entries,
    required this.onOpen,
    required this.onOrganize,
    required this.onReview,
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
  final bool notesOnly;

  Future<void> _export(
    BuildContext context,
  ) => studyOperation(context, '导出课程笔记', () async {
    final text = StringBuffer();
    for (final (course, lecture) in entries) {
      final material = await app.study.materials(course, lecture);
      if (material.notes.isEmpty && material.summary.isEmpty) continue;
      text.writeln(
        '## ${lecture.title}${course.teacher.isEmpty ? '' : ' · ${course.teacher}'}\n\n${material.notes}\n\n${material.summary}\n',
      );
    }
    if (context.mounted) {
      await FilePicker.saveFile(
        dialogTitle: '导出课程笔记',
        fileName: '课程笔记.md',
        bytes: Uint8List.fromList(utf8.encode(text.toString())),
      );
    }
  });

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (notesOnly) ...[
                FilledButton.tonalIcon(
                  onPressed: onReview,
                  icon: const Icon(Icons.auto_stories_outlined, size: 18),
                  label: const Text('复习提纲'),
                ),
                TextButton.icon(
                  onPressed: entries.isEmpty ? null : () => _export(context),
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: const Text('导出课程笔记'),
                ),
              ] else ...[
                FilledButton.tonalIcon(
                  onPressed: onOrganize,
                  icon: const Icon(Icons.layers_outlined, size: 18),
                  label: const Text('整理课程资料'),
                ),
                Text('按课时归档', style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
      Expanded(
        child: entries.isEmpty
            ? const StudyEmpty(text: '暂无课时资料')
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final (course, lecture) = entries[index];
                  return FutureBuilder<LectureMaterials>(
                    future: app.study.materials(course, lecture),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return ListTile(
                          title: Text(lecture.title),
                          subtitle: const Text('无法读取本地资料'),
                          onTap: () => onOpen(
                            course,
                            lecture,
                            notesOnly
                                ? StudyMaterial.notes
                                : StudyMaterial.slides,
                          ),
                        );
                      }
                      final material = snapshot.data;
                      final slides =
                          material?.slides
                              .where((slide) => !slide.hidden)
                              .toList() ??
                          [];
                      final theme = Theme.of(context);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
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
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                            if (notesOnly) ...[
                              if (material == null)
                                const LinearProgressIndicator(minHeight: 2)
                              else if (material.notes.isNotEmpty)
                                StudyMarkdown(
                                  text: material.notes,
                                  onSeek: (position) => onOpen(
                                    course,
                                    lecture,
                                    StudyMaterial.video,
                                    position: position,
                                  ),
                                )
                              else
                                Text(
                                  '本节还没有笔记',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () => onOpen(
                                    course,
                                    lecture,
                                    StudyMaterial.notes,
                                  ),
                                  icon: const Icon(
                                    Icons.edit_note_rounded,
                                    size: 17,
                                  ),
                                  label: const Text('记笔记'),
                                ),
                              ),
                            ] else
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 74,
                                    height: 68,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: theme
                                            .colorScheme
                                            .surfaceContainerLow,
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: slides.isEmpty
                                          ? Icon(
                                              Icons.slideshow_outlined,
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            )
                                          : Image.file(
                                              File(slides.first.file),
                                              fit: BoxFit.contain,
                                              errorBuilder: (_, _, _) =>
                                                  const Icon(
                                                    Icons.slideshow_outlined,
                                                  ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _ResourceRow(
                                          title: '课件',
                                          detail: material == null
                                              ? '正在读取'
                                              : slides.isEmpty
                                              ? '尚未提取'
                                              : '${slides.length} 页 · 已保存',
                                          onTap: () => onOpen(
                                            course,
                                            lecture,
                                            StudyMaterial.slides,
                                          ),
                                        ),
                                        const Divider(height: 14),
                                        _ResourceRow(
                                          title: '课堂字幕',
                                          detail: material == null
                                              ? '正在读取'
                                              : material.transcript.isEmpty
                                              ? '尚未获取'
                                              : '${material.transcript.length} 段 · 带时间戳',
                                          onTap: () => onOpen(
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
                            const Divider(height: 28),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyMedium),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, size: 18),
        ],
      ),
    ),
  );
}
