import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../schedule/model.dart';
import '../library.dart';
import '../model.dart';
import 'study_common.dart';
import 'study_course.dart';
import 'study_layout.dart';
import 'study_library.dart';
import 'study_live.dart';
import 'study_search.dart';
import 'study_services.dart';
import 'study_tasks.dart';
import 'study_today.dart';

class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key, required this.controller, this.onTimetable});
  final AppController controller;
  final VoidCallback? onTimetable;
  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  AppController get app => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && app.school.username != null) {
        unawaited(_refreshClassrooms());
      }
    });
  }

  Future<void> _refreshClassrooms() => app.study.broadcasts.refresh(
    campusNow(),
    studyVerify(context),
    signedIn: app.school.username != null,
  );

  Future<void> _refresh() async {
    if (!await studyAccount(context, app) || !mounted) return;
    await studyOperation(
      context,
      '读取延河课堂',
      () => app.study.refresh(studyVerify(context)),
    );
    if (mounted) await _refreshClassrooms();
  }

  void _open(StudyCourse course) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => StudyCourseScreen(
        app: app,
        courses:
            groupStudyCourses(app.study.courses)
                .where(
                  (group) => group.courses.any((item) => item.id == course.id),
                )
                .firstOrNull
                ?.courses ??
            [course],
      ),
    ),
  );

  Future<void> _search() async {
    final course = await Navigator.of(context).push<StudyCourse>(
      MaterialPageRoute(
        builder: (_) => StudySearchScreen(
          app: app,
          onLocal: () {
            Navigator.of(context).pop();
            unawaited(_createLocal());
          },
        ),
      ),
    );
    if (course != null && mounted) _open(course);
  }

  Future<void> _createLocal() async {
    var input = '';
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加本地课程'),
        content: TextField(
          onChanged: (value) => input = value,
          autofocus: true,
          decoration: const InputDecoration(labelText: '课程名称'),
          onSubmitted: (value) {
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
              if (input.trim().isNotEmpty) Navigator.pop(context, input.trim());
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (title == null || !mounted) return;
    final course = await studyOperation(
      context,
      '添加课程',
      () => app.study.addLocalCourse(title),
    );
    if (course != null && mounted) _open(course);
  }

  void _live() => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => StudyLiveScreen(app: app)));

  Widget _actions() => Wrap(
    spacing: 12,
    runSpacing: 4,
    children: [
      TextButton.icon(
        onPressed: app.study.loading ? null : _refresh,
        icon: const Icon(Icons.sync_rounded, size: 18),
        label: Text(app.study.courses.isEmpty ? '获取我的课程' : '同步课程'),
      ),
      TextButton.icon(
        onPressed: _search,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('添加课程'),
      ),
      TextButton.icon(
        onPressed: _createLocal,
        icon: const Icon(Icons.folder_open_outlined, size: 18),
        label: const Text('本地资料'),
      ),
    ],
  );

  Widget _footer() => Wrap(
    spacing: 12,
    runSpacing: 4,
    children: [
      TextButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => StudyTaskScreen(app: app)),
        ),
        icon: const Icon(Icons.checklist_rounded, size: 18),
        label: const Text('处理任务'),
      ),
      TextButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => StudyServices(model: app.study.model),
          ),
        ),
        icon: const Icon(Icons.tune_rounded, size: 18),
        label: const Text('学习服务'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app.study,
    builder: (context, _) => SafeArea(
      bottom: false,
      child: StudyContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StudyHeading(
              '学习',
              subtitle:
                  app.study.courses
                          .where((course) => course.remote)
                          .firstOrNull
                          ?.term ==
                      null
                  ? null
                  : studyTermLabel(
                      app.study.courses
                          .firstWhere((course) => course.remote)
                          .term,
                    ),
            ),
            const SizedBox(height: 24),
            if (app.study.loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: StudyLibrary(
                  app: app,
                  onOpen: (group) => _open(group.courses.first),
                  actions: _actions(),
                  footer: _footer(),
                  today: StudyTodayOverview(
                    app: app,
                    onLive: _live,
                    onTimetable: widget.onTimetable,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
