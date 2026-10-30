import 'package:flutter/material.dart';

import '../../agenda/model.dart';
import '../../agenda/ui/agenda_detail.dart';
import '../../agenda/ui/calendar_list.dart';
import '../../app/controller.dart';
import '../../schedule/model.dart';
import '../../sync/controller.dart';
import '../../sync/ui/sync.dart';
import '../../sync/ui/sync_text.dart';
import '../../ui/app_dropdown_field.dart';
import '../exam_conflicts.dart';
import 'academic_common.dart';

class ExamsScreen extends StatefulWidget {
  const ExamsScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<ExamsScreen> createState() => _ExamsScreenState();
}

class _ExamsScreenState extends State<ExamsScreen> {
  late String? _term = widget.controller.timetable.schedule?.term;
  bool _includeClasses = true;
  bool _showPast = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.controller.agenda,
      widget.controller.timetable,
      widget.controller.school,
    ]),
    builder: (context, _) {
      final controller = widget.controller;
      final now = campusNow();
      final allExams = controller.agenda.entries
          .where((entry) => entry.kind == AgendaKind.exam)
          .toList();
      final terms = {
        if (controller.timetable.schedule != null)
          controller.timetable.schedule!.term,
        for (final exam in allExams)
          if (exam.term != null) exam.term!,
      }.toList()..sort((a, b) => b.compareTo(a));
      final term = terms.contains(_term) ? _term : null;
      final selected = allExams
          .where((entry) => term == null || entry.term == term)
          .toList();
      final exams =
          selected
              .where((entry) => _showPast || !entry.isFinished(now))
              .toList()
            ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
      final conflicts = findExamConflicts(
        exams,
        controller.timetable.schedules,
        includeClasses: _includeClasses,
      );
      final days = <DateTime, List<AgendaEntry>>{};
      for (final exam in exams) {
        days.putIfAbsent(calendarDate(exam.startsAt), () => []).add(exam);
      }
      final theme = Theme.of(context);
      return AcademicPage(
        title: '考试安排与冲突检查',
        loading: controller.school.busy,
        actions: [
          AcademicImportButton(
            controller: controller,
            action: SyncTarget.exams,
            term: term,
          ),
        ],
        children: [
          if (terms.isNotEmpty)
            AppDropdownField<String?>(
              label: '学期',
              value: term,
              entries: [
                const DropdownMenuEntry(value: null, label: '全部学期'),
                for (final value in terms)
                  DropdownMenuEntry(value: value, label: value),
              ],
              onChanged: (value) => setState(() => _term = value),
            ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('同时检查本地课表'),
            value: _includeClasses,
            onChanged: (value) => setState(() => _includeClasses = value!),
          ),
          if (_includeClasses && controller.timetable.schedules.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '同步课表后，可检查考试与课程的时间冲突。',
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (conflicts.isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.warning_amber_rounded,
                color: theme.colorScheme.error,
              ),
              title: Text('发现 ${conflicts.length} 处时间冲突'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => _ExamConflictsScreen(
                    controller: controller,
                    term: term,
                    includeClasses: _includeClasses,
                    showPast: _showPast,
                  ),
                ),
              ),
            ),
          for (final day in days.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 8),
              child: Text(
                agendaDateLabel(day.key),
                style: theme.textTheme.bodySmall,
              ),
            ),
            for (final exam in day.value)
              _ExamTile(
                controller: controller,
                exam: exam,
                conflicts: conflicts
                    .where(
                      (conflict) =>
                          conflict.exam.entry?.id == exam.id ||
                          conflict.other.entry?.id == exam.id,
                    )
                    .toList(),
              ),
          ],
          if (exams.isEmpty)
            AcademicEmpty(
              title: !_showPast && selected.isNotEmpty ? '没有即将到来的考试' : '暂无考试安排',
              label: SyncTarget.exams.actionLabel,
              onPressed: () => startSync(
                context,
                controller,
                targets: {SyncTarget.exams},
                term: term,
              ),
            ),
          if (selected.any((exam) => exam.isFinished(now)))
            TextButton(
              onPressed: () => setState(() => _showPast = !_showPast),
              child: Text(_showPast ? '隐藏已结束考试' : '查看已结束考试'),
            ),
          const SizedBox(height: 16),
          Text('考试与日程共用记录，同步、编辑和删除会在两处同时生效。', style: theme.textTheme.bodySmall),
        ],
      );
    },
  );
}

class _ExamTile extends StatelessWidget {
  const _ExamTile({
    required this.controller,
    required this.exam,
    required this.conflicts,
  });
  final AppController controller;
  final AgendaEntry exam;
  final List<ExamConflict> conflicts;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(exam.title),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          [
            exam.timeLabel,
            exam.location,
          ].where((value) => value.isNotEmpty).join('  '),
        ),
        for (final conflict in conflicts)
          Text(
            conflict.other.course != null
                ? '与${conflict.other.title}上课时间重叠'
                : '与${conflict.exam.entry?.id == exam.id ? conflict.other.title : conflict.exam.title}考试时间重叠',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: () => showAgendaEntry(context, controller, exam),
  );
}

class _ExamConflictsScreen extends StatelessWidget {
  const _ExamConflictsScreen({
    required this.controller,
    required this.term,
    required this.includeClasses,
    required this.showPast,
  });
  final AppController controller;
  final String? term;
  final bool includeClasses;
  final bool showPast;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      controller.agenda,
      controller.timetable,
      controller.school,
    ]),
    builder: (context, _) {
      final now = campusNow();
      final conflicts = findExamConflicts(
        controller.agenda.entries.where(
          (entry) =>
              entry.kind == AgendaKind.exam &&
              (term == null || entry.term == term) &&
              (showPast || !entry.isFinished(now)),
        ),
        controller.timetable.schedules,
        includeClasses: includeClasses,
      );
      return AcademicPage(
        title: '时间冲突',
        children: [
          if (conflicts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Text('没有时间冲突'),
            ),
          for (final conflict in conflicts) ...[
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 4),
              child: Text(
                '${agendaDateLabel(conflict.exam.startsAt)}  重叠 ${conflict.minutes} 分钟',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            for (final item in [conflict.exam, conflict.other])
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.title),
                subtitle: Text(
                  [
                    item.timeLabel,
                    item.location,
                  ].where((value) => value.isNotEmpty).join('  '),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => openCalendarItem(context, controller, item),
              ),
            const Divider(height: 24),
          ],
        ],
      );
    },
  );
}
