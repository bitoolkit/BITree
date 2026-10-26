import 'package:flutter/material.dart';

import '../academics/model.dart';
import '../app_controller.dart';
import '../agenda/model.dart';
import '../schedule/model.dart';
import 'external_link.dart';
import 'school_screen.dart';

class AcademicPage extends StatelessWidget {
  const AcademicPage({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
    this.loading = false,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final bool loading;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: actions,
    ),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            children: [
              SizedBox(
                height: 2,
                child: loading
                    ? const LinearProgressIndicator(minHeight: 2)
                    : null,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: children,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class AcademicImportButton extends StatelessWidget {
  const AcademicImportButton({
    super.key,
    required this.controller,
    required this.action,
    this.term,
  });
  final AppController controller;
  final SchoolAction action;
  final String? term;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: action.label,
    onPressed: controller.schoolBusy || controller.academics.busy
        ? null
        : () => openSchoolPage(context, controller, action: action, term: term),
    icon: const Icon(Icons.refresh_rounded),
  );
}

class AcademicEmpty extends StatelessWidget {
  const AcademicEmpty({
    super.key,
    required this.title,
    required this.label,
    required this.onPressed,
  });
  final String title;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Column(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        FilledButton(onPressed: onPressed, child: Text(label)),
      ],
    ),
  );
}

class AcademicSummary extends StatelessWidget {
  const AcademicSummary({super.key, required this.values});
  final List<({String label, String value})> values;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Wrap(
      spacing: 32,
      runSpacing: 16,
      children: [
        for (final item in values)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(
                item.value,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
      ],
    ),
  );
}

class GradeListTile extends StatelessWidget {
  const GradeListTile({super.key, required this.grade, required this.onTap});
  final CourseGrade grade;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(grade.name),
    subtitle: Text(
      [
        '${creditText(grade.credits)} 学分',
        grade.category,
        if (grade.failed) '未通过',
      ].where((text) => text.isNotEmpty).join('  '),
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: Text(
            grade.result,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: grade.failed ? Theme.of(context).colorScheme.error : null,
            ),
          ),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right_rounded, size: 18),
      ],
    ),
    onTap: onTap,
  );
}

class AcademicUpdatedAt extends StatelessWidget {
  const AcademicUpdatedAt({super.key, required this.updatedAt});
  final DateTime updatedAt;

  @override
  Widget build(BuildContext context) {
    final time = updatedAt.toUtc().add(const Duration(hours: 8));
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Text(
        '更新于 ${dateText(time)} ${clockText(time)}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

Future<void> showGpaRules(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    scrollable: true,
    title: const Text('绩点计算规则'),
    content: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('采用北京理工大学本科生绩点计算方法（试行）。'),
        SizedBox(height: 12),
        Text(
          '百分制：60 分及以上按 4 − 3 × (100 − 成绩)² ÷ 1600 计算，课程绩点四舍五入至一位小数；60 分以下为 0。',
        ),
        SizedBox(height: 12),
        Text('五级制：优秀 4.0，良好 3.6，中等 2.8，及格 1.7，不及格 0。'),
        SizedBox(height: 12),
        Text('按学分加权。同一课程取最高成绩；校公选课的不及格成绩不计入绩点。合格制课程只统计学分，加权平均分仅统计百分制成绩。'),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => openExternalLink(
          context,
          Uri.parse(gpaRulesUrl),
          failureTitle: '无法打开计分规则',
        ),
        child: const Text('学校原文'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  ),
);
