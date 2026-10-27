import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../ui/app_notice.dart';

/// Manually generates deadlines from every week of the selected local timetable.
Future<void> updatePhysicsLabDeadlines(
  BuildContext context,
  AppController controller,
) async {
  bool canUpdate() {
    if (!controller.timetable.ready || !controller.agenda.ready) {
      showAppNotice(context, '课表或日程尚未加载，请稍后重试。');
      return false;
    }
    if (controller.timetable.busy || controller.agenda.busy) {
      showAppNotice(context, '课表或日程正在保存，请稍后重试。');
      return false;
    }
    if (controller.timetable.schedule == null) {
      showAppNotice(context, '请先选择或导入本地课表。');
      return false;
    }
    return true;
  }

  if (!canUpdate()) return;
  final schedule = controller.timetable.schedule!;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('更新大物实验 DDL'),
      scrollable: true,
      content: Text(
        '将根据当前选中的 ${schedule.termLabel} 本地课表，'
        '生成全部周次的大物实验 DDL，不限于当前查看的周。\n\n'
        '仅匹配地点同时包含“物理”和“实验”的课程。预习报告在上课开始时截止，'
        '实验报告在下一周同一天前夜的 23:59 截止。\n\n'
        '将保留手动修改及完成、删除状态，仅清理本学期已失效、'
        '未编辑、未完成且未删除的自动生成项。\n\n'
        '此操作离线完成，无需学校登录；仅在手动操作时更新，不会后台自动更新。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('更新'),
        ),
      ],
    ),
  );
  if (!context.mounted || confirmed != true) return;
  if (!canUpdate()) return;
  if (!identical(controller.timetable.schedule, schedule)) {
    showAppNotice(context, '当前选中的课表已变更，请重新确认后更新。');
    return;
  }

  final count = await controller.agenda.updatePhysicsLabDeadlines(schedule);
  if (!context.mounted || count == null) return;
  showAppNotice(
    context,
    count == 0
        ? '${schedule.termLabel} 更新完成：无匹配课程，已按规则清理过期自动生成项。'
        : '${schedule.termLabel} 全部周次更新完成，匹配 $count 条大物实验 DDL。',
  );
}
