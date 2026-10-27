import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../schedule/model.dart';
import '../model.dart';
import 'study_common.dart';
import 'study_live.dart';

class StudyTodayOverview extends StatelessWidget {
  const StudyTodayOverview({
    super.key,
    required this.app,
    required this.onLive,
    this.onTimetable,
  });
  final AppController app;
  final VoidCallback onLive;
  final VoidCallback? onTimetable;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app.study.broadcasts,
    builder: (context, _) {
      final theme = Theme.of(context);
      final items = app.study.broadcasts.items
          .where(
            (item) =>
                isPersonalClassroom(app, item) &&
                [
                  StudyLectureStatus.live,
                  StudyLectureStatus.upcoming,
                ].contains(item.status),
          )
          .take(2)
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('今日课堂', style: theme.textTheme.titleMedium)),
              Text(
                '${campusNow().month}月${campusNow().day}日',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          if (app.study.broadcasts.loading)
            const LinearProgressIndicator(minHeight: 2),
          if (items.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              app.school.username == null ? '登录后查看课表中的课堂。' : '暂无待播课程',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ] else
            for (final item in items) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.status == StudyLectureStatus.live
                          ? '● 正在上课'
                          : '下一节 · ${studyClock(item.startsAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: item.status == StudyLectureStatus.live
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(item.title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      '${studyClock(item.startsAt)}–${studyClock(item.endsAt)}${item.location.isEmpty ? '' : ' · ${item.location}'}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    item.status == StudyLectureStatus.live
                        ? OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: theme.colorScheme.error,
                              side: BorderSide(
                                color: theme.colorScheme.error.withValues(
                                  alpha: .3,
                                ),
                              ),
                              backgroundColor: theme.colorScheme.errorContainer
                                  .withValues(alpha: .18),
                            ),
                            onPressed: () =>
                                openStudyClassroom(context, app, item),
                            icon: const Icon(Icons.live_tv_rounded, size: 17),
                            label: const Text('观看直播'),
                          )
                        : TextButton(
                            onPressed: () =>
                                openStudyClassroom(context, app, item),
                            child: const Text('课程资料 ›'),
                          ),
                  ],
                ),
              ),
              const Divider(height: 1),
            ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (onTimetable != null)
                TextButton.icon(
                  onPressed: onTimetable,
                  icon: const Icon(Icons.calendar_month_outlined, size: 16),
                  label: const Text('查看课表'),
                ),
              TextButton(onPressed: onLive, child: const Text('课堂直播 ↗')),
            ],
          ),
        ],
      );
    },
  );
}
