import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../ui/app_menu_anchor.dart';
import '../../ui/app_page.dart';
import '../library.dart';
import '../model.dart';
import 'study_common.dart';
import 'study_course.dart';
import 'study_library.dart';
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
          builder: (_) => StudyCourseScreen(
            app: controller,
            courses:
                groupStudyCourses(controller.study.courses)
                    .where(
                      (group) =>
                          group.courses.any((item) => item.id == course.id),
                    )
                    .firstOrNull
                    ?.courses ??
                [course],
          ),
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
                    child: StudyLibrary(
                      app: controller,
                      onOpen: (group) => _open(context, group.courses.first),
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
