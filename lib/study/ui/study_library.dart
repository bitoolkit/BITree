import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../library.dart';
import '../model.dart';
import '../tasks.dart';
import 'study_reader.dart';
import 'study_tasks.dart';

class StudyLibrary extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final groups = groupStudyCourses(app.study.courses);
    final terms = <(bool, String), List<StudyCourseGroup>>{};
    for (final group in groups) {
      terms.putIfAbsent((group.remote, group.term), () => []).add(group);
    }
    final last = app.study.lastReading;
    final course = app.study.courses
        .where((course) => course.id == last?.course)
        .firstOrNull;
    final lecture = course?.lectures
        .where((lecture) => lecture.id == last?.lecture)
        .firstOrNull;

    final activity = [
      if (course != null && lecture != null)
        _ResumeLecture(app: app, course: course, lecture: lecture),
      _ActiveTasks(app: app),
    ];
    final sections = <Widget>[
      actions,
      if (terms.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text('添加延河课堂课程，或导入本地录播。'),
        ),
      for (final (index, section) in terms.entries.indexed)
        ExpansionTile(
          key: PageStorageKey('study-term-${section.key}'),
          initiallyExpanded: index == 0 || !section.key.$1,
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 8),
          childrenPadding: const EdgeInsets.only(bottom: 16),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  section.key.$1 ? studyTermLabel(section.key.$2) : '本地课程',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${section.value.length} 门',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          children: [
            for (final (index, group) in section.value.indexed) ...[
              if (index > 0)
                const Divider(height: 1, indent: 12, endIndent: 12),
              _CourseRow(group: group, onTap: () => onOpen(group)),
            ],
          ],
        ),
    ];

    return LayoutBuilder(
      builder: (context, size) {
        if (size.maxWidth >= 960) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ListView(
                    key: const PageStorageKey('study-library'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(top: 8, bottom: 24),
                    children: [
                      ...activity,
                      ...sections,
                      const SizedBox(height: 16),
                      footer,
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                SizedBox(
                  width: 270,
                  child: ListView(
                    primary: false,
                    padding: const EdgeInsets.only(top: 16, bottom: 24),
                    children: [today],
                  ),
                ),
              ],
            ),
          );
        }
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: ListView(
              key: const PageStorageKey('study-library'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                ...activity,
                today,
                const SizedBox(height: 24),
                ...sections,
                const SizedBox(height: 16),
                footer,
              ],
            ),
          ),
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
    final teachers = group.teachers;
    final count = group.lectureCount;
    final subtitle = [
      if (teachers.isNotEmpty) teachers.join('、'),
      if (group.courses.length > 1) '${group.courses.length} 个教学班',
    ].join('  ');

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.title, style: theme.textTheme.titleMedium),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 12),
              Text(
                '$count 课时',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
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
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: theme.colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: open,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, size) {
                  final details = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '上次学到 ${studyTimestamp(snapshot.data?.position ?? Duration.zero)}',
                        style: theme.textTheme.labelMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(course.title, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(
                        lecture.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      if (snapshot.data case final material?
                          when material.duration > Duration.zero) ...[
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value:
                              (material.position.inMilliseconds /
                                      material.duration.inMilliseconds)
                                  .clamp(0, 1),
                          minHeight: 3,
                        ),
                      ],
                    ],
                  );
                  final button = FilledButton.icon(
                    onPressed: open,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('继续观看'),
                  );
                  if (size.maxWidth < 500) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        details,
                        const SizedBox(height: 16),
                        Align(alignment: Alignment.centerLeft, child: button),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: details),
                      const SizedBox(width: 20),
                      button,
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ActiveTasks extends StatelessWidget {
  const _ActiveTasks({required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
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
      final task = active.first;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          children: [
            ListTile(
              dense: true,
              minVerticalPadding: 4,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: const Icon(Icons.downloading_outlined, size: 20),
              title: Text(
                task.title,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              subtitle: task.detail.isEmpty
                  ? null
                  : Text(
                      task.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
              trailing: Text(
                '${active.length} 项',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => StudyTaskScreen(app: app),
                ),
              ),
            ),
            LinearProgressIndicator(value: task.progress, minHeight: 2),
          ],
        ),
      );
    },
  );
}
