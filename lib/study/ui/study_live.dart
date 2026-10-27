import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../core/async/cancelable_request.dart';
import '../../core/error_message.dart';
import '../../schedule/model.dart';
import '../../ui/app_notice.dart';
import '../broadcasts.dart';
import '../model.dart';
import 'study_common.dart';
import 'study_course.dart';
import 'study_legacy_live.dart';
import 'study_reader.dart';

String studyClock(DateTime value) {
  final date = value.toUtc().add(const Duration(hours: 8));
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

bool isPersonalClassroom(AppController app, StudyClassroom item) {
  if (item.timetable != null) return true;
  String title(String value) =>
      value.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  final name = title(item.title);
  return app.study.courses.any((course) => title(course.title) == name) ||
      (app.timetable.schedule?.courses.any(
            (course) => title(course.name) == name,
          ) ??
          false);
}

Future<void> openStudyClassroom(
  BuildContext context,
  AppController app,
  StudyClassroom item,
) async {
  if (item.legacy case final legacy?) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => LegacyLiveScreen(item: legacy)),
    );
    return;
  }
  final broadcast = item.timetable!;
  final course = await studyOperation(
    context,
    '读取课程课时',
    () => app.study.refreshCourse(
      broadcast.course.id,
      studyVerify(context),
      CancellationToken(),
    ),
  );
  if (course == null || !context.mounted) return;
  final lecture = course.lectures.firstWhere(
    (lecture) => lecture.id == broadcast.lecture.id,
  );
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => lecture.status.canPlay
          ? StudyReader(
              app: app,
              course: course,
              lecture: lecture,
              initial: StudyMaterial.video,
            )
          : StudyCourseScreen(app: app, courses: [course]),
    ),
  );
}

class StudyLiveScreen extends StatefulWidget {
  const StudyLiveScreen({super.key, required this.app});
  final AppController app;
  @override
  State<StudyLiveScreen> createState() => _StudyLiveScreenState();
}

class _StudyLiveScreenState extends State<StudyLiveScreen> {
  late var _personal = widget.app.school.username != null;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('课堂直播')),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: true, label: Text('我的课堂')),
                    ButtonSegment(value: false, label: Text('校内直播')),
                  ],
                  selected: {_personal},
                  onSelectionChanged: (value) =>
                      setState(() => _personal = value.single),
                ),
              ),
              Expanded(
                child: StudyTodayLiveList(
                  app: widget.app,
                  personalOnly: _personal,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class StudyTodayLiveList extends StatefulWidget {
  const StudyTodayLiveList({
    super.key,
    required this.app,
    this.personalOnly = true,
  });
  final AppController app;
  final bool personalOnly;
  @override
  State<StudyTodayLiveList> createState() => _StudyTodayLiveListState();
}

class _StudyTodayLiveListState extends State<StudyTodayLiveList> {
  final _query = TextEditingController();
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  @override
  void didUpdateWidget(StudyTodayLiveList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.personalOnly != widget.personalOnly) {
      _query.clear();
      unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final catalog = widget.app.study.broadcasts;
    await catalog.refresh(
      campusNow(),
      studyVerify(context),
      signedIn: widget.app.school.username != null,
      keyword: widget.personalOnly ? '' : _query.text.trim(),
    );
    if (!mounted) return;
    if (catalog.failure case final failure?) {
      showAppNotice(context, errorMessage(failure));
    }
  }

  Future<void> _open(StudyClassroom item) async {
    setState(() => _opening = true);
    await openStudyClassroom(context, widget.app, item);
    if (mounted) setState(() => _opening = false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.app.study.broadcasts,
    builder: (context, _) {
      final catalog = widget.app.study.broadcasts;
      final query = _query.text.trim().toLowerCase();
      final items = catalog.items
          .where(
            (item) =>
                (!widget.personalOnly ||
                    isPersonalClassroom(widget.app, item)) &&
                (widget.personalOnly ||
                    '${item.title} ${item.location} ${item.teacher}'
                        .toLowerCase()
                        .contains(query)),
          )
          .toList();
      final ended = items
          .where(
            (item) => ![
              StudyLectureStatus.live,
              StudyLectureStatus.upcoming,
            ].contains(item.status),
          )
          .toList();
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: widget.personalOnly
                      ? Text(
                          '${campusNow().month}月${campusNow().day}日',
                          style: Theme.of(context).textTheme.titleMedium,
                        )
                      : TextField(
                          controller: _query,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _refresh(),
                          decoration: InputDecoration(
                            labelText: '课程或教室',
                            suffixIcon: IconButton(
                              tooltip: '搜索',
                              onPressed: _refresh,
                              icon: const Icon(Icons.search_rounded),
                            ),
                          ),
                        ),
                ),
                IconButton(
                  tooltip: '刷新课堂',
                  onPressed: catalog.loading ? null : _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
          if (catalog.loading || _opening)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  if (items.isEmpty && !catalog.loading)
                    StudyEmpty(
                      text: catalog.failure != null
                          ? '暂时无法获取课堂'
                          : widget.personalOnly
                          ? '今天没有找到你的课堂'
                          : '没有找到直播或预告',
                      action: TextButton(
                        onPressed: _refresh,
                        child: const Text('刷新'),
                      ),
                    ),
                  for (final (status, title) in [
                    (StudyLectureStatus.live, '正在上课'),
                    (StudyLectureStatus.upcoming, '接下来的课'),
                  ]) ...[
                    if (items.any((item) => item.status == status))
                      Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 10),
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    for (final item in items.where(
                      (item) => item.status == status,
                    ))
                      StudyClassroomTile(
                        item: item,
                        onTap: _opening ? null : () => _open(item),
                      ),
                  ],
                  if (ended.isNotEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      shape: const Border(),
                      collapsedShape: const Border(),
                      title: Text(
                        '已结束 ${ended.length}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      children: [
                        for (final item in ended)
                          StudyClassroomTile(
                            item: item,
                            onTap: _opening ? null : () => _open(item),
                          ),
                      ],
                    ),
                  if (!widget.personalOnly && catalog.more)
                    TextButton(
                      onPressed: catalog.loading
                          ? null
                          : () => studyOperation(
                              context,
                              '读取更多课堂',
                              catalog.loadMore,
                            ),
                      child: const Text('加载更多'),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

class StudyClassroomTile extends StatelessWidget {
  const StudyClassroomTile({
    super.key,
    required this.item,
    required this.onTap,
  });
  final StudyClassroom item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final live = item.status == StudyLectureStatus.live;
    final action = TextButton.icon(
      onPressed: onTap,
      icon: Icon(
        live
            ? Icons.play_arrow_rounded
            : item.status == StudyLectureStatus.recorded
            ? Icons.replay_rounded
            : Icons.chevron_right_rounded,
        size: 18,
      ),
      label: Text(
        live
            ? '进入直播'
            : item.status == StudyLectureStatus.recorded
            ? '看录播'
            : '查看课程',
      ),
      style: live
          ? TextButton.styleFrom(foregroundColor: theme.colorScheme.error)
          : null,
    );
    return LayoutBuilder(
      builder: (context, size) {
        final narrow =
            size.maxWidth < 480 ||
            MediaQuery.textScalerOf(context).scale(14) > 19;
        return InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 64,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        studyClock(item.startsAt),
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        studyClock(item.endsAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        [
                          item.location,
                          item.teacher,
                          item.status.label,
                        ].where((text) => text.isNotEmpty).join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: live
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (narrow) action,
                    ],
                  ),
                ),
                if (!narrow) action,
              ],
            ),
          ),
        );
      },
    );
  }
}
