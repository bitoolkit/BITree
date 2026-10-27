import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../ui/app_notice.dart';
import '../model.dart';
import 'study_common.dart';

Future<void> showStudyOrganize(
  BuildContext context,
  AppController app,
  StudyCourse course, {
  StudyLecture? lecture,
}) async {
  var count = lecture == null ? 3 : 1;
  final remote = course.remote && !(lecture?.id.startsWith('local-') ?? false);
  final selected = <String>{if (remote) 'transcript', 'slides'};
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: const Text('整理资料'),
        scrollable: true,
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(lecture?.title ?? course.title),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(lecture == null ? '最新1节' : '当前课时'),
                    selected: count == 1,
                    onSelected: (_) => update(() => count = 1),
                  ),
                  ChoiceChip(
                    label: const Text('最近3节'),
                    selected: count == 3,
                    onSelected: (_) => update(() => count = 3),
                  ),
                  ChoiceChip(
                    label: const Text('全部课时'),
                    selected: count == -1,
                    onSelected: (_) => update(() => count = -1),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final (key, label) in [
                if (remote) ('transcript', '平台字幕'),
                ('slides', '提取课件'),
                if (remote) ('screen', '课件录播'),
                if (remote) ('classroom', '教室录播'),
              ])
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(label),
                  value: selected.contains(key),
                  onChanged: (value) => update(() {
                    if (value == true) {
                      selected.add(key);
                    } else {
                      selected.remove(key);
                    }
                  }),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: selected.isEmpty
                ? null
                : () => Navigator.pop(context, true),
            child: const Text('开始整理'),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final lectures = count == 1
      ? [lecture ?? course.lectures.first]
      : count == -1
      ? course.lectures
      : course.lectures.take(3);
  for (final item in lectures) {
    if (selected.contains('transcript') && !item.id.startsWith('local-')) {
      app.study.fetchTranscript(course, item, studyVerify(context));
    }
    if (selected.contains('slides')) {
      app.study.extractSlides(course, item, studyVerify(context));
    }
    for (final kind in ['screen', 'classroom']) {
      if (selected.contains(kind) && !item.id.startsWith('local-')) {
        app.study.download(course, item, studyVerify(context), kind);
      }
    }
  }
  showAppNotice(context, '已加入处理任务');
}
