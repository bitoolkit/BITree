import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../model.dart';
import 'study_live.dart';

class StudyTodayOverview extends StatelessWidget {
  const StudyTodayOverview({
    super.key,
    required this.app,
    required this.onLive,
  });
  final AppController app;
  final VoidCallback onLive;

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
              IconButton(
                tooltip: '课堂直播',
                onPressed: onLive,
                icon: const Icon(Icons.arrow_forward_rounded, size: 20),
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
              StudyClassroomTile(
                item: item,
                onTap: () => openStudyClassroom(context, app, item),
              ),
              const Divider(height: 1),
            ],
        ],
      );
    },
  );
}
