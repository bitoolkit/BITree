import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../sync/controller.dart';
import '../../sync/ui/sync.dart';
import '../../sync/ui/sync_text.dart';
import '../../ui/app_dropdown_field.dart';
import '../model.dart';
import 'academic_common.dart';
import 'credit_progress_screen.dart';
import 'grade_detail.dart';

class GradesScreen extends StatefulWidget {
  const GradesScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends State<GradesScreen> {
  String? _term;
  bool _byTerm = false;
  bool _onlyFailed = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.controller.academics,
      widget.controller.school,
    ]),
    builder: (context, _) {
      final controller = widget.controller;
      final record = controller.academics.record;
      final terms = record.grades.map((grade) => grade.term).toSet().toList()
        ..sort((a, b) => b.compareTo(a));
      final term = terms.contains(_term) ? _term : null;
      final grades =
          record.grades
              .where((grade) => term == null || grade.term == term)
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));
      final stats = AcademicStats(grades);
      return AcademicPage(
        title: '成绩与学业',
        loading: controller.school.busy,
        actions: [
          IconButton(
            tooltip: '计分规则',
            onPressed: () => showGpaRules(context),
            icon: const Icon(Icons.help_outline_rounded),
          ),
          AcademicImportButton(
            controller: controller,
            action: SyncTarget.grades,
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
          else if (record.gradesUpdatedAt == null)
            AcademicEmpty(
              title: '还没有同步成绩',
              label: SyncTarget.grades.actionLabel,
              onPressed: () =>
                  startSync(context, controller, targets: {SyncTarget.grades}),
            )
          else ...[
            AppDropdownField<String?>(
              label: '学期',
              value: term,
              entries: [
                const DropdownMenuEntry(value: null, label: '全部学期'),
                for (final value in terms)
                  DropdownMenuEntry(value: value, label: value),
              ],
              onChanged: (value) => setState(() {
                _term = value;
                _onlyFailed = false;
              }),
            ),
            AcademicSummary(
              values: [
                (label: '平均绩点', value: stats.gpa?.toStringAsFixed(2) ?? '—'),
                (
                  label: '加权平均分',
                  value: stats.averageScore?.toStringAsFixed(1) ?? '—',
                ),
                (label: '获得学分', value: creditText(stats.earnedCredits)),
              ],
            ),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('课程成绩')),
                ButtonSegment(value: true, label: Text('学期表现')),
              ],
              selected: {_byTerm},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  setState(() => _byTerm = value.first),
            ),
            const SizedBox(height: 12),
            if (_byTerm)
              for (final value in terms.where(
                (value) => term == null || value == term,
              ))
                _TermPerformance(
                  term: value,
                  stats: AcademicStats(
                    record.grades.where((grade) => grade.term == value),
                  ),
                )
            else ...[
              if (stats.failed.isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.error_outline_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    _onlyFailed
                        ? '只显示未通过课程'
                        : term == null
                        ? '${stats.failed.length} 门课程尚未通过'
                        : '这个学期有 ${stats.failed.length} 门课程未通过',
                  ),
                  trailing: Text(_onlyFailed ? '显示全部' : '查看'),
                  onTap: () => setState(() => _onlyFailed = !_onlyFailed),
                ),
              for (final grade in _onlyFailed ? stats.failed : grades)
                GradeListTile(
                  grade: grade,
                  onTap: () => showGradeDetails(context, controller, grade),
                ),
              if (grades.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('这个学期暂无成绩'),
                ),
            ],
            const Divider(height: 32),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('毕业学分进度'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => CreditProgressScreen(controller: controller),
                ),
              ),
            ),
            if (record.gradesUpdatedAt case final updatedAt?)
              AcademicUpdatedAt(updatedAt: updatedAt),
          ],
        ],
      );
    },
  );
}

class _TermPerformance extends StatelessWidget {
  const _TermPerformance({required this.term, required this.stats});
  final String term;
  final AcademicStats stats;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(term)),
            Text(stats.gpa?.toStringAsFixed(2) ?? '—'),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: (stats.gpa ?? 0) / 4,
          minHeight: 5,
          borderRadius: BorderRadius.circular(3),
        ),
        const SizedBox(height: 8),
        Text(
          '加权平均 ${stats.averageScore?.toStringAsFixed(1) ?? '—'} 分',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}
