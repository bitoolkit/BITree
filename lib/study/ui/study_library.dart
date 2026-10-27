import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../ui/app_menu_anchor.dart';
import '../../ui/app_menu_trigger.dart';
import '../library.dart';
import '../model.dart';
import '../tasks.dart';
import 'study_common.dart';
import 'study_layout.dart';
import 'study_reader.dart';
import 'study_tasks.dart';

class StudyLibrary extends StatefulWidget {
  const StudyLibrary({
    super.key,
    required this.app,
    required this.onOpen,
    required this.actions,
    required this.footer,
    required this.today,
  });
  final AppController app;
  final ValueChanged<StudyCourseGroup> onOpen;
  final Widget actions;
  final Widget footer;
  final Widget today;
  @override
  State<StudyLibrary> createState() => _StudyLibraryState();
}

class _StudyLibraryState extends State<StudyLibrary> {
  String? _term;
  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final groups = groupStudyCourses(app.study.courses);
    final terms = groups
        .map((group) => group.remote ? group.term : 'local')
        .toSet()
        .toList();
    final term = terms.contains(_term) ? _term : terms.firstOrNull;
    final selected = groups
        .where((group) => (group.remote ? group.term : 'local') == term)
        .toList();
    final last = app.study.lastReading;
    final course = app.study.courses
        .where((course) => course.id == last?.course)
        .firstOrNull;
    final lecture = course?.lectures
        .where((lecture) => lecture.id == last?.lecture)
        .firstOrNull;
    final catalog = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          children: [
            Text('我的课程', style: Theme.of(context).textTheme.titleMedium),
            if (terms.isNotEmpty)
              AppMenuAnchor(
                menuChildren: [
                  for (final item in terms)
                    AppMenuItemButton(
                      onPressed: () => setState(() => _term = item),
                      trailingIcon: item == term
                          ? const Icon(Icons.check_rounded, size: 18)
                          : null,
                      child: Text(
                        item == 'local' ? '本地课程' : studyTermLabel(item),
                      ),
                    ),
                ],
                builder: (context, menu, open) => AppMenuTrigger(
                  label: term == 'local' ? '本地课程' : studyTermLabel(term ?? ''),
                  semanticsLabel: '课程学期',
                  isOpen: open,
                  onPressed: () => open ? menu.close() : menu.open(),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (selected.isEmpty) const StudyEmpty(text: '添加延河课堂课程，或导入本地录播。'),
        for (final group in selected)
          _CourseRow(group: group, onTap: () => widget.onOpen(group)),
        const SizedBox(height: 12),
        widget.actions,
        const Divider(height: 30),
        widget.footer,
      ],
    );
    return LayoutBuilder(
      builder: (context, size) {
        final wide = size.maxWidth >= 900;
        final main = ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            if (course != null && lecture != null) ...[
              _ResumeLecture(app: app, course: course, lecture: lecture),
              const SizedBox(height: 28),
            ],
            if (!wide) ...[widget.today, const SizedBox(height: 28)],
            catalog,
          ],
        );
        if (!wide) return main;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: main),
            const SizedBox(width: 32),
            SizedBox(
              width: 248,
              child: SingleChildScrollView(
                child: StudyAside(child: widget.today),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CourseRow extends StatelessWidget {
  const _CourseRow({required this.group, required this.onTap});
  final StudyCourseGroup group;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest =
        group.courses
            .expand((course) => course.lectures)
            .where((lecture) => lecture.startsAt != null)
            .toList()
          ..sort((a, b) => b.startsAt!.compareTo(a.startsAt!));
    final metadata = [
      if (latest.isNotEmpty)
        '${lectureDate(latest.first)} · ${studyLectureTitle(latest.first)}'
      else if (group.teachers.isNotEmpty)
        group.teachers.join('、'),
      if (group.courses.length > 1) '${group.courses.length} 个教学班',
    ].join(' · ');
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 17),
          child: Row(
            children: [
              StudyCourseMark(group.title),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.title, style: theme.textTheme.titleMedium),
                    if (metadata.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        metadata,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    if (group.lectureCount != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        '${group.lectureCount} 课时',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (MediaQuery.sizeOf(context).width >= 760)
                OutlinedButton(onPressed: onTap, child: const Text('进入课程'))
              else
                const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResumeLecture extends StatelessWidget {
  const _ResumeLecture({
    required this.app,
    required this.course,
    required this.lecture,
  });
  final AppController app;
  final StudyCourse course;
  final StudyLecture lecture;
  @override
  Widget build(BuildContext context) => FutureBuilder<LectureMaterials>(
    future: app.study.materials(course, lecture),
    builder: (context, snapshot) {
      final material = snapshot.data;
      final theme = Theme.of(context);
      void open() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => StudyReader(
            app: app,
            course: course,
            lecture: lecture,
            initial: StudyMaterial.video,
          ),
        ),
      );
      return Material(
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: LayoutBuilder(
            builder: (context, size) {
              final narrow = size.maxWidth < 440;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: narrow ? 79 : 164,
                    height: narrow ? 142 : 175,
                    child: StudyCourseCover(
                      course: course,
                      lecture: lecture,
                      material: material,
                    ),
                  ),
                  SizedBox(width: narrow ? 15 : 22),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('继续上次学习', style: theme.textTheme.bodySmall),
                        const SizedBox(height: 6),
                        Text(
                          course.title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: narrow ? 17 : 21,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${studyLectureTitle(lecture)} · ${lectureDate(lecture)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 10),
                        if (material != null &&
                            material.duration > Duration.zero) ...[
                          LinearProgressIndicator(
                            value:
                                (material.position.inMilliseconds /
                                        material.duration.inMilliseconds)
                                    .clamp(0, 1),
                            minHeight: 3,
                          ),
                          const SizedBox(height: 5),
                        ],
                        Text(
                          '${studyTimestamp(material?.position ?? Duration.zero)}${material != null && material.duration > Duration.zero ? ' / ${studyTimestamp(material.duration)}' : ''}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: open,
                          icon: const Icon(Icons.play_arrow_rounded, size: 17),
                          label: const Text('继续观看'),
                        ),
                        ListenableBuilder(
                          listenable: app.study.tasks,
                          builder: (context, _) {
                            final active = app.study.tasks.items
                                .where(
                                  (task) =>
                                      task.status == StudyTaskStatus.running ||
                                      task.status == StudyTaskStatus.queued,
                                )
                                .toList();
                            if (active.isEmpty) return const SizedBox.shrink();
                            return TextButton.icon(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => StudyTaskScreen(app: app),
                                ),
                              ),
                              icon: const Icon(Icons.layers_outlined, size: 16),
                              label: Text(
                                '${active.length} 项资料正在整理',
                                style: const TextStyle(fontSize: 12),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}
