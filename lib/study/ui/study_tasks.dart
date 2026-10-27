import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../model.dart';
import '../tasks.dart';
import 'study_common.dart';
import 'study_layout.dart';
import 'study_reader.dart';
import 'study_review.dart';

class StudyTaskScreen extends StatelessWidget {
  const StudyTaskScreen({super.key, required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: const StudyAppBar('处理任务'),
      body: SafeArea(
        child: StudyContent(
          child: ListenableBuilder(
            listenable: app.study.tasks,
            builder: (context, _) {
              final pending = app.study.tasks.items
                  .where((task) => task.status != StudyTaskStatus.completed)
                  .toList();
              final completed = app.study.tasks.items
                  .where((task) => task.status == StudyTaskStatus.completed)
                  .toList();
              final information = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('资料归属', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 12),
                  const Text('完成后的课件、字幕和录播会保存在对应课程、课时中。'),
                  const SizedBox(height: 16),
                  const Text('可以离开此页。应用保持运行时，任务会继续处理。'),
                ],
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      Tab(text: '进行中 ${pending.length}'),
                      Tab(text: '已完成 ${completed.length}'),
                    ],
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, size) {
                        final list = TabBarView(
                          children: [
                            for (final tasks in [pending, completed])
                              ListView(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 24,
                                ),
                                children: [
                                  if (tasks.isEmpty)
                                    const StudyEmpty(text: '暂无处理任务'),
                                  for (final task in tasks) ...[
                                    _TaskRow(app: app, task: task),
                                    const Divider(height: 32),
                                  ],
                                  if (size.maxWidth < 850)
                                    StudyAside(below: true, child: information),
                                ],
                              ),
                          ],
                        );
                        return size.maxWidth >= 850
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: list),
                                  const SizedBox(width: 36),
                                  SizedBox(
                                    width: 270,
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 24),
                                      child: StudyAside(child: information),
                                    ),
                                  ),
                                ],
                              )
                            : list;
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.app, required this.task});
  final AppController app;
  final StudyTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final course = app.study.courses
        .where((course) => course.id == task.course)
        .firstOrNull;
    final lecture = course?.lectures
        .where((lecture) => lecture.id == task.lecture)
        .firstOrNull;
    final active = [
      StudyTaskStatus.queued,
      StudyTaskStatus.running,
    ].contains(task.status);
    final status = switch (task.status) {
      StudyTaskStatus.queued => '等待处理',
      StudyTaskStatus.running => task.detail,
      StudyTaskStatus.paused => '已暂停',
      StudyTaskStatus.completed => '已保存到课时资料',
      StudyTaskStatus.failed => '处理失败，可重试',
      StudyTaskStatus.cancelled => '已取消',
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Icon(
            switch (task.status) {
              StudyTaskStatus.completed => Icons.check_circle_outline_rounded,
              StudyTaskStatus.failed => Icons.error_outline_rounded,
              _ => Icons.layers_outlined,
            },
            size: 20,
            color: task.status == StudyTaskStatus.failed
                ? theme.colorScheme.error
                : theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(task.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 5),
              Text(
                [course?.title, lecture?.title].whereType<String>().join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (active || task.status == StudyTaskStatus.paused)
                Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 8),
                  child: LinearProgressIndicator(
                    value: task.progress,
                    minHeight: 4,
                  ),
                ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    status,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: task.status == StudyTaskStatus.failed
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (active && task.progress != null)
                    Text(
                      '${(task.progress! * 100).round()}%',
                      style: theme.textTheme.bodySmall,
                    ),
                  if (active && task.pausable)
                    TextButton(
                      onPressed: () => app.study.tasks.pause(task),
                      child: const Text('暂停'),
                    ),
                  if ([
                    StudyTaskStatus.paused,
                    StudyTaskStatus.failed,
                    StudyTaskStatus.cancelled,
                  ].contains(task.status))
                    TextButton(
                      onPressed: () => app.study.tasks.resume(task),
                      child: Text(
                        task.status == StudyTaskStatus.paused ? '继续' : '重试',
                      ),
                    ),
                  if (active || task.status == StudyTaskStatus.paused)
                    TextButton(
                      onPressed: () => app.study.tasks.cancel(task),
                      child: const Text('取消'),
                    ),
                  if (task.status == StudyTaskStatus.completed &&
                      course != null)
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => lecture == null
                              ? StudyReviewScreen(app: app, course: course)
                              : StudyReader(
                                  app: app,
                                  course: course,
                                  lecture: lecture,
                                  initial: task.key.endsWith('/slides')
                                      ? StudyMaterial.slides
                                      : task.key.contains('/download-')
                                      ? StudyMaterial.video
                                      : task.key.endsWith('/answer')
                                      ? StudyMaterial.question
                                      : task.key.endsWith('/summary')
                                      ? StudyMaterial.notes
                                      : StudyMaterial.transcript,
                                ),
                        ),
                      ),
                      icon: const Icon(Icons.chevron_right_rounded, size: 18),
                      label: const Text('查看资料'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
