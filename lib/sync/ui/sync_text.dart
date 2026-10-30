import '../../mooc/progress.dart';
import '../controller.dart';

extension SyncTargetText on SyncTarget {
  String get title => switch (this) {
    SyncTarget.schedule => '课表',
    SyncTarget.exams => '考试安排',
    SyncTarget.grades => '成绩',
    SyncTarget.studyPlan => '学分进度',
    SyncTarget.lexue => '乐学 DDL',
    SyncTarget.eclass => '新延河课堂 DDL',
    SyncTarget.mooc => '中国大学MOOC DDL',
    SyncTarget.physicsLab => '大物实验 DDL',
  };

  String get actionLabel => switch (this) {
    SyncTarget.schedule => '同步课表',
    SyncTarget.exams => '同步考试安排',
    SyncTarget.grades => '同步成绩',
    SyncTarget.studyPlan => '同步学分进度',
    SyncTarget.lexue => '同步乐学 DDL',
    SyncTarget.eclass => '同步新延河课堂 DDL',
    SyncTarget.mooc => '同步中国大学MOOC DDL',
    SyncTarget.physicsLab => '更新大物实验 DDL',
  };
}

String syncProgressText(SyncController controller, SyncTarget target) {
  if (controller.results[target] case final result?) {
    return _syncResultText(result, target);
  }
  if (controller.isRunning(target)) {
    if (controller.cancelled) return '正在取消…';
    if (target == SyncTarget.mooc) {
      final progress = switch (controller.moocProgress) {
        MoocCourseListProgress(:final isSpoc) =>
          isSpoc ? '正在读取 SPOC 课程…' : '正在读取 MOOC 课程…',
        MoocCourseReadProgress(:final index, :final total, :final course) =>
          '正在读取 $index/$total：《$course》',
        null => null,
      };
      if (progress != null) return progress;
    }
    return '正在同步…';
  }
  return target.isSchool && controller.waitingForSchool ? '等待学校请求完成' : '等待同步';
}

String _syncResultText(SyncResult result, SyncTarget target) {
  final detail = result.detail?.trim();
  return switch (result.outcome) {
    SyncOutcome.synced => switch (result.count) {
      null => '已同步',
      final count => '已同步 $count 条 DDL',
    },
    SyncOutcome.failed => [
      if (result.count case final count? when count > 0) '已同步 $count 条 DDL',
      if (detail != null && detail.isNotEmpty) detail else '同步未完成，请重试',
    ].join('\n'),
    SyncOutcome.needsLogin =>
      target == SyncTarget.mooc ? '需要登录中国大学MOOC账号' : '需要登录学校账号',
    SyncOutcome.needsVerification => '需要完成学校登录验证',
    SyncOutcome.cancelled => '已取消',
    SyncOutcome.noSchedule => '暂无可用课表',
    SyncOutcome.saveFailed => '未能保存大物实验 DDL',
  };
}
