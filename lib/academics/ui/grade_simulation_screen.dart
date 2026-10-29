import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../school/ui/school_screen.dart';
import '../model.dart';
import 'academic_common.dart';
import 'projected_course_dialog.dart';

class GradeSimulationScreen extends StatefulWidget {
  const GradeSimulationScreen({
    super.key,
    required this.controller,
    this.retake,
  });
  final AppController controller;
  final CourseGrade? retake;

  @override
  State<GradeSimulationScreen> createState() => _GradeSimulationScreenState();
}

class _GradeSimulationScreenState extends State<GradeSimulationScreen> {
  final _courses = <ProjectedCourse>[];
  final _target = TextEditingController(text: '3.60');
  bool _targetMode = false;
  bool _replaceRetakes = true;

  @override
  void initState() {
    super.initState();
    if (widget.retake case final grade?) {
      _courses.add(
        ProjectedCourse(
          id: 'simulation-retake',
          name: grade.name,
          credits: grade.credits,
          score: 85,
          replaces: grade.courseKey,
        ),
      );
    }
  }

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  Future<void> _edit([ProjectedCourse? course]) async {
    final next = await showDialog<ProjectedCourse>(
      context: context,
      builder: (_) => ProjectedCourseDialog(
        grades: widget.controller.academics.record.grades,
        courses: widget.controller.timetable.schedule?.courses ?? const [],
        course: course,
      ),
    );
    if (next == null || !mounted) return;
    setState(() {
      final index = _courses.indexWhere((item) => item.id == next.id);
      if (index < 0) {
        _courses.add(next);
      } else {
        _courses[index] = next;
      }
    });
  }

  Future<void> _remove(ProjectedCourse course) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除试算课程？'),
        content: Text(course.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) setState(() => _courses.remove(course));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.controller.academics,
      widget.controller.timetable,
      widget.controller.school,
    ]),
    builder: (context, _) {
      final grades = widget.controller.academics.record.grades;
      final original = AcademicStats(grades);
      final result = projectGrades(
        grades,
        _courses,
        replaceRetakes: _replaceRetakes,
      );
      final target = double.tryParse(_target.text);
      final validTarget =
          target != null && target.isFinite && target >= 0 && target <= 4;
      final needed = validTarget
          ? scoreForTarget(
              grades,
              _courses,
              target: target,
              replaceRetakes: _replaceRetakes,
            )
          : null;
      final theme = Theme.of(context);
      return AcademicPage(
        title: '成绩试算',
        loading: widget.controller.school.busy,
        actions: [
          IconButton(
            tooltip: '计分规则',
            onPressed: () => showGpaRules(context),
            icon: const Icon(Icons.help_outline_rounded),
          ),
          AcademicImportButton(
            controller: widget.controller,
            action: SchoolAction.importGrades,
          ),
        ],
        children: [
          Text(
            '当前计绩学分 ${creditText(original.gpaCredits)}，平均绩点 ${original.gpa?.toStringAsFixed(2) ?? '—'}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('按课程试算')),
              ButtonSegment(value: true, label: Text('目标倒推')),
            ],
            selected: {_targetMode},
            showSelectedIcon: false,
            onSelectionChanged: (value) =>
                setState(() => _targetMode = value.first),
          ),
          if (_targetMode) ...[
            const SizedBox(height: 20),
            TextField(
              controller: _target,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: '目标累计绩点',
                errorText: validTarget ? null : '请输入 0～4 之间的绩点',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _targetMode ? '每门试算课程至少需要达到' : '预计累计绩点',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  _courses.isEmpty
                      ? '先添加试算课程'
                      : _targetMode
                      ? !validTarget
                            ? '—'
                            : needed == null
                            ? '满分也无法达到目标'
                            : '$needed 分'
                      : result.gpa?.toStringAsFixed(2) ?? '—',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!_targetMode &&
                    result.gpa != null &&
                    original.gpa != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '累计绩点变化 ${(result.gpa! - original.gpa!) >= 0 ? '+' : ''}${(result.gpa! - original.gpa!).toStringAsFixed(2)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          Row(
            children: [
              const Expanded(child: Text('试算课程')),
              TextButton.icon(
                onPressed: _edit,
                icon: const Icon(Icons.add_rounded),
                label: const Text('添加课程'),
              ),
            ],
          ),
          for (final course in _courses)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(course.name),
              subtitle: Text(
                '${creditText(course.credits)} 学分${course.replaces == null ? '' : '  重修'}',
              ),
              onTap: () => _edit(course),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => _edit(course),
                    child: Text(
                      _targetMode ? '修改' : '${creditText(course.score)} 分',
                    ),
                  ),
                  IconButton(
                    tooltip: '移除试算课程',
                    onPressed: () => _remove(course),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('重修取最高成绩'),
            value: _replaceRetakes,
            onChanged: (value) => setState(() => _replaceRetakes = value!),
          ),
          Text(
            _replaceRetakes ? '试算不会修改已同步成绩。' : '本次试算同时计入原成绩和重修成绩，不采用学校的最高成绩规则。',
            style: theme.textTheme.bodySmall,
          ),
        ],
      );
    },
  );
}
