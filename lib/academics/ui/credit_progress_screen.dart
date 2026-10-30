import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../sync/controller.dart';
import '../../sync/ui/sync.dart';
import '../model.dart';
import 'academic_common.dart';
import 'credit_targets_dialog.dart';
import 'grade_detail.dart';

class CreditProgressScreen extends StatelessWidget {
  const CreditProgressScreen({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller.academics, controller.school]),
    builder: (context, _) {
      final record = controller.academics.record;
      final plan = record.plan;
      final stats = record.stats;
      final earned =
          plan?.completedCredits ??
          (record.gradesUpdatedAt == null ? null : stats.earnedCredits);
      final target = record.targetCredits ?? plan?.requiredCredits;
      final categories = {
        ...record.categoryTargets.keys,
        for (final grade in stats.courses) record.categoryOf(grade),
      }.toList()..sort();
      final theme = Theme.of(context);
      return AcademicPage(
        title: '毕业学分进度',
        loading: controller.school.busy || controller.academics.busy,
        actions: [
          IconButton(
            tooltip: '核对学分目标',
            onPressed:
                controller.school.username == null || controller.academics.busy
                ? null
                : () => showDialog<void>(
                    context: context,
                    builder: (_) =>
                        CreditTargetsDialog(controller: controller.academics),
                  ),
            icon: const Icon(Icons.tune_rounded),
          ),
          AcademicImportButton(
            controller: controller,
            action: SyncTarget.studyPlan,
          ),
        ],
        children: [
          if (!controller.academics.ready)
            AcademicEmpty(
              title: '学业数据暂时无法读取',
              label: '重新读取',
              onPressed: () =>
                  controller.academics.load(controller.school.username),
            )
          else if (plan == null && record.gradesUpdatedAt == null)
            AcademicEmpty(
              title: '还没有学分记录',
              label: SyncTarget.studyPlan.label,
              onPressed: () => startSync(
                context,
                controller,
                targets: {SyncTarget.studyPlan},
              ),
            )
          else ...[
            if (plan != null)
              Text(
                [
                  plan.year,
                  plan.major,
                ].where((text) => text.isNotEmpty).join('  '),
                style: theme.textTheme.titleMedium,
              ),
            AcademicSummary(
              values: [
                (
                  label: plan?.completedCredits == null
                      ? '成绩中已获学分'
                      : '学校记录已修学分',
                  value: earned == null ? '未获取' : creditText(earned),
                ),
                (
                  label: record.targetCredits == null ? '学校要求学分' : '核对目标学分',
                  value: target == null ? '未获取' : creditText(target),
                ),
                (
                  label: '尚缺学分',
                  value: target == null || earned == null
                      ? '—'
                      : creditText(math.max(0.0, target - earned)),
                ),
              ],
            ),
            if (target != null && target > 0 && earned != null)
              LinearProgressIndicator(
                value: (earned / target).clamp(0, 1).toDouble(),
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
            const SizedBox(height: 20),
            if (stats.failed
                    .where((grade) => grade.attribute.contains('必修'))
                    .toList()
                case final failed when failed.isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.error_outline_rounded,
                  color: theme.colorScheme.error,
                ),
                title: Text('${failed.length} 门必修课待通过'),
                subtitle: Text(failed.map((grade) => grade.name).join('、')),
                onTap: () => _showCategory(context, '待通过的必修课', failed),
                trailing: const Icon(Icons.chevron_right_rounded),
              ),
            Row(
              children: [
                const Expanded(child: Text('按课程类别核对')),
                TextButton(
                  onPressed:
                      controller.school.username == null ||
                          controller.academics.busy
                      ? null
                      : () => showDialog<void>(
                          context: context,
                          builder: (_) => CreditTargetsDialog(
                            controller: controller.academics,
                          ),
                        ),
                  child: const Text('设置目标'),
                ),
              ],
            ),
            for (final category in categories)
              _CreditCategoryRow(
                name: category,
                grades: stats.courses
                    .where((grade) => record.categoryOf(grade) == category)
                    .toList(),
                target: record.categoryTargets[category],
                onTap: (grades) => _showCategory(context, category, grades),
              ),
            if (record.gradesUpdatedAt == null)
              TextButton.icon(
                onPressed: () => startSync(
                  context,
                  controller,
                  targets: {SyncTarget.grades},
                ),
                icon: const Icon(Icons.download_rounded),
                label: const Text('同步成绩，查看分类学分'),
              ),
            const SizedBox(height: 20),
            Text(
              '分类学分按已同步成绩汇总，同一课程只计一次。分类要求需按你的培养方案核对；不估算在修学分。毕业认定以学校审核为准。',
              style: theme.textTheme.bodySmall,
            ),
            if (record.planUpdatedAt ?? record.gradesUpdatedAt
                case final updatedAt?)
              AcademicUpdatedAt(updatedAt: updatedAt),
          ],
        ],
      );
    },
  );

  void _showCategory(
    BuildContext context,
    String category,
    List<CourseGrade> grades,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => AcademicPage(
          title: category,
          children: [
            if (grades.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('这个类别还没有课程成绩'),
              ),
            for (final grade in grades)
              GradeListTile(
                grade: grade,
                onTap: () => showGradeDetails(context, controller, grade),
              ),
          ],
        ),
      ),
    );
  }
}

class _CreditCategoryRow extends StatelessWidget {
  const _CreditCategoryRow({
    required this.name,
    required this.grades,
    required this.target,
    required this.onTap,
  });
  final String name;
  final List<CourseGrade> grades;
  final double? target;
  final ValueChanged<List<CourseGrade>> onTap;

  @override
  Widget build(BuildContext context) {
    final earned = AcademicStats(grades).earnedCredits;
    return InkWell(
      onTap: () => onTap(grades),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(name)),
                Text(
                  '${creditText(earned)}${target == null ? ' 学分' : ' / ${creditText(target!)}'}',
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
            if (target != null && target! > 0) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (earned / target!).clamp(0, 1).toDouble(),
                minHeight: 4,
                borderRadius: BorderRadius.circular(3),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              target == null
                  ? '尚未设置分类要求'
                  : '还需 ${creditText(math.max(0.0, target! - earned))} 学分',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
