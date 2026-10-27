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
  final count = await controller.agenda.updatePhysicsLabDeadlines(schedule);
  if (!context.mounted || count == null) return;
  showAppNotice(context, '已更新大物实验 DDL');
}
