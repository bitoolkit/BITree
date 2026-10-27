import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../ui/app_menu_anchor.dart';
import '../../ui/app_page.dart';
import '../model.dart';
import 'study_common.dart';
import 'study_course.dart';
import 'study_reader.dart';
import 'study_search.dart';
import 'study_services.dart';
import 'study_tasks.dart';

class StudyScreen extends StatelessWidget {
  const StudyScreen({super.key, required this.controller});
  final AppController controller;

  Future<void> _refresh(BuildContext context) async {
    if (!await studyAccount(context, controller) || !context.mounted) return;
    await studyOperation(
      context,
      '读取延河课堂',
      () => controller.study.refresh(studyVerify(context)),
    );
  }

  void _open(BuildContext context, StudyCourse course) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => StudyCourseScreen(app: controller, course: course),
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller.study,
    builder: (context, _) => AppPage(
      title: const Text('学习'),
      actions: [
        IconButton(
          tooltip: '搜索课程',
          icon: const Icon(Icons.search_rounded),
          onPressed: () async {
            final course = await Navigator.of(context).push<StudyCourse>(
              MaterialPageRoute(
                builder: (_) => StudySearchScreen(app: controller),
              ),
            );
            if (course != null && context.mounted) _open(context, course);
          },
        ),
        AppMenuAnchor(
          menuChildren: [
            AppMenuItemButton(
              leadingIcon: const Icon(Icons.refresh_rounded),
              onPressed: controller.study.loading
                  ? null
                  : () => _refresh(context),
              child: const Text('更新课程'),
            ),
            AppMenuItemButton(
              leadingIcon: const Icon(Icons.add_rounded),
              onPressed: () async {
                final course = await _createLocalCourse(context, controller);
                if (course != null && context.mounted) _open(context, course);
              },
              child: const Text('添加本地课程'),
            ),
            AppMenuItemButton(
              leadingIcon: const Icon(Icons.downloading_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => StudyTaskScreen(app: controller),
                ),
              ),
              child: const Text('处理任务'),
            ),
            AppMenuItemButton(
              leadingIcon: const Icon(Icons.tune_rounded),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => StudyServices(model: controller.study.model),
                ),
              ),
              child: const Text('学习服务'),
            ),
          ],
          builder: (context, menu, open) => ListenableBuilder(
            listenable: controller.study.tasks,
            builder: (context, _) => IconButton(
              tooltip: '更多选项',
              onPressed: () => open ? menu.close() : menu.open(),
              icon: Badge(
                isLabelVisible: controller.study.tasks.activeCount > 0,
                child: const Icon(Icons.more_horiz_rounded),
              ),
            ),
          ),
        ),
      ],
      child: Column(
        children: [
          if (controller.study.loading)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: controller.study.courses.isEmpty
                ? Center(
                    child: StudyEmpty(
                      text: '添加延河课堂课程，或导入本地录播。',
                      action: Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          FilledButton(
                            onPressed: controller.study.loading
                                ? null
                                : () => _refresh(context),
                            child: const Text('获取我的课程'),
                          ),
                          OutlinedButton(
                            onPressed: () async {
                              final course = await _createLocalCourse(
                                context,
                                controller,
                              );
                              if (course != null && context.mounted) {
                                _open(context, course);
                              }
                            },
                            child: const Text('添加本地课程'),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => _refresh(context),
                    child: LayoutBuilder(
                      builder: (context, size) {
                        final columns = size.maxWidth >= 720 ? 2 : 1;
                        final courses = controller.study.courses;
                        final last = controller.study.lastReading;
                        final resumeCourse = courses
                            .where((item) => item.id == last?.course)
                            .firstOrNull;
                        final resumeLecture = resumeCourse?.lectures
                            .where((item) => item.id == last?.lecture)
                            .firstOrNull;
                        return Column(
                          children: [
                            if (resumeCourse != null && resumeLecture != null)
                              FutureBuilder<LectureMaterials>(
                                future: controller.study.materials(
                                  resumeCourse,
                                  resumeLecture,
                                ),
                                builder: (context, snapshot) => ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 8,
                                  ),
                                  leading: const Icon(
                                    Icons.play_circle_outline_rounded,
                                  ),
                                  title: Text(
                                    resumeLecture.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    '继续观看  ${studyTimestamp(snapshot.data?.position ?? Duration.zero)}',
                                  ),
                                  trailing: const Icon(
                                    Icons.chevron_right_rounded,
                                  ),
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => StudyReader(
                                        app: controller,
                                        course: resumeCourse,
                                        lecture: resumeLecture,
                                        initial: StudyMaterial.video,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            Expanded(
                              child: GridView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  24,
                                ),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      mainAxisExtent:
                                          100 +
                                          (MediaQuery.textScalerOf(context)
                                                      .scale(16) -
                                                  16) *
                                              3,
                                      crossAxisSpacing: 24,
                                      mainAxisSpacing: 8,
                                    ),
                                itemCount: courses.length,
                                itemBuilder: (context, index) {
                                  final course = courses[index];
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    leading: Icon(
                                      Icons.menu_book_outlined,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    ),
                                    title: Text(
                                      course.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      [course.term, course.teacher]
                                          .where((item) => item.isNotEmpty)
                                          .join('  '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: const Icon(
                                      Icons.chevron_right_rounded,
                                    ),
                                    onTap: () => _open(context, course),
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}

Future<StudyCourse?> _createLocalCourse(
  BuildContext context,
  AppController app,
) async {
  var input = '';
  final title = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('添加本地课程'),
      content: TextFormField(
        onChanged: (value) => input = value,
        autofocus: true,
        decoration: const InputDecoration(labelText: '课程名称'),
        onFieldSubmitted: (value) {
          if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (input.trim().isNotEmpty) {
              Navigator.pop(context, input.trim());
            }
          },
          child: const Text('添加'),
        ),
      ],
    ),
  );
  if (title == null || !context.mounted) return null;
  return studyOperation(context, '添加课程', () => app.study.addLocalCourse(title));
}
