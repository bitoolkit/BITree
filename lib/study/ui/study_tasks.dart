import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../model.dart';
import '../tasks.dart';
import 'study_common.dart';
import 'study_reader.dart';
import 'study_review.dart';

class StudyTaskScreen extends StatelessWidget {
  const StudyTaskScreen({super.key, required this.app});
  final AppController app;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('处理任务')),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: ListenableBuilder(
          listenable: app.study.tasks,
          builder: (context, _) {
            final tasks = app.study.tasks.items;
            if (tasks.isEmpty) return const StudyEmpty(text: '暂无处理任务');
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: tasks.length,
              separatorBuilder: (_, _) => const Divider(height: 32),
              itemBuilder: (context, index) {
                final task = tasks[index];
                final course = app.study.courses
                    .where((item) => item.id == task.course)
                    .firstOrNull;
                final lecture = course?.lectures
                    .where((item) => item.id == task.lecture)
                    .firstOrNull;
                final active = [
                  StudyTaskStatus.queued,
                  StudyTaskStatus.running,
                ].contains(task.status);
                final status = switch (task.status) {
                  StudyTaskStatus.queued => '等待处理',
                  StudyTaskStatus.running => task.detail,
                  StudyTaskStatus.paused => '已暂停',
                  StudyTaskStatus.completed => '已完成',
                  StudyTaskStatus.failed => '处理失败',
                  StudyTaskStatus.cancelled => '已取消',
                };
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      task.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(lecture?.title ?? course?.title ?? ''),
                    const SizedBox(height: 12),
                    if (active)
                      LinearProgressIndicator(
                        value: task.progress,
                        minHeight: 3,
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          status,
                          style: Theme.of(context).textTheme.bodySmall,
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
                              task.status == StudyTaskStatus.paused
                                  ? '继续'
                                  : '重试',
                            ),
                          ),
                        if (active || task.status == StudyTaskStatus.paused)
                          TextButton(
                            onPressed: () => app.study.tasks.cancel(task),
                            child: const Text('取消'),
                          ),
                        if (task.status == StudyTaskStatus.completed &&
                            course != null)
                          TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => lecture == null
                                    ? StudyReviewScreen(
                                        app: app,
                                        course: course,
                                      )
                                    : StudyReader(
                                        app: app,
                                        course: course,
                                        lecture: lecture,
                                        initial: task.key.endsWith('/slides')
                                            ? StudyMaterial.slides
                                            : task.key.contains('/download-')
                                            ? StudyMaterial.video
                                            : task.key.endsWith('/summary') ||
                                                  task.key.endsWith('/answer')
                                            ? StudyMaterial.notes
                                            : StudyMaterial.transcript,
                                      ),
                              ),
                            ),
                            child: const Text('查看资料'),
                          ),
                      ],
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    ),
  );
}
