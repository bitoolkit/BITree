import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../core/async/cancelable_request.dart';
import '../../schedule/model.dart';
import '../../ui/app_menu_anchor.dart';
import '../../ui/app_menu_trigger.dart';
import '../model.dart';
import 'study_common.dart';
import 'study_course.dart';
import 'study_legacy_live.dart';
import 'study_reader.dart';

class StudyLiveScreen extends StatefulWidget {
  const StudyLiveScreen({super.key, required this.app});
  final AppController app;

  @override
  State<StudyLiveScreen> createState() => _StudyLiveScreenState();
}

class _StudyLiveScreenState extends State<StudyLiveScreen> {
  bool _legacy = true;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: AppMenuAnchor(
        menuChildren: [
          for (final (legacy, label) in [
            (true, '延河课堂（旧版）'),
            (false, '延河课堂（新版）'),
          ])
            AppMenuItemButton(
              onPressed: () => setState(() => _legacy = legacy),
              trailingIcon: legacy == _legacy
                  ? const Icon(Icons.check_rounded, size: 18)
                  : const SizedBox(width: 18),
              child: Text(label),
            ),
        ],
        builder: (context, menu, open) => AppMenuTrigger(
          label: _legacy ? '旧版直播' : '新版直播',
          isOpen: open,
          onPressed: () => open ? menu.close() : menu.open(),
          textStyle: Theme.of(context).appBarTheme.titleTextStyle,
        ),
      ),
    ),
    body: _legacy
        ? const LegacyLiveBrowser()
        : StudyTodayLiveList(app: widget.app),
  );
}

class StudyTodayLiveList extends StatefulWidget {
  const StudyTodayLiveList({super.key, required this.app});
  final AppController app;

  @override
  State<StudyTodayLiveList> createState() => _StudyTodayLiveListState();
}

class _StudyTodayLiveListState extends State<StudyTodayLiveList> {
  final _cancellation = CancellationToken();
  List<StudyBroadcast>? _broadcasts;
  bool _loading = false;
  bool _opening = false;
  bool _failed = false;
  DateTime _date = campusNow();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _cancellation.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading || !await studyAccount(context, widget.app) || !mounted) {
      return;
    }
    setState(() => _loading = true);
    final date = campusNow();
    final items = await studyOperation(
      context,
      '读取课堂直播',
      () => widget.app.study.repository.broadcasts(
        date,
        studyVerify(context),
        _cancellation,
      ),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = items == null;
      if (items != null) {
        _date = date;
        _broadcasts = items;
      }
    });
  }

  Future<void> _open(StudyBroadcast item) async {
    setState(() => _opening = true);
    final course = await studyOperation(
      context,
      '读取课程课时',
      () => widget.app.study.refreshCourse(
        item.course.id,
        studyVerify(context),
        _cancellation,
      ),
    );
    if (!mounted) return;
    setState(() => _opening = false);
    if (course == null) return;
    final lecture = course.lectures.firstWhere(
      (lecture) => lecture.id == item.lecture.id,
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => lecture.status.canPlay
            ? StudyReader(
                app: widget.app,
                course: course,
                lecture: lecture,
                initial: StudyMaterial.video,
              )
            : StudyCourseScreen(app: widget.app, courses: [course]),
      ),
    );
    if (mounted) unawaited(_refresh());
  }

  @override
  Widget build(BuildContext context) {
    final broadcasts = _broadcasts;
    final live =
        broadcasts
            ?.where((item) => item.lecture.status == StudyLectureStatus.live)
            .toList() ??
        [];
    final upcoming =
        broadcasts
            ?.where(
              (item) => item.lecture.status == StudyLectureStatus.upcoming,
            )
            .toList() ??
        [];
    final ended =
        broadcasts
            ?.where(
              (item) => ![
                StudyLectureStatus.live,
                StudyLectureStatus.upcoming,
              ].contains(item.lecture.status),
            )
            .toList() ??
        [];
    for (final items in [live, upcoming, ended]) {
      items.sort((a, b) => a.lecture.startsAt!.compareTo(b.lecture.startsAt!));
    }
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loading || _opening)
                const LinearProgressIndicator(minHeight: 2),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_date.month}月${_date.day}日',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: '刷新状态',
                      onPressed: _loading || _opening ? null : _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: broadcasts == null
                    ? Center(
                        child: _loading
                            ? const CircularProgressIndicator()
                            : StudyEmpty(
                                text: _failed ? '无法获取今日课堂' : '登录后查看今日课堂',
                                action: TextButton(
                                  onPressed: _refresh,
                                  child: Text(_failed ? '重试' : '登录'),
                                ),
                              ),
                      )
                    : RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          children: [
                            if (broadcasts.isEmpty)
                              const StudyEmpty(text: '今天没有课程'),
                            for (final (label, items) in [
                              ('正在直播', live),
                              ('即将开始', upcoming),
                            ])
                              if (items.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    8,
                                    12,
                                    8,
                                    8,
                                  ),
                                  child: Text(
                                    label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge,
                                  ),
                                ),
                                for (final item in items)
                                  _BroadcastRow(
                                    item: item,
                                    onTap: _opening ? null : () => _open(item),
                                  ),
                              ],
                            if (ended.isNotEmpty)
                              ExpansionTile(
                                tilePadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                shape: const Border(),
                                collapsedShape: const Border(),
                                title: Text(
                                  '已结束 ${ended.length}',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                children: [
                                  for (final item in ended)
                                    _BroadcastRow(
                                      item: item,
                                      onTap: _opening
                                          ? null
                                          : () => _open(item),
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BroadcastRow extends StatelessWidget {
  const _BroadcastRow({required this.item, required this.onTap});
  final StudyBroadcast item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final live = item.lecture.status == StudyLectureStatus.live;
    String clock(DateTime? at) {
      if (at == null) return '';
      final time = at.toUtc().add(const Duration(hours: 8));
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }

    return Material(
      color: live ? theme.colorScheme.errorContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: MediaQuery.textScalerOf(context).scale(56),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clock(item.lecture.startsAt),
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      clock(item.lecture.endsAt),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.course.title, style: theme.textTheme.titleMedium),
                    if (item.course.teacher.isNotEmpty)
                      Text(
                        item.course.teacher,
                        style: theme.textTheme.bodySmall,
                      ),
                    const SizedBox(height: 6),
                    Text(
                      live
                          ? '观看直播'
                          : item.lecture.status == StudyLectureStatus.recorded
                          ? '观看录播'
                          : item.lecture.status.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: live
                            ? theme.colorScheme.onErrorContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                item.lecture.status.canPlay
                    ? Icons.play_arrow_rounded
                    : Icons.chevron_right_rounded,
                color: live
                    ? theme.colorScheme.onErrorContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
