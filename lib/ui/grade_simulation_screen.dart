import 'package:flutter/material.dart';

import '../academics/model.dart';
import '../app_controller.dart';
import 'academic_common.dart';
import 'app_dropdown_field.dart';
import 'school_screen.dart';

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
      builder: (_) =>
          _ProjectedCourseDialog(controller: widget.controller, course: course),
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
    listenable: widget.controller,
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
        loading: widget.controller.schoolBusy,
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
            _replaceRetakes ? '试算不会修改已导入成绩。' : '本次试算同时计入原成绩和重修成绩，不采用学校的最高成绩规则。',
            style: theme.textTheme.bodySmall,
          ),
        ],
      );
    },
  );
}

class _ProjectedCourseDialog extends StatefulWidget {
  const _ProjectedCourseDialog({required this.controller, this.course});
  final AppController controller;
  final ProjectedCourse? course;

  @override
  State<_ProjectedCourseDialog> createState() => _ProjectedCourseDialogState();
}

class _ProjectedCourseDialogState extends State<_ProjectedCourseDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.course?.name);
  late final _credits = TextEditingController(
    text: widget.course == null ? '' : creditText(widget.course!.credits),
  );
  late final _score = TextEditingController(
    text: creditText(widget.course?.score ?? 85),
  );
  late String? _selection = widget.course?.replaces;

  @override
  void dispose() {
    _name.dispose();
    _credits.dispose();
    _score.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final choices =
        <String, ({String name, double? credits, String? replaces})>{
          for (final grade in highestGrades(
            widget.controller.academics.record.grades,
          ))
            grade.courseKey: (
              name: grade.name,
              credits: grade.credits,
              replaces: grade.courseKey,
            ),
        };
    for (final course in widget.controller.schedule?.courses ?? []) {
      final key = course.number.isEmpty ? course.name : course.number;
      choices.putIfAbsent(
        key,
        () => (name: course.name, credits: null, replaces: null),
      );
    }
    return AlertDialog(
      constraints: const BoxConstraints(maxWidth: 520),
      scrollable: true,
      title: Text(widget.course == null ? '添加试算课程' : '修改试算课程'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (choices.isNotEmpty) ...[
              AppDropdownField<String?>(
                label: '选择课程（选填）',
                value: choices.containsKey(_selection) ? _selection : null,
                entries: [
                  const DropdownMenuEntry(value: null, label: '手动填写'),
                  for (final choice in choices.entries)
                    DropdownMenuEntry(
                      value: choice.key,
                      label:
                          '${choice.value.name}${choice.value.replaces == null ? '' : '（重修）'}',
                    ),
                ],
                onChanged: (key) {
                  setState(() {
                    final choice = choices[key];
                    _selection = key;
                    if (choice != null) {
                      _name.text = choice.name;
                      _credits.text = choice.credits == null
                          ? ''
                          : creditText(choice.credits!);
                    }
                  });
                },
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: '课程名称'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请输入课程名称' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _credits,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: '课程学分'),
              validator: (text) {
                final value = double.tryParse(text ?? '');
                return value == null || !value.isFinite || value <= 0
                    ? '请输入大于 0 的学分'
                    : null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _score,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: '预计成绩'),
              validator: (text) {
                final value = double.tryParse(text ?? '');
                return value == null ||
                        !value.isFinite ||
                        value < 0 ||
                        value > 100
                    ? '请输入 0～100 之间的成绩'
                    : null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(
              context,
              ProjectedCourse(
                id:
                    widget.course?.id ??
                    'simulation-${DateTime.now().microsecondsSinceEpoch}',
                name: _name.text.trim(),
                credits: double.parse(_credits.text),
                score: double.parse(_score.text),
                replaces: choices[_selection]?.replaces,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
